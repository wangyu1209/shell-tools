#!/bin/bash

# ============ 定义函数 ============

# 创建 bond4 配置（含 IPv4 + IPv6）
function bond0(){
    local ipv6_block=""
    if [ -n "$bond4_ip6addr" ] && [ -n "$bond4_ip6_prefix" ]; then
        ipv6_block=$(cat <<IPV6EOF
IPV6INIT=yes
IPV6_AUTOCONF=no
IPV6ADDR=${bond4_ip6addr}/${bond4_ip6_prefix}
IPV6_FAILURE_FATAL=no
IPV6EOF
)
        if [ -n "$bond4_ip6_gateway" ]; then
            ipv6_block="${ipv6_block}
IPV6_DEFAULTGW=${bond4_ip6_gateway}"
        fi
    fi

    cat > /etc/sysconfig/network-scripts/ifcfg-bond4 <<EOF
DEVICE=bond4
TYPE=bond
NAME=bond4
BONDING_MASTER=yes
BOOTPROTO=static
USERCTL=no
ONBOOT=yes
IPADDR=$bond4_ipaddr
PREFIX=$bond4_mask
GATEWAY=$bond4_gateway
${ipv6_block}
BONDING_OPTS="mode=4 miimon=100 lacp_rate=fast"
EOF
}

# 定义从网卡配置函数
function network_slave_config(){
    local eth=$1
    cat > /etc/sysconfig/network-scripts/ifcfg-$eth <<EOF
TYPE=Ethernet
BOOTPROTO=none
DEVICE=$eth
ONBOOT=yes
MASTER=bond4
SLAVE=yes
EOF
}

# 清除旧网卡上残留的 IP 地址（IPv4 + IPv6）
function flush_old_addrs(){
    echo -e "\e[1;33;41m***清除旧网卡残留 IP 信息***\e[0m"
    for iface in $ETH1 $ETH2 $ETH3 $ETH4; do
        echo "  正在 flush $iface ..."
        ip addr flush dev "$iface"
        echo "  $iface 已清除"
    done
    sleep 1s
}

# ============ 加载 bonding 模块 ============
modprobe bonding
grep -q "modprobe bonding" /etc/rc.local 2>/dev/null || echo "modprobe bonding" >> /etc/rc.local

# ============ 判断是否可以做 4 口 bond ============
upnetwork_num=$(ip a | grep "LOWER_UP" | grep -vE "lo|bond|docker|virbr|MASTER" | wc -l)

if [ "$upnetwork_num" -lt 4 ]; then
    echo -e "\e[1;33;41m***检测到 UP 网卡数量为 $upnetwork_num 个，不足 4 个，无法做 4 口绑定，程序退出***\e[0m"
    exit 1

elif [ "$upnetwork_num" -eq 4 ]; then
    echo -e "\e[1;33;41m***获取当前机器相关信息（IPv4 + IPv6）***\e[0m"

    # ---- 获取 4 个活动网卡名称 ----
    ETH_LIST=$(ip a | grep "LOWER_UP" | grep -vE "lo|bond|docker|virbr|MASTER" | awk -F ":" '{print $2}' | xargs)
    ETH1=$(echo $ETH_LIST | awk '{print $1}')
    ETH2=$(echo $ETH_LIST | awk '{print $2}')
    ETH3=$(echo $ETH_LIST | awk '{print $3}')
    ETH4=$(echo $ETH_LIST | awk '{print $4}')
    echo "ADAPTER NAMES: $ETH1, $ETH2, $ETH3 and $ETH4"

    # ---- 获取 IPv4 信息 ----
    bond4_ipaddr=$(curl -4s --max-time 10 ip.sb)
    if [ -z "$bond4_ipaddr" ]; then
        echo -e "\e[1;33;41m***获取 IPv4 公网地址失败，请检查网络，程序退出***\e[0m"
        exit 1
    fi
    echo "IPv4 ADDR   : $bond4_ipaddr"

    bond4_mask=$(ip addr show | grep "inet ${bond4_ipaddr}/" | awk '{print $2}' | awk -F "/" '{print $2}')
    echo "IPv4 PREFIX : $bond4_mask"

    bond4_gateway=$(ip route | grep "default" | awk '{print $3}')
    echo "IPv4 GATEWAY: $bond4_gateway"

    # ---- 获取 IPv6 信息 ----
    bond4_ip6_raw=$(ip -6 addr show scope global | grep "inet6" | head -1 | awk '{print $2}')
    if [ -n "$bond4_ip6_raw" ]; then
        bond4_ip6addr=$(echo "$bond4_ip6_raw" | awk -F "/" '{print $1}')
        bond4_ip6_prefix=$(echo "$bond4_ip6_raw" | awk -F "/" '{print $2}')
        echo "IPv6 ADDR   : $bond4_ip6addr"
        echo "IPv6 PREFIX : $bond4_ip6_prefix"

        bond4_ip6_gateway=$(ip -6 route | grep "default" | awk '{print $3}')
        if [ -n "$bond4_ip6_gateway" ]; then
            echo "IPv6 GATEWAY: $bond4_ip6_gateway"
        else
            echo "IPv6 GATEWAY: (未检测到默认网关)"
        fi
    else
        echo "IPv6        : 未检测到全局 IPv6 地址，将跳过 IPv6 配置"
        bond4_ip6addr=""
        bond4_ip6_prefix=""
        bond4_ip6_gateway=""
    fi

    # ---- 检查所有网卡端口类型是否一致 ----
    echo -e "\e[1;33;41m***开始验证网卡兼容性***\e[0m"
    port_type=$(ethtool "$ETH1" 2>/dev/null | grep 'Speed' | awk '{print $(NF)}')
    all_same=true

    for eth in $ETH1 $ETH2 $ETH3 $ETH4; do
        current_type=$(ethtool "$eth" 2>/dev/null | grep 'Speed' | awk '{print $(NF)}')
        if [ "$current_type" != "$port_type" ]; then
            all_same=false
            echo -e "\e[1;31m  $eth 速率 $current_type 与 $ETH1 速率 $port_type 不一致\e[0m"
            break
        fi
    done

    if [ "$all_same" = true ]; then
        # 清除旧网卡上残留的 IP 地址
        flush_old_addrs

        # 配置所有从网卡
        for eth in $ETH1 $ETH2 $ETH3 $ETH4; do
            network_slave_config "$eth"
            echo "$eth 网口正在聚合中......"
            sleep 1s
        done

        # 配置 bond4
        bond0
        echo "4 口网卡 bond4 绑定配置已写入（含 IPv6）......"
        sleep 1s
    else
        echo -e "\e[1;33;41m***检测到网卡速率不一致，程序退出***\e[0m"
        exit 1
    fi

    # 重启网络服务
    systemctl stop NetworkManager
    systemctl disable NetworkManager
    systemctl restart network.service
    sleep 3s

    echo ""
    echo -e "\e[1;33;41m***4 口网卡 bond4 绑定完毕，请开始部署业务***\e[0m"
    echo "  bond4 IPv4: $bond4_ipaddr/$bond4_mask  GW: $bond4_gateway"
    [ -n "$bond4_ip6addr" ] && echo "  bond4 IPv6: $bond4_ip6addr/$bond4_ip6_prefix  GW: $bond4_ip6_gateway"

else
    echo -e "\e[1;33;41m***检测到 UP 网卡数量为 $upnetwork_num 个，超过 4 个，无法做 4 口绑定，程序退出***\e[0m"
    exit 1
fi

rm -f "$0"
