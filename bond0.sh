#!/bin/bash

# ============ 定义函数 ============

# 创建 bond0 配置（含 IPv4 + IPv6）
function bond0(){
    local ipv6_block=""
    if [ -n "$bond0_ip6addr" ] && [ -n "$bond0_ip6_prefix" ]; then
        ipv6_block=$(cat <<IPV6EOF
IPV6INIT=yes
IPV6_AUTOCONF=no
IPV6ADDR=${bond0_ip6addr}/${bond0_ip6_prefix}
IPV6_FAILURE_FATAL=no
IPV6EOF
)
        if [ -n "$bond0_ip6_gateway" ]; then
            ipv6_block="${ipv6_block}
IPV6_DEFAULTGW=${bond0_ip6_gateway}"
        fi
    fi

    cat > /etc/sysconfig/network-scripts/ifcfg-bond0 <<EOF
DEVICE=bond0
TYPE=bond
NAME=bond0
BONDING_MASTER=yes
BOOTPROTO=static
USERCTL=no
ONBOOT=yes
IPADDR=$bond0_ipaddr
PREFIX=$bond0_mask
GATEWAY=$bond0_gateway
${ipv6_block}
BONDING_OPTS="mode=0 miimon=100"
EOF
}

function network_one_name(){
    cat > /etc/sysconfig/network-scripts/ifcfg-$ETH1 <<EOF
TYPE=Ethernet
BOOTPROTO=none
DEVICE=$ETH1
ONBOOT=yes
MASTER=bond0
SLAVE=yes
EOF
}

function network_two_name(){
    cat > /etc/sysconfig/network-scripts/ifcfg-$ETH2 <<EOF
TYPE=Ethernet
BOOTPROTO=none
DEVICE=$ETH2
ONBOOT=yes
MASTER=bond0
SLAVE=yes
EOF
}

# 清除旧网卡上残留的 IP 地址（IPv4 + IPv6）
function flush_old_addrs(){
    echo -e "\e[1;33;41m***清除旧网卡残留 IP 信息***\e[0m"
    for iface in $ETH1 $ETH2; do
        echo "  正在 flush $iface ..."
        ip addr flush dev "$iface"
        echo "  $iface 已清除"
    done
    sleep 1s
}

# ============ 加载 bonding 模块 ============
modprobe bonding
grep -q "modprobe bonding" /etc/rc.local 2>/dev/null || echo "modprobe bonding" >> /etc/rc.local

# ============ 判断是否可以做 bond ============
upnetwork_num=$(ip a | grep "LOWER_UP" | grep -vE "lo|bond|docker|virbr|MASTER" | wc -l)

if [ "$upnetwork_num" -eq 1 ]; then
    echo -e "\e[1;33;41m***检测到 UP 网卡数量只有 1 个，无法做双口绑定，程序退出***\e[0m"
    exit 1

elif [ "$upnetwork_num" -eq 2 ]; then
    echo -e "\e[1;33;41m***获取当前机器相关信息（IPv4 + IPv6）***\e[0m"

    # ---- 获取网卡名称 ----
    ETH1=$(ip a | grep "LOWER_UP" | grep -vE "lo|bond|docker|virbr|MASTER" | awk -F ":" '{print $2}' | xargs | awk '{print $1}')
    ETH2=$(ip a | grep "LOWER_UP" | grep -vE "lo|bond|docker|virbr|MASTER" | awk -F ":" '{print $2}' | xargs | awk '{print $2}')
    echo "ADAPTER NAME: $ETH1 and $ETH2"

    # ---- 获取 IPv4 信息 ----
    bond0_ipaddr=$(curl -4s --max-time 10 ip.sb)
    if [ -z "$bond0_ipaddr" ]; then
        echo -e "\e[1;33;41m***获取 IPv4 公网地址失败，请检查网络，程序退出***\e[0m"
        exit 1
    fi
    echo "IPv4 ADDR   : $bond0_ipaddr"

    bond0_mask=$(ip addr show | grep "inet ${bond0_ipaddr}/" | awk '{print $2}' | awk -F "/" '{print $2}')
    echo "IPv4 PREFIX : $bond0_mask"

    bond0_gateway=$(ip route | grep "default" | awk '{print $3}')
    echo "IPv4 GATEWAY: $bond0_gateway"

    # ---- 获取 IPv6 信息 ----
    bond0_ip6_raw=$(ip -6 addr show scope global | grep "inet6" | head -1 | awk '{print $2}')
    if [ -n "$bond0_ip6_raw" ]; then
        bond0_ip6addr=$(echo "$bond0_ip6_raw" | awk -F "/" '{print $1}')
        bond0_ip6_prefix=$(echo "$bond0_ip6_raw" | awk -F "/" '{print $2}')
        echo "IPv6 ADDR   : $bond0_ip6addr"
        echo "IPv6 PREFIX : $bond0_ip6_prefix"

        bond0_ip6_gateway=$(ip -6 route | grep "default" | awk '{print $3}')
        if [ -n "$bond0_ip6_gateway" ]; then
            echo "IPv6 GATEWAY: $bond0_ip6_gateway"
        else
            echo "IPv6 GATEWAY: (未检测到默认网关)"
        fi
    else
        echo "IPv6        : 未检测到全局 IPv6 地址，将跳过 IPv6 配置"
        bond0_ip6addr=""
        bond0_ip6_prefix=""
        bond0_ip6_gateway=""
    fi

    # ---- 确认网卡端口类型一致 ----
    echo -e "\e[1;33;41m***开始绑定网口***\e[0m"
    a=$(ethtool "$ETH1" 2>/dev/null | grep 'Supported ports' | awk '{print $(NF-1)}')
    b=$(ethtool "$ETH2" 2>/dev/null | grep 'Supported ports' | awk '{print $(NF-1)}')

    if [ "$a" = "$b" ]; then
        # 清除旧网卡上残留的 IP 地址
        flush_old_addrs

        # 写入新配置
        network_one_name
        echo "$ETH1 网口正在聚合中......"
        sleep 1s

        network_two_name
        echo "$ETH2 网口正在聚合中......"
        sleep 1s

        bond0
        echo "网卡双口 bond0 绑定配置已写入（含 IPv6）......"
        sleep 1s
    else
        echo -e "\e[1;33;41m***两张网卡传输速率不同（${a} vs ${b}），程序退出***\e[0m"
        exit 1
    fi

    systemctl stop NetworkManager
    systemctl disable NetworkManager
    systemctl restart network.service
    sleep 3s

    echo ""
    echo -e "\e[1;33;41m***网口绑定完毕，请开始部署业务***\e[0m"
    echo "  bond0 IPv4: $bond0_ipaddr/$bond0_mask  GW: $bond0_gateway"
    [ -n "$bond0_ip6addr" ] && echo "  bond0 IPv6: $bond0_ip6addr/$bond0_ip6_prefix  GW: $bond0_ip6_gateway"

else
    echo -e "\e[1;33;41m***未获取到网卡或检测网卡数量异常（UP 数量=$upnetwork_num），程序退出***\e[0m"
    exit 1
fi

rm -f "$0"
