#!/bin/bash
set -e
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
usage() { echo "用法: $0 <IPv6地址/前缀> <IPv6网关>"; echo "示例: $0 2409:8c3c:900:177::28/64 2409:8c3c:900:177::1"; exit 1; }
if [ $# -ne 2 ]; then usage; error "参数数量错误"; fi
IPV6_ADDR="$1"
IPV6_GW="$2"
IPV6_PURE=${IPV6_ADDR%/*}
IPV6_PREFIX=${IPV6_ADDR#*/}
if [ "$(id -u)" != "0" ]; then error "请使用root权限运行此脚本"; fi
detect_os() {
    if [ -f /etc/centos-release ]; then
        OS="centos"
        info "检测到CentOS系统"
    elif [ -f /etc/debian_version ]; then
        OS="debian"
        info "检测到Debian系统"
    else
        error "不支持的操作系统"
    fi
}
get_active_interface() {
    info "正在检测活跃网卡..."
    ACTIVE_IF=$(ip route show default | awk '/default/ {print $5}' | head -n1)
    if [ -z "$ACTIVE_IF" ]; then
        ACTIVE_IF=$(ip -4 addr | grep -v 'LOOPBACK' | grep 'inet' | awk '{print $NF}' | sort | uniq | head -n1)
    fi
    if [ -z "$ACTIVE_IF" ]; then
        ACTIVE_IF=$(ip link show | grep -v LOOPBACK | grep -E '^[0-9]+:' | awk -F: '{print $2}' | tr -d ' ' | grep -v '^$' | head -n1)
    fi
    if [ -z "$ACTIVE_IF" ] || [ "$ACTIVE_IF" = "lo" ]; then
        info "自动检测网卡失败，以下是可用的网卡："
        ip link show | grep -v LOOPBACK | grep -E '^[0-9]+:' | awk -F: '{print $1 " - " $2}' | tr -d ' '
        read -p "请输入要配置的网卡名称（如eth0）：" ACTIVE_IF
        if [ -z "$ACTIVE_IF" ]; then error "网卡名称不能为空"; fi
    fi
    info "自动识别使用网卡: $ACTIVE_IF"
}
configure_centos() {
    IF_CFG="/etc/sysconfig/network-scripts/ifcfg-$ACTIVE_IF"
    if [ ! -f "$IF_CFG" ]; then error "网卡配置文件不存在：$IF_CFG"; fi
    cp "$IF_CFG" "${IF_CFG}.bak.$(date +%Y%m%d%H%M%S)"
    info "已备份原有配置文件"
    sed -i '/^IPV6INIT=/d' "$IF_CFG"
    echo "IPV6INIT=yes" >> "$IF_CFG"
    sed -i '/^IPV6ADDR=/d' "$IF_CFG"
    sed -i '/^IPV6_DEFAULTGW=/d' "$IF_CFG"
    cat >> "$IF_CFG" << EOF
IPV6ADDR=$IPV6_ADDR
IPV6_DEFAULTGW=$IPV6_GW
EOF
    success "CentOS IPv6 配置已写入 $IF_CFG"
}
configure_debian() {
    IF_CONF="/etc/network/interfaces.d/$ACTIVE_IF"
    if [ -f "$IF_CONF" ]; then
        cp "$IF_CONF" "${IF_CONF}.bak.$(date +%Y%m%d%H%M%S)"
        info "已备份原有网卡配置"
    fi
    cat > "$IF_CONF" << EOF
iface $ACTIVE_IF inet6 static
    address $IPV6_PURE
    netmask $IPV6_PREFIX
    gateway $IPV6_GW
EOF
    success "Debian IPv6 配置已写入规范路径：$IF_CONF"
}
restart_network() {
    info "正在重启网络服务..."
    if [ "$OS" = "centos" ]; then
        systemctl restart network
    elif [ "$OS" = "debian" ]; then
        if command -v systemctl &>/dev/null; then
            systemctl restart networking
        else
            /etc/init.d/networking restart
        fi
        ifdown "$ACTIVE_IF" && ifup "$ACTIVE_IF"
    fi
    sleep 2
    if ip -6 addr show "$ACTIVE_IF" 2>/dev/null | grep -q "$IPV6_PURE"; then
        success "IPv6配置生效成功"
        info "当前IPv6地址信息："
        ip -6 addr show "$ACTIVE_IF" | grep "inet6" | grep -v "fe80::"
    else
        info "IPv6配置可能需要手动激活"
        info "可以尝试执行：ip -6 addr add $IPV6_ADDR dev $ACTIVE_IF"
        info "以及：ip -6 route add default via $IPV6_GW dev $ACTIVE_IF"
    fi
}
main() {
    echo "======================================"
    echo "    自动网卡 + 传参式 IPv6 配置脚本"
    echo "======================================"
    detect_os
    get_active_interface
    info "待配置IPv6地址: $IPV6_ADDR"
    info "待配置IPv6网关: $IPV6_GW"
    if [ "$OS" = "centos" ]; then
        configure_centos
    elif [ "$OS" = "debian" ]; then
        configure_debian
    fi
    restart_network
    echo -e "\n${GREEN}全部配置完成！${NC}"
}
main
