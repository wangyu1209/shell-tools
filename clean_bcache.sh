#!/usr/bin/env bash
#
# bcache-clean.sh — 清理 bcache + 删除非系统盘所有分区
#
# 自动识别系统盘（挂载 / 的磁盘），只操作其他磁盘
#
# 用法: sudo bash bcache-clean.sh [--dry-run]
#
# ⚠  操作不可逆，数据将被全部销毁！

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

# ─── 识别系统盘 ────────────────────────────────────────────

SYSTEM_DISK=""

detect_system_disk() {
    # 找到挂载 / 的分区，提取其父磁盘
    local root_part
    root_part=$(findmnt -n -o SOURCE / | sed 's/[0-9]*$//' | sed 's/p[0-9]*$//')

    if [[ -z "$root_part" ]]; then
        log_error "无法识别系统盘，退出。"
        exit 1
    fi

    # 提取父设备名（如 /dev/sdc3 → /dev/sdc, /dev/nvme0n1p1 → /dev/nvme0n1）
    SYSTEM_DISK=$(lsblk -npo PKNAME "$root_part" | head -1)
    if [[ -z "$SYSTEM_DISK" ]]; then
        SYSTEM_DISK=$(echo "$root_part" | sed -E 's/(sd[a-z]+).*/\1/;s/(nvme[0-9]+n[0-9]+).*/\1/')
    fi

    log_info "检测到系统盘: ${SYSTEM_DISK}（将跳过此盘）"
}

get_target_disks() {
    # 返回所有非系统盘的磁盘设备
    local disks=()
    for dev in /dev/sd[a-z]; do
        [[ -b "$dev" ]] || continue
        if [[ "$dev" != "$SYSTEM_DISK" ]]; then
            disks+=("$dev")
        fi
    done
    # 也检查 nvme 盘（排除系统盘）
    for dev in /dev/nvme[0-9]n[0-9]; do
        [[ -b "$dev" ]] || continue
        if [[ "$dev" != "$SYSTEM_DISK" ]]; then
            disks+=("$dev")
        fi
    done
    echo "${disks[@]+"${disks[@]}"}"
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
        exit 1
    fi
    log_info "所有 bcache 设备均未挂载 ✓"
}

check_target_partitions_unmounted() {
    log_step "检查目标磁盘的分区是否已卸载"
    local target_disks
    target_disks=$(get_target_disks)
    local mounted=0

    for disk in $target_disks; do
        local disk_name
        disk_name=$(basename "$disk")
        for part in /dev/${disk_name}*; do
            [[ -b "$part" ]] || continue
            [[ "$part" == "$disk" ]] && continue
            if mount | grep -q "${part} "; then
                log_warn "分区 ${part} 仍在挂载中!"
                mounted=1
            fi
        done
    done

    if (( mounted )); then
        log_error "请先卸载目标磁盘的所有分区，然后重新运行此脚本。"
        exit 1
    fi
    log_info "目标磁盘的分区均未挂载 ✓"
}

# ─── 步骤 1: 停止缓存 ─────────────────────────────────────

stop_caching() {
    log_step "步骤 1/7: 将所有 bcache 设为 none 模式（停止缓存）"
    local found=0
    for bdev in /sys/block/bcache*; do
        [[ -d "$bdev" ]] || continue
        found=1
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
    if (( found == 0 )); then
        log_info "  没有找到 bcache 设备，跳过"
    fi
    sleep 2
}

# ─── 步骤 2: 分离后端设备 ──────────────────────────────────

detach_backing() {
    log_step "步骤 2/7: 分离所有后端设备"
    local found=0
    for bdev in /sys/block/bcache*; do
        [[ -d "$bdev" ]] || continue
        found=1
        local name
        name=$(basename "$bdev")
        local detach="${bdev}/bcache/detach"
        if [[ -f "$detach" ]]; then
            log_info "  分离 ${name}"
            run "echo 1 > ${detach}"
        fi
    done
    if (( found == 0 )); then
        log_info "  没有找到 bcache 设备，跳过"
    fi
    sleep 3
}

# ─── 步骤 3: 停止 cache_set ────────────────────────────────

