#!/bin/bash

trap 'rm -f "$0" 2>/dev/null' EXIT

if [ "$EUID" -ne 0 ]; then
    printf '\033[1;31m错误：请使用 root 权限运行此脚本（例如：sudo %s）\033[0m\n' "$0"
    exit 1
fi

ESC=$'\033'
R="${ESC}[0m"
HD="${ESC}[1;36m"
LB="${ESC}[1;37m"
VA="${ESC}[0;37m"
HI="${ESC}[1;38;5;114m"
WA="${ESC}[1;31m"

LINE="${ESC}[1;36m------------------------------${R}"

dlen() {
    local w
    w=$(printf '%s' "$1" | wc -L 2>/dev/null | tr -dc '0-9')
    [ -z "$w" ] && w=${#1}
    printf '%s' "$w"
}

tcol() {
    local t="$1" w="$2" c="$3" d p
    d=$(dlen "$t"); p=$((w - d)); [ "$p" -lt 0 ] && p=0
    [ -n "$c" ] && printf '%s%s%s' "$c" "$t" "$R"
    [ -z "$c" ] && printf '%s%s%s' "$VA" "$t" "$R"
    printf '%*s' "$p" ''
}

kv() {
    local key="$1" val="$2" d p
    d=$(dlen "$key"); p=$((18 - d)); [ "$p" -lt 0 ] && p=0
    printf '%s%s%s%*s%s%s\n' "$LB" "$key" "$R" "$p" '' "$VA" "$val"
}

hdr() {
    printf '%s\n%s%s%s\n' "$LINE" "$HD" "$1" "$R"
}

hdr2() {
    printf '\n%s\n%s%s%s\n' "$LINE" "$HD" "$1" "$R"
}

safe_add() { awk "BEGIN{a=$1+0; b=$2+0; print a+b}"; }

get_ips() {
    ip -4 addr show "$1" 2>/dev/null | awk '/inet /{gsub(/\/.*/, "", $2); printf $2" "}'
}

# ═══════════════ 基本信息 ═══════════════

hdr "基本信息"

kv "主机名" "$(hostname)"

os_arch=$(uname -m)
os_name=$(awk -F= '/^PRETTY_NAME=/{gsub(/"/, "", $2); print $2}' /etc/os-release 2>/dev/null)
[ -z "$os_name" ] && [ -f /etc/redhat-release ] && os_name=$(cat /etc/redhat-release)
kv "系统信息" "${os_name:-未知} (${os_arch})"

kv "内核版本" "$(uname -r)"

if [ -f /etc/redhat-release ]; then
    sys_ver=$(cat /etc/redhat-release 2>/dev/null)
elif [ -f /etc/os-release ]; then
    sys_ver=$(awk -F= '/^VERSION=/{gsub(/"/, "", $2); print $2}' /etc/os-release 2>/dev/null)
    [ -z "$sys_ver" ] && sys_ver="$os_name"
fi
[ -n "$sys_ver" ] && kv "系统版本" "$sys_ver"

kv "当前时间" "$(date '+%Y-%m-%d %H:%M:%S')"

boot_time=$(uptime -s 2>/dev/null)
if [ -z "$boot_time" ]; then
    boot_sec=$(awk '{printf "%d", $1}' /proc/uptime 2>/dev/null)
    boot_time=$(date -d "-${boot_sec} sec" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
fi
[ -n "$boot_time" ] && kv "启动时间" "$boot_time"

up_str=$(uptime -p 2>/dev/null | sed 's/^up //')
[ -z "$up_str" ] && up_str=$(uptime 2>/dev/null | sed 's/.*up /up /; s/,.*//')
[ -n "$up_str" ] && kv "运行时长" "${HI}${up_str}${R}"

model=$(dmidecode -t 1 2>/dev/null | grep 'Product Name' | awk 'NR==1{for(i=3;i<=NF;i++) printf $i" "; print ""}')
[ -n "$model" ] && kv "机器型号" "$model"

sn=$(dmidecode -t 1 2>/dev/null | grep 'Serial Number' | awk 'NR==1{print $3}')
[ -n "$sn" ] && kv "序列号" "$sn"

ipmi_ip=$(ipmitool lan print 2>/dev/null | awk -F: '
    /^[[:space:]]*IP Address[[:space:]]+:/ && !/Source/ {
        gsub(/^[[:space:]]+|[[:space:]]+$/,"",$2); print $2; exit
    }')
[ -n "$ipmi_ip" ] && kv "IPMI地址" "${HI}${ipmi_ip}${R}"

# ═══════════════ CPU 信息 ═══════════════

hdr2 "CPU 信息"

phy_cnt=$(awk -F: '/physical id/{print $2}' /proc/cpuinfo | sort -un | wc -l)
log_cnt=$(awk '/^processor/' /proc/cpuinfo | wc -l)
cpu_model=$(grep 'model name' /proc/cpuinfo | head -1 | awk -F: '{gsub(/^ /,"",$2); print $2}')

kv "物理CPU" "${phy_cnt} 颗"
kv "逻辑核心" "${log_cnt} 核"
kv "CPU型号" "$cpu_model"

# ═══════════════ 内存信息 ═══════════════

hdr2 "内存信息"

_memtmp=$(mktemp /tmp/_hwmem.XXXXXX)
dmidecode -t memory 2>/dev/null | awk '
    BEGIN{loc="";sz="";sp="";mf="";im=0}
    /^Memory Device$/{
        if(im&&sz!="No Module Installed"&&sz!="") print loc"|"sz"|"sp"|"mf
        loc="";sz="";sp="";mf="";im=1;next
    }
    im{
        if(/^\tLocator:/){loc=$0;sub(/^\tLocator:[ \t]*/,"",loc);gsub(/[ \t]+$/,"",loc)}
        if(/^\tSize:/){sz=$0;sub(/^\tSize:[ \t]*/,"",sz);gsub(/[ \t]+$/,"",sz)}
        if(/^\tSpeed:/){sp=$0;sub(/^\tSpeed:[ \t]*/,"",sp);gsub(/[ \t]+$/,"",sp)}
        if(/^\tManufacturer:/){mf=$0;sub(/^\tManufacturer:[ \t]*/,"",mf);gsub(/[ \t]+$/,"",mf)}
    }
    END{if(im&&sz!="No Module Installed"&&sz!="") print loc"|"sz"|"sp"|"mf}
' > "$_memtmp"

tcol "插槽位置" 18; tcol "容量" 14; tcol "频率" 14; printf '%s\n' "厂商"

mem_cnt=0
while IFS='|' read -r loc sz sp mf; do
    [ -z "$loc" ] && continue
    mem_cnt=$((mem_cnt + 1))
    tcol "$loc" 18; tcol "$sz" 14; tcol "$sp" 14; printf '%s\n' "$mf"
done < "$_memtmp"
rm -f "$_memtmp"

total_mb=$(free -m | awk 'NR==2{printf "%d", $2}')
total_gb=$(awk "BEGIN{printf \"%.0f\",${total_mb}/1024}")
echo
kv "内存合计" "${mem_cnt} 条  ${total_mb} MB (约 ${total_gb} GB)"

# ═══════════════ 磁盘信息 ═══════════════

hdr2 "磁盘信息"

tcol "设备" 16; tcol "大小" 12; tcol "类型" 10; tcol "接口" 10; printf '%s\n' "序列号"

_dtmp=$(mktemp /tmp/_hwdisk.XXXXXX)

for dev in $(lsblk -d -n -o NAME 2>/dev/null | grep -v 'loop\|rom\|sr\|zram'); do
    size=$(lsblk -dn -o SIZE "/dev/${dev}" 2>/dev/null | tr -d ' ')
    rota=$(cat "/sys/block/${dev}/queue/rotational" 2>/dev/null)
    tran=$(lsblk -dn -o TRAN "/dev/${dev}" 2>/dev/null)

    dsn=$(lsblk -dn -o SERIAL "/dev/${dev}" 2>/dev/null)
    [ -z "$dsn" ] && dsn=$(cat "/sys/block/${dev}/device/serial" 2>/dev/null)
    [ -z "$dsn" ] && dsn="-"

    if [ "$rota" = "0" ]; then dtype="SSD"; dc="$HI"
    elif [ "$rota" = "1" ]; then dtype="HDD"; dc="$VA"
    else dtype="未知"; dc=""
    fi

    case "$tran" in
        sata) ifc="SATA" ;; sas) ifc="SAS" ;;
        nvme) ifc="NVMe" ;; usb) ifc="USB" ;; *) ifc="-" ;;
    esac

    tcol "/dev/${dev}" 16; tcol "$size" 12
    tcol "$dtype" 10 "$dc"; tcol "$ifc" 10; printf '%s\n' "$dsn"
    printf '%s %s\n' "$size" "$dtype" >> "$_dtmp"
