#!/usr/bin/env bash
#
# bcache-clean.sh — 针对当前环境清理全部 bcache 设备
#
# 结构: nvme0n1(缓存盘) → sda1~6 / sdc1~6(后端盘) → bcache0~11
#
# 用法: sudo bash bcache-clean.sh [--dry-run]
#
# ⚠  操作不可逆，请确保 bcache 上的数据已备份且无挂载。

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

DRY_RUN=${1:-""}

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()  { echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }

run() {
    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} $*"
    else
        log_info "执行: $*"
        eval "$@" 2>&1 || true
    fi
}

# ─── 前置检查 ──────────────────────────────────────────────

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用 root 权限运行: sudo bash $0"
        exit 1
    fi
}

check_mount() {
    log_step "检查是否有 bcache 设备被挂载"
    local mounted=0
    for dev in /dev/bcache*; do
        [[ -b "$dev" ]] || continue
        if mount | grep -q "$dev"; then
            log_warn "设备 $dev 仍处于挂载状态!"
            mounted=1
        fi
    done
    if (( mounted )); then
        log_error "请先卸载所有 bcache 设备，然后重新运行此脚本。"
        log_error "提示: umount /dev/bcache*"
        exit 1
    fi
    log_info "所有 bcache 设备均未挂载 ✓"
}

# ─── 步骤 1: 停止缓存 ─────────────────────────────────────

stop_caching() {
    log_step "步骤 1/6: 将所有 bcache 设为 none 模式（停止缓存）"
    for bdev in /sys/block/bcache*; do
        [[ -d "$bdev" ]] || continue
        local name
        name=$(basename "$bdev")
        local mode_file="${bdev}/bcache/cache_mode"
        if [[ -f "$mode_file" ]]; then
            local current
            current=$(cat "$mode_file")
            log_info "  ${name}: 当前模式 → ${current}"
            run "echo none > ${mode_file}"
        fi
    done
    sleep 2
}

# ─── 步骤 2: 分离后端设备 ──────────────────────────────────

detach_backing() {
    log_step "步骤 2/6: 分离所有后端设备（从 cache_set 断开）"
    for bdev in /sys/block/bcache*; do
        [[ -d "$bdev" ]] || continue
        local name
        name=$(basename "$bdev")
        local detach="${bdev}/bcache/detach"
        if [[ -f "$detach" ]]; then
            log_info "  分离 ${name}"
            run "echo 1 > ${detach}"
        fi
    done
    sleep 3
}

# ─── 步骤 3: 停止 cache_set ────────────────────────────────