stop_cache_set() {
    log_step "步骤 3/7: 注销所有 cache_set"

    local found=0
    for cs in /sys/fs/bcache/*-*-*-*-*; do
        [[ -d "$cs" ]] || continue
        found=1
        local uuid
        uuid=$(basename "$cs")

        if [[ -f "${cs}/stop" ]]; then
            log_info "  停止 cache_set: ${uuid}"
            run "echo 1 > ${cs}/stop"
        elif [[ -f "${cs}/unregister" ]]; then
            log_info "  注销 cache_set: ${uuid}"
            run "echo 1 > ${cs}/unregister"
        fi
    done

    if (( found == 0 )); then
        log_info "  没有找到已注册的 cache_set"
    fi
    sleep 3
}

# ─── 步骤 4: 确认 bcache 设备消失 ─────────────────────────

verify_bcache_gone() {
    log_step "步骤 4/7: 验证 bcache 块设备是否已消失"
    local remaining
    remaining=$(ls /sys/block/ 2>/dev/null | grep -E '^bcache' || true)
    if [[ -z "$remaining" ]]; then
        log_info "  所有 bcache 块设备已消失 ✓"
    else
        log_warn "  仍有 bcache 设备存在: ${remaining}"
        for bdev in $remaining; do
            run "echo 1 > /sys/block/${bdev}/bcache/stop" 2>/dev/null || true
        done
        sleep 2
    fi
}

# ─── 步骤 5: 擦除 bcache 超级块 ───────────────────────────

wipe_bcache_superblocks() {
    log_step "步骤 5/7: 擦除所有 bcache 超级块"

    local target_disks
    target_disks=$(get_target_disks)

    for disk in $target_disks; do
        local disk_name
        disk_name=$(basename "$disk")

        # 擦除整盘签名
        log_info "  擦除 ${disk} 整盘签名..."
        run "wipefs -af ${disk}"

        # 擦除每个分区签名
        for part in /dev/${disk_name}*; do
            [[ -b "$part" ]] || continue
            [[ "$part" == "$disk" ]] && continue
            log_info "  擦除 ${part} 签名..."
            run "wipefs -af ${part}"
        done
    done

    # 额外清理 nvme 缓存盘（如果存在且不是系统盘）
    if [[ -b /dev/nvme0n1 ]] && [[ "/dev/nvme0n1" != "$SYSTEM_DISK" ]]; then
        log_info "  擀除缓存盘 /dev/nvme0n1 上的 bcache 签名..."
        run "wipefs -af /dev/nvme0n1"
    fi
}

# ─── 步骤 6: 删除非系统盘所有分区 ─────────────────────────

remove_all_partitions() {
    log_step "步骤 6/7: 删除非系统盘的所有分区"

    local target_disks
    target_disks=$(get_target_disks)

    if [[ -z "$target_disks" ]]; then
        log_warn "  没有找到需要处理的非系统盘"
        return
    fi

    for disk in $target_disks; do
        local disk_name
        disk_name=$(basename "$disk")

        # 列出当前分区
        local parts
        parts=$(lsblk -lnpo NAME "$disk" | tail -n +2 | tr -s ' ')
        if [[ -n "$parts" ]]; then
            log_info "  ${disk} 当前分区:"
            echo "$parts" | while read -r p; do
                local size
                size=$(lsblk -npo SIZE "$p" 2>/dev/null | tr -d ' ')
                echo "    $p  ($size)"
            done
        fi

        # 使用 sfdisk 删除分区表（最彻底）
        log_info "  删除 ${disk} 全部分区..."
        run "wipefs -af ${disk}"

        # 用 sfdisk 清除 GPT 和 MBR 分区表
        run "sfdisk --delete ${disk}" 2>/dev/null || true

        # 双保险：用 dd 覆盖前 100MB 和后 100MB
        log_info "  覆盖 ${disk} 前 100MB + 后 100MB..."
        run "dd if=/dev/zero of=${disk} bs=1M count=100 conv=notrunc 2>/dev/null"
        local disk_size_mb
        disk_size_mb=$(blockdev --getsize64 "$disk" 2>/dev/null)
        if [[ -n "$disk_size_mb" ]] && (( disk_size_mb > 209715200 )); then
            local seek_mb=$(( (disk_size_mb / 1048576) - 100 ))
            run "dd if=/dev/zero of=${disk} bs=1M seek=${seek_mb} count=100 conv=notrunc 2>/dev/null"
        fi

        # 再次 wipefs 确保干净
        run "wipefs -af ${disk}"

        # 通知内核重读分区表
        run "partprobe ${disk}" 2>/dev/null || true

        log_info "  ${disk} 已清理完毕 ✓"
    done

    sleep 2
}

# ─── 步骤 7: 卸载重载模块 ─────────────────────────────────

reload_module() {
    log_step "步骤 7/7: 重载 bcache 内核模块"

    if lsmod | grep -q bcache; then
        log_info "  卸载 bcache 模块..."
        run "modprobe -r bcache" || {
            log_warn "  常规卸载失败，尝试强制卸载..."
            run "rmmod -f bcache" || log_error "  强制卸载失败"
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
    echo "--- bcache 设备 ---"
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
    echo "--- 非系统盘状态 ---"
    local target_disks
    target_disks=$(get_target_disks)
    for disk in $target_disks; do
        local parts
        parts=$(lsblk -lnpo NAME "$disk" 2>/dev/null | tail -n +2 || true)
        if [[ -z "$parts" ]]; then
            log_info "  ${disk}: 无分区，已恢复为裸盘 ✓"
        else
            log_warn "  ${disk}: 仍有分区存在:"
            lsblk "$disk" 2>/dev/null
        fi
    done

    echo ""
    echo "--- 系统盘状态（未修改）---"
    lsblk "$SYSTEM_DISK" 2>/dev/null || true

    echo ""
    echo "--- 全局 lsblk ---"
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -v loop
    echo ""

    log_info "========================================="
    log_info "  全部清理完成！"
    log_info "  · bcache 已全部移除"
    log_info "  · 非系统盘分区已全部删除"
    log_info "  · 系统盘 ${SYSTEM_DISK} 未受影响"
    log_info "========================================="
    log_info ""
    log_info "现在可以用 fdisk/parted 对裸盘重新分区了。"
    log_info "例如: parted /dev/sda mklabel gpt"
    log_info "      parted /dev/sda mkpart primary 0% 100%"
}

# ─── 帮助 ──────────────────────────────────────────────────

show_summary() {
    echo ""
    echo "========================================="
    echo "  bcache 清理 + 分区清除脚本"
    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        echo -e "  模式: ${YELLOW}DRY-RUN（仅预览）${NC}"
    else
        echo -e "  模式: ${RED}正式执行${NC}"
    fi
    echo "========================================="
    echo ""

    detect_system_disk

    echo ""
    echo "目标磁盘（将被清理）:"
    local target_disks
    target_disks=$(get_target_disks)
    for disk in $target_disks; do
        local size
        size=$(lsblk -npo SIZE "$disk" | tr -d ' ')
        echo "  $disk  $size"
    done

    echo ""
    echo "跳过的磁盘:"
    echo "  $SYSTEM_DISK  (系统盘)"
    echo ""

    echo "当前 bcache 设备:"
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E 'bcache' || echo "  (无)"
    echo ""

    echo "当前磁盘分区:"
    for disk in $target_disks; do
        lsblk "$disk" 2>/dev/null || true
    done
    echo ""

    echo "执行步骤:"
    echo "  1. bcache 设为 none 模式（停止缓存）"
    echo "  2. 分离所有后端设备"
    echo "  3. 注销 cache_set"
    echo "  4. 验证 bcache 设备消失"
    echo "  5. 擦除 bcache 超级块签名"
    echo "  6. 删除非系统盘所有分区（dd + wipefs + sfdisk）"
    echo "  7. 重载 bcache 模块"
    echo ""
}

# ─── 主流程 ────────────────────────────────────────────────

main() {
    check_root
    show_summary

    if [[ "$DRY_RUN" != "--dry-run" ]]; then
        echo -e "${RED}⚠  此操作将:${NC}"
        echo -e "${RED}   · 销毁所有 bcache 数据${NC}"
        echo -e "${RED}   · 删除目标磁盘的全部分区表和数据${NC}"
        echo ""
        read -rp "确认继续? (输入 yes): " confirm
        if [[ "$confirm" != "yes" ]]; then
            log_info "已取消。"
            exit 0
        fi
    fi

    check_mount
    check_target_partitions_unmounted
    stop_caching
    detach_backing
    stop_cache_set
    verify_bcache_gone
    wipe_bcache_superblocks
    remove_all_partitions
    reload_module
    final_verify
}

main "$@"
