#!/bin/bash
set -e

echo "==== 规范 IPv6 批量命令生成器 (安全无错版) ===="

read -p "请输入网关 (带前缀, 如 240e:914:4006:5::1/64): " GW_INPUT
read -p "请输入地址段 (如 240e:914:4006:5::113-240e:914:4006:5::119): " IP_RANGE

GW_ADDR=$(echo "$GW_INPUT" | cut -d'/' -f1)
PREFIX=$(echo "$GW_INPUT" | cut -d'/' -f2)

START_IP=$(echo "$IP_RANGE" | cut -d'-' -f1)
END_IP=$(echo "$IP_RANGE" | cut -d'-' -f2)

extract_suffix() {
    local ip=$1
    echo "$ip" | awk -F'::' '{print $NF}'
}

SUFFIX_START=$(extract_suffix "$START_IP")
SUFFIX_END=$(extract_suffix "$END_IP")

PREFIX_PART=${START_IP%::*}::

echo -e "\n==== 生成的规范 IPv6 命令 ===="
for ((i=SUFFIX_START; i<=SUFFIX_END; i++)); do
    echo "./ipv6.sh ${PREFIX_PART}${i}/${PREFIX} ${GW_ADDR}"
done