done

echo
printf '%s硬盘统计:%s\n' "$LB" "$R"
awk '{print $1, $2}' "$_dtmp" | sort | uniq -c | while read cnt rest; do
    printf '%d 块  %s\n' "$cnt" "$rest"
done

ssd_cnt=$(awk '/ SSD$/{c++} END{print c+0}' "$_dtmp")
hdd_cnt=$(awk '/ HDD$/{c++} END{print c+0}' "$_dtmp")
disk_total=$(safe_add "$ssd_cnt" "$hdd_cnt")
echo
kv "类型汇总" "SSD: ${ssd_cnt} 块  HDD: ${hdd_cnt} 块  合计: ${disk_total} 块"
rm -f "$_dtmp"

# ═══════════════ 网卡信息 ═══════════════

hdr2 "网卡信息"

tcol "接口" 14; tcol "速率" 12; tcol "状态" 8
tcol "MAC" 18; tcol "IP地址" 16; printf '%s\n' "型号"

for iface in $(ls /sys/class/net/ 2>/dev/null | grep -v "^lo$"); do
    [ -d "/sys/class/net/${iface}/device" ] || continue

    pci_addr=$(basename "$(readlink -f "/sys/class/net/${iface}/device")" 2>/dev/null)
    nic_model="未知"
    [ -n "$pci_addr" ] && nic_model=$(lspci -s "${pci_addr}" 2>/dev/null | sed 's/^[^ ]* //; s/ (rev[^)]*)//')

    speed_val=$(cat "/sys/class/net/${iface}/speed" 2>/dev/null)
    if [ -n "$speed_val" ] && [ "$speed_val" -gt 0 ] 2>/dev/null; then
        [ "$speed_val" -ge 1000 ] && speed_str="$((speed_val / 1000))Gbps" || speed_str="${speed_val}Mbps"
    else
        speed_str=$(ethtool "${iface}" 2>/dev/null | awk '/Speed:/{print $2}')
        speed_str=${speed_str:-"N/A"}
    fi

    state=$(cat "/sys/class/net/${iface}/operstate" 2>/dev/null)
    if [ "$state" = "up" ]; then st="UP"; stc="$HI"; else st="DOWN"; stc="$WA"; fi

    mac=$(cat "/sys/class/net/${iface}/address" 2>/dev/null)

    ips=$(get_ips "$iface")
    [ -z "$ips" ] && ips="-"

    tcol "$iface" 14; tcol "$speed_str" 12
    tcol "$st" 8 "$stc"; tcol "$mac" 18; tcol "$ips" 16 "$HI"
    printf '%s\n' "$nic_model"
done
