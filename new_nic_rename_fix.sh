#!/bin/bash
set -euo pipefail

UDEV_RULES="/etc/udev/rules.d/70-persistent-net.rules"
NETWORK_SCRIPTS="/etc/sysconfig/network-scripts"
BACKUP_DIR="/tmp/nic_rename_backup_$(date +%Y%m%d_%H%M%S)"
UDEV_DIR="/etc/udev/rules.d"

if [ "$(id -u)" -ne 0 ]; then
    echo "错误：必须使用 root 用户执行此脚本！"
    exit 1
fi

mkdir -p "$BACKUP_DIR"
[ -f "$UDEV_RULES" ] && cp -a "$UDEV_RULES" "$BACKUP_DIR/"
cp -a "$NETWORK_SCRIPTS"/ifcfg-* "$BACKUP_DIR/" 2>/dev/null
echo "备份完成：$BACKUP_DIR"

echo -e "\n=================================================="
echo "           清理所有冲突网卡命名规则            "
echo "=================================================="

rm -f ${UDEV_DIR}/70-persistent-ipoib.rules
rm -f ${UDEV_DIR}/*persistent-net-*.rules
rm -f ${UDEV_DIR}/[0-9][0-9]-net*.rules
rm -f ${UDEV_DIR}/*custom*.rules
rm -f ${UDEV_DIR}/99-*.rules
rm -f ${UDEV_DIR}/*net-names*.rules
rm -f ${UDEV_DIR}/80-*.rules
rm -f ${UDEV_DIR}/60-*.rules

echo "所有冲突UDEV规则已清理完毕！"
echo "仅保留默认规则：$UDEV_RULES"
echo "=================================================="

echo "====================================="
echo "        当前活跃（UP）物理网卡        "
echo "====================================="
echo "序号	网卡名		MAC地址		状态"
echo "-------------------------------------"

index=1
for nic in $(ls /sys/class/net | grep -v '^lo$'); do
    state=$(cat /sys/class/net/"$nic"/operstate 2>/dev/null)
    if [ "$state" = "up" ]; then
        mac=$(cat /sys/class/net/"$nic"/address)
        echo "$index	$nic		$mac	$state"
        index=$((index+1))
    fi
done

echo "-------------------------------------"
echo "直接复制上方网卡名填写即可！"
echo "====================================="

read -p "请输入旧网卡名(空格分隔)：" OLD_NICS
[ -z "$OLD_NICS" ] && { echo "旧网卡名不能为空！"; exit 1; }

read -p "请输入对应新网卡名(数量一致)：" NEW_NICS

read -ra OLD_ARR <<< "$OLD_NICS"
read -ra NEW_ARR <<< "$NEW_NICS"
if [ ${#OLD_ARR[@]} -ne ${#NEW_ARR[@]} ]; then
    echo "新旧网卡数量不匹配！"
    exit 1
fi

echo -e "\n===== 即将执行重命名 ====="
for i in "${!OLD_ARR[@]}"; do
    echo "  ${OLD_ARR[$i]}  →  ${NEW_ARR[$i]}"
done
read -p "确认执行？(y/n)：" CONFIRM
[ "$CONFIRM" != "y" ] && { echo "已取消操作"; exit 0; }

> "$UDEV_RULES"
for i in "${!OLD_ARR[@]}"; do
    old_nic="${OLD_ARR[$i]}"
    new_nic="${NEW_ARR[$i]}"

    [ ! -d "/sys/class/net/$old_nic" ] && { echo "网卡 $old_nic 不存在，跳过"; continue; }
    old_mac=$(cat "/sys/class/net/$old_nic"/address)
    [ -z "$old_mac" ] && { echo "无法读取 $old_nic MAC，跳过"; continue; }

    echo "SUBSYSTEM==\"net\",ATTR{address}==\"$old_mac\",NAME=\"$new_nic\"" >> "$UDEV_RULES"
    echo "写入规则：$old_nic → $new_nic"

    if [ "$old_nic" != "$new_nic" ]; then
        old_cfg="$NETWORK_SCRIPTS/ifcfg-$old_nic"
        new_cfg="$NETWORK_SCRIPTS/ifcfg-$new_nic"
        if [ -f "$old_cfg" ]; then
            mv -f "$old_cfg" "$new_cfg"
            sed -i "s/^DEVICE=.*/DEVICE=$new_nic/" "$new_cfg"
            sed -i "s/^NAME=.*/NAME=$new_nic/" "$new_cfg"
            echo "更新配置：$new_cfg"
        fi
    fi
done

echo -e "\n移除内核网卡命名强制参数..."
grubby --update-kernel=ALL --remove-args="net.ifnames=0 biosdevname=0"

echo -e "\n重载UDEV规则..."
udevadm control --reload-rules
udevadm trigger

echo -e "\n====================================="
echo "网卡重命名配置完成！"
echo "重启系统 reboot 生效"
echo "====================================="
rm -rf "$0"
