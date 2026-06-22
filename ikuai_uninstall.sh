#!/bin/bash

install_tmux() {
    if command -v tmux &>/dev/null; then
        return
    fi
    if command -v yum &>/dev/null; then
        yum install -y tmux &>/dev/null
    elif command -v apt-get &>/dev/null; then
        apt-get update -qq &>/dev/null && apt-get install -y tmux &>/dev/null
    else
        echo "ERROR：无法识别包管理器，请手动安装 tmux"
        exit 1
    fi
    if ! command -v tmux &>/dev/null; then
        echo "ERROR：tmux 安装失败"
        exit 1
    fi
}

remove_services() {
    vm_list=$(virsh list --all --name 2>/dev/null)
    if [ -n "$vm_list" ]; then
        for i in $(echo "$vm_list" | grep "^ikuai"); do
            virsh destroy "$i" 2>/dev/null
            virsh undefine "$i" 2>/dev/null
        done
    fi
    echo "INFO：[卸载ikuai虚拟机——完成]"
}

network() {
    systemctl daemon-reload &>/dev/null
    systemctl unmask new_pppoe &>/dev/null
    systemctl enable new_pppoe &>/dev/null
    systemctl start new_pppoe &>/dev/null
    echo "INFO：等待 120 秒..."
    sleep 120
    systemctl restart new_pppoe &>/dev/null
    echo "INFO：[启动new_pppoe——完成]"
}

delete_lan1() {
    chattr -ie /etc/sysconfig/network-scripts/ifcfg-* 2>/dev/null

    nic_array=($(ip a 2>/dev/null | grep -E "state (UP|DOWN)" | grep -Ev 'lo|\.|virbr|@|docker' | cut -d':' -f2,3 | awk '{print $1,$8}' | grep "br" | grep -Ev "^br" | cut -d: -f1))
    br_array=($(ip a 2>/dev/null | grep -E "state (UP|DOWN)" | grep -Ev 'lo|\.|virbr|@|docker' | cut -d':' -f2,3 | awk '{print $1,$8}' | grep "br" | grep -Ev "^br" | cut -d: -f2))

    if [ ${#br_array[*]} -eq 0 ]; then
        echo "INFO：未发现需要清理的 br 网桥"
    else
        for i in $(seq ${#nic_array[*]}); do
            j=$((i - 1))
            brctl delif "${br_array[$j]}" "${nic_array[$j]}" 2>/dev/null
            ip link set dev "br$j" down 2>/dev/null
            ifconfig "br$j" down 2>/dev/null
            brctl delbr "br$j" 2>/dev/null
        done
    fi

    input="$(brctl show 2>/dev/null | grep -E "br[0-3]|lan" | grep -v vir | awk '{print $1,$4}')"
    mapfile -t lines <<< "$input"
    for line in "${lines[@]}"; do
        brctl delif $line 2>/dev/null
    done

    ifconfig vnet0 down 2>/dev/null
    ifconfig lan1 down 2>/dev/null
    ip link set dev lan1 down 2>/dev/null
    ip link set dev vnet0 down 2>/dev/null
    brctl delbr lan1 2>/dev/null

    echo "INFO：[删除lan1及br网卡——完成]"
}

main() {
    remove_services
    delete_lan1
    network
    systemctl restart new_pppoe 2>/dev/null
    echo "INFO：[最终 restart new_pppoe——完成]"
    echo "INFO：全部完成，删除脚本自身"
    rm -f "$0"
}

install_tmux

SESSION_NAME="ikuai_cleanup"

if [ -z "$TMUX" ]; then
    SELF=$(readlink -f "$0")
    echo "INFO：tmux 后台会话 [${SESSION_NAME}] 已启动"
    tmux new-session -d -s "$SESSION_NAME" "bash $SELF --in-tmux"
    echo "INFO：查看进度 →  tmux attach -t ${SESSION_NAME}"
    exit 0
else
    main
    echo "INFO：10 秒后关闭 tmux 会话"
    sleep 10
fi