stop_cache_set() {
    log_step "步骤 3/6: 注销所有 cache_set"

    local found=0
    for cs in /sys/fs/bcache/*-*-*-*-*; do
        [[ -d "$cs" ]] || continue
        found=1
        local uuid
        uuid=$(basename "$cs")
        local stop="${cs}/stop"
        if [[ -f "$stop" ]]; then
            log_info "  停止 cache_set: ${uuid}"
            run "echo 1 > ${stop}"
        elif [[ -f "${cs}/unregister" ]]; then
            log_info "  注销 cache_set: ${uuid}"
            run "echo 1 > ${cs}/unregister"
        fi
    done

    if (( found == 0 )); then
        log_info "  没有找到已注册的 cache_set（可能已自动清理）"
    fi
    sleep 3
}

# ─── 步骤 4: 确认 bcache 设备消失 ─────────────────────────

verify_bcache_gone() {
    log_step "步骤 4/6: 验证 bcache 块设备是否已消失"
    local remaining
    remaining=$(ls /sys/block/ | grep -E '^bcache' || true)
    if [[ -z "$remaining" ]]; then
        log_info "  所有 bcache 块设备已消失 ✓"
    else
        log_warn "  仍有 bcache 设备存在: ${remaining}"
        log_warn "  尝试强制移除..."
        for bdev in $remaining; do
            local dev_path="/dev/${bdev}"
            if [[ -b "$dev_path" ]]; then
                run "echo 1 > /sys/block/${bdev}/bcache/stop" 2>/dev/null || true
            fi
        done
        sleep 2
    fi
}

# ─── 步骤 5: 擦除 bcache 超级块 ───────────────────────────

wipe_superblocks() {
    log_step "步骤 5/6: 擦除所有相关设备上的 bcache 超级块"

    # ---- 后端设备: sda 和 sdc 的所有分区 ----
    log_info "  清理后端设备 (sda/sdc 分区)..."
    local backing_parts=(
        /dev/sda1 /dev/sda2 /dev/sda3 /dev/sda4 /dev/sda5 /dev/sda6
        /dev/sdc1 /dev/sdc2 /dev/sdc3 /dev/sdc4 /dev/sdc5 /dev/sdc6
    )

    for part in "${backing_parts[@]}"; do
        if [[ -b "$part" ]]; then
            log_info "  擦除 ${part}"
            run "wipefs -af ${part}"
        else
            log_warn "  ${part} 不存在，跳过"
        fi
    done

    # ---- 同时清理整盘签名 ----
    log_info "  清理整盘签名 (sda/sdc)..."
    for disk in /dev/sda /dev/sdc; do
        if [[ -b "$disk" ]]; then
            if wipefs -n "$disk" 2>/dev/null | grep -qi bcache; then
                log_info "  擦除 ${disk} 上的 bcache 签名"
                run "wipefs -af ${disk}"
            else
                log_info "  ${disk} 无 bcache 签名，跳过"
            fi
        fi
    done

    # ---- 缓存设备: nvme0n1 ----
    log_info "  清理缓存设备 (nvme0n1)..."
    if [[ -b /dev/nvme0n1 ]]; then
        local has_bcache
        has_bcache=$(wipefs -n /dev/nvme0n1 2>/dev/null | grep -ci bcache || true)
        if (( has_bcache > 0 )); then
            log_info "  擦除 /dev/nvme0n1 上的 bcache 缓存签名"
            run "wipefs -af /dev/nvme0n1"
        else
            log_info "  /dev/nvme0n1 无 bcache 签名，跳过"
        fi
    fi
}

# ─── 步骤 6: 卸载重载模块 ─────────────────────────────────

reload_module() {
    log_step "步骤 6/6: 重载 bcache 内核模块"

    if lsmod | grep -q bcache; then
        log_info "  卸载 bcache 模块..."
        run "modprobe -r bcache" || {
            log_warn "  常规卸载失败，尝试强制卸载..."
            run "rmmod -f bcache" || log_error "  强制卸载失败，请手动处理"
        }
        sleep 1
    fi

    log_info "  重新加载 bcache 模块..."
    run "modprobe bcache"
    log_info "  bcache 模块已重载 ✓"
}

# ─── 最终验证 ──────────────────────────────────────────────

final_verify() {
    log_step "最终验证"

    echo ""
    echo "--- bcache 块设备 ---"
    local bcache_devs
    bcache_devs=$(ls /sys/block/ 2>/dev/null | grep -E '^bcache' || true)
    if [[ -z "$bcache_devs" ]]; then
        log_info "  没有残留 bcache 设备 ✓"
    else
        log_warn "  残留: $bcache_devs"
    fi

    echo ""
    echo "--- cache_set ---"
    local cache_sets
    cache_sets=$(ls /sys/fs/bcache/ 2>/dev/null | grep -E '-' || true)
    if [[ -z "$cache_sets" ]]; then
        log_info "  没有残留 cache_set ✓"
    else
        log_warn "  残留: $cache_sets"
    fi

    echo ""
    echo "--- lsblk 输出 ---"
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -v loop
    echo ""

    log_info "========================================="
    log_info "  bcache 清理完成！"
    log_info "  现在 sda/sdc 的分区可作为普通块设备使用"
    log_info "========================================="
}

# ─── 主流程 ────────────────────────────────────────────────

main() {
    check_root

    echo ""
    echo "========================================="
    echo "  bcache 清理脚本"
    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        echo -e "  模式: ${YELLOW}DRY-RUN（仅预览）${NC}"
    else
        echo -e "  模式: ${RED}正式执行${NC}"
    fi
    echo "========================================="
    echo ""
    echo "当前 bcache 设备:"
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E 'bcache|sda|sdc|nvme'
    echo ""

    if [[ "$DRY_RUN" != "--dry-run" ]]; then
        echo -e "${RED}⚠  此操作将销毁所有 bcache 数据!${NC}"
        read -rp "确认继续? (输入 yes): " confirm
        if [[ "$confirm" != "yes" ]]; then
            log_info "已取消。"
            exit 0
        fi
    fi

    check_mount
    stop_caching
    detach_backing
    stop_cache_set
    verify_bcache_gone
    wipe_superblocks
    reload_module
    final_verify
}

main "$@"
