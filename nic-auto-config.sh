#!/bin/bash

RED='\e[1;31m'
GREEN='\e[1;32m'
YELLOW='\e[1;33m'
RESET='\e[0m'

get_public_ip() {
    ip -4 addr show | grep -v 'LOOPBACK' | grep -oP '(?<=inet\s)\d+(\.\d+){3}/\d+' | grep -vE '^127\.|^10\.|^172\.|^192\.168' | head -n1 | cut -d'/' -f1
}

echo -e "${GREEN}=== 开始自动配置内网网卡 ===${RESET}"

PUBLIC_IP=$(get_public_ip)
if [ -z "$PUBLIC_IP" ]; then
    echo -e "${RED}错误：未检测到公网IP，请检查网络配置${RESET}"
    exit 1
fi
echo -e "✅ 检测到公网IP：${GREEN}$PUBLIC_IP${RESET}"

PUBLIC_NIC=""
for nic in $(ip -br link show | awk '$1 != "lo" {print $1}' | tr -d ':' | sort); do
    ip=$(ip -4 addr show "$nic" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)
    if [ "$ip" = "$PUBLIC_IP" ]; then
        PUBLIC_NIC="$nic"
        break
    fi
done

if [ -z "$PUBLIC_NIC" ]; then
    PUBLIC_NIC=$(ip -br link show | awk '$1 != "lo" {print $1}' | tr -d ':' | head -n1)
fi
echo -e "✅ 公网网卡：${GREEN}$PUBLIC_NIC${RESET}"

INTERNAL_IP="100.${PUBLIC_IP#*.}"
echo -e "✅ 规划内网IP：${GREEN}$INTERNAL_IP${RESET}"

echo -e "\n${YELLOW}正在查找内网网卡...${RESET}"
TARGET_NIC=""

for NIC in $(ip -br link show | awk '$1 != "lo" && $1 != "'"$PUBLIC_NIC"'" {print $1}' | tr -d ':' | sort); do
    if [[ "$NIC" =~ ^(docker|veth|br-|bond|virbr|lo) ]]; then
        continue
    fi
    TARGET_NIC="$NIC"
    break
done

if [ -z "$TARGET_NIC" ]; then
    echo -e "${RED}错误：未找到可用的内网网卡${RESET}"
    exit 1
fi
echo -e "✅ 找到内网网卡：${GREEN}$TARGET_NIC${RESET}"

CONFIG_FILE="/etc/sysconfig/network-scripts/ifcfg-$TARGET_NIC"
echo -e "\n${GREEN}正在配置 $TARGET_NIC 网卡...${RESET}"

cat > "$CONFIG_FILE" <<EOF
TYPE=Ethernet
BOOTPROTO=static
DEVICE=$TARGET_NIC
ONBOOT=yes
IPADDR=$INTERNAL_IP
NETMASK=255.255.255.0
NM_CONTROLLED=no
EOF

echo -e "\n${YELLOW}重启网络服务...${RESET}"
systemctl stop NetworkManager 2>/dev/null
systemctl restart network 2>/dev/null

echo -e "\n${GREEN}=== 配置完成 ===${RESET}"
echo -e "网卡：${GREEN}$TARGET_NIC${RESET}"
echo -e "IP地址：${GREEN}$INTERNAL_IP${RESET}"
ip -4 addr show $TARGET_NIC 2>/dev/null | grep inet
