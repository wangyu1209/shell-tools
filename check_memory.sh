#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    echo "错误：请使用 root 权限运行此脚本（例如：sudo $0）"
    exit 1
fi

dmidecode -t memory | awk '
BEGIN {
    # 打印表头（格式化对齐）
    printf "%-20s %-15s %-15s %s\n", "Locator", "Size", "Speed", "Manufacturer"
    printf "%-20s %-15s %-15s %s\n", "--------------------", "---------------", "---------------", "------------------------"
    # 初始化变量
    locator=""
    size=""
    speed=""
    manufacturer=""
    in_memory=0
}

/^Memory Device$/ {
    if (in_memory && size != "No Module Installed" && size != "") {
        printf "%-20s %-15s %-15s %s\n", locator, size, speed, manufacturer
    }
    locator=""
    size=""
    speed=""
    manufacturer=""
    in_memory=1
    next
}

# 在内存设备块内提取字段（注意字段前的制表符缩进）
in_memory {
    if (/^\tLocator:/)          locator      = substr($0, 11)  # 去掉 "\tLocator: " 前缀
    if (/^\tSize:/)             size         = substr($0, 8)   # 去掉 "\tSize: " 前缀
    if (/^\tSpeed:/)            speed        = substr($0, 9)   # 去掉 "\tSpeed: " 前缀
    if (/^\tManufacturer:/)     manufacturer = substr($0, 16)  # 去掉 "\tManufacturer: " 前缀
}

# 文件结束时，处理最后一个内存设备
END {
    if (in_memory && size != "No Module Installed" && size != "") {
        printf "%-20s %-15s %-15s %s\n", locator, size, speed, manufacturer
    }
}
'
rm -rf "$0"