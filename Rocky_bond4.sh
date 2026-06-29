#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()  { echo -e "${CYAN}[STEP]${NC}  $*"; }

check_env() {
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用 root 执行"
        exit 1
    fi
    if ! command -v nmcli &>/dev/null; then
        log_error "未检测到 nmcli"
        exit 1
    fi
    if ! lsmod | grep -q bonding; then
        modprobe bonding
    fi
}

get_network_info() {
    log_step "获取公网 IP..."
    local public_ip=""
    for svc in "https://ifconfig.me" "https://api.ipify.org" "https://icanhazip.com" "https://checkip.amazonaws.com" "https://ipinfo.io/ip"; do
        public_ip=$(curl -s --connect-timeout 5 "$svc" 2>/dev/null | tr -d '[:space:]')
        [[ "$public_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && break
        public_ip=""
    done

    if [[ -z "$public_ip" ]]; then
        log_error "无法获取公网 IP"
        read -rp "手动输入公网 IP: " public_ip
        [[ ! "$public_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && log_error "IP 格式错误" && exit 1
    fi

    PUBLIC_IP="$public_ip"
    LAST_OCTET=$(echo "$public_ip" | awk -F'.' '{print $4}')
    INTERNAL_IP="192.168.102.${LAST_OCTET}"

    GATEWAY=$(ip route show default | awk '/default/ {print $3}' | head -1)
    if [[ -z "$GATEWAY" ]]; then
        log_error "无法自动获取默认网关"
        read -rp "手动输入网关: " GATEWAY
    fi

    DNS=$(grep "^nameserver" /etc/resolv.conf | awk '{print $2}' | head -1)
    if [[ -z "$DNS" ]]; then
        DNS="223.5.5.5"
        log_warn "未检测到 DNS，使用默认: ${DNS}"
    fi

    log_info "公网 IP:  ${PUBLIC_IP}"
    log_info "内网 IP:  ${INTERNAL_IP}/24"
    log_info "网关:     ${GATEWAY}"
    log_info "DNS:      ${DNS}"
}

select_slaves() {
    log_step "扫描可用网卡..."
    echo ""
    local idx=1
    declare -gA IFACE_MAP
    while IFS=: read -r iface iftype; do
        [[ "$iface" =~ ^(lo|bond|dummy|bridge|tun|tap|veth|virbr) ]] && continue
        local state
        state=$(nmcli -t -f DEVICE,STATE device status | grep "^${iface}:" | cut -d: -f2)
        printf "  [%d] %-15s %s\n" "$idx" "$iface" "${state:-unknown}"
        IFACE_MAP[$idx]="$iface"
        ((idx++))
    done < <(nmcli -t -f DEVICE,TYPE device status)

    echo ""
    read -rp "选择加入 bond4 的网卡编号（空格分隔，如 1 2）: " -a selections
    [[ ${#selections[@]} -lt 2 ]] && log_warn "LACP 建议至少 2 个接口"

    SLAVE_IFACES=()
    for sel in "${selections[@]}"; do
        [[ -z "${IFACE_MAP[$sel]:-}" ]] && log_error "无效选择: ${sel}" && exit 1
        SLAVE_IFACES+=("${IFACE_MAP[$sel]}")
    done
    log_info "子接口: ${SLAVE_IFACES[*]}"
}

select_mode() {
    echo ""
    echo "  [0] balance-rr     mode=0"
    echo "  [1] active-backup  mode=1"
    echo "  [2] balance-xor    mode=2"
    echo "  [3] broadcast      mode=3"
    echo "  [4] 802.3ad (LACP) mode=4  ← 推荐"
    echo "  [5] balance-tlb    mode=5"
    echo "  [6] balance-alb    mode=6"
    echo ""
    read -rp "选择 Bond 模式 [默认 4]: " mode_choice
    mode_choice=${mode_choice:-4}

    case "$mode_choice" in
        0) BOND_MODE="balance-rr"    ;;
        1) BOND_MODE="active-backup" ;;
        2) BOND_MODE="balance-xor"   ;;
        3) BOND_MODE="broadcast"     ;;
        4) BOND_MODE="802.3ad"       ;;
        5) BOND_MODE="balance-tlb"   ;;
        6) BOND_MODE="balance-alb"   ;;
        *) log_error "无效"; exit 1  ;;
    esac
    log_info "模式: ${BOND_MODE}"
}

clean_existing() {
    if nmcli connection show bond4 &>/dev/null; then
        log_warn "已存在 bond4 连接"
        read -rp "删除并重新配置？(y/n): " choice
        if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
            nmcli connection delete bond4 2>/dev/null || true
            nmcli -t -f NAME connection show | grep "bond4" | xargs -r -I{} nmcli connection delete "{}" 2>/dev/null || true
        else
            exit 0
        fi
    fi
}

apply_config() {
    log_step "配置 bond4..."

    nmcli connection add type bond con-name bond4 ifname bond4 \
        bond.options "mode=${BOND_MODE},miimon=100,xmit_hash_policy=layer3+4"

    nmcli connection modify bond4 \
        ipv4.method manual \
        ipv4.addresses "${PUBLIC_IP}/26" \
        ipv4.gateway "${GATEWAY}" \
        ipv4.dns "${DNS}" \
        +ipv4.addresses "${INTERNAL_IP}/24" \
        ipv6.method disabled

    for iface in "${SLAVE_IFACES[@]}"; do
        local old_con
        old_con=$(nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | grep ":${iface}$" | cut -d: -f1)
        [[ -n "$old_con" ]] && nmcli connection down "$old_con" 2>/dev/null || true
        nmcli connection delete "${iface}" 2>/dev/null || true

        nmcli connection add type bond-slave con-name "${iface}-bond4" ifname "${iface}" master bond4
    done

    nmcli connection up bond4
    for iface in "${SLAVE_IFACES[@]}"; do
        nmcli connection up "${iface}-bond4" 2>/dev/null || true
    done
}

verify() {
    log_step "验证状态..."
    echo ""
    echo "========= bond4 接口 ========="
    ip addr show bond4
    echo ""
    echo "========= bonding 状态 ========"
    cat /proc/net/bonding/bond4
    echo ""
    echo "========= 路由表 =============="
    ip route show dev bond4
    echo ""
    echo "========= DNS ================="
    grep "nameserver" /etc/resolv.conf
}

summary() {
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    printf "║  公网 IP:  %-38s║\n" "${PUBLIC_IP}/26"
    printf "║  内网 IP:  %-38s║\n" "${INTERNAL_IP}/24"
    printf "║  网关:     %-38s║\n" "${GATEWAY}"
    printf "║  DNS:      %-38s║\n" "${DNS}"
    printf "║  Bond:     %-38s║\n" "bond4 (${BOND_MODE})"
    printf "║  子接口:   %-38s║\n" "${SLAVE_IFACES[*]}"
    echo "╚══════════════════════════════════════════════════╝"
}

main() {
    check_env
    get_network_info
    clean_existing
    select_slaves
    select_mode

    echo ""
    read -rp "确认执行？(y/n): " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && log_info "已取消" && exit 0

    apply_config
    verify
    summary
}

main "$@"