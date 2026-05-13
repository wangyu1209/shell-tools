#!/bin/bash
set -euo pipefail

XML_BASE_DIR="/etc/libvirt/qemu"

echo "========================================"
echo "当前 ${XML_BASE_DIR} 目录下的虚拟机XML文件列表："
echo "========================================"

xml_files=("${XML_BASE_DIR}"/*.xml)
if [ ${#xml_files[@]} -eq 0 ]; then
    echo "错误：未找到任何虚拟机XML文件！"
    exit 1
fi

for i in "${!xml_files[@]}"; do
    filename=$(basename "${xml_files[$i]}")
    echo "$((i+1))) $filename"
done
echo "========================================"

read -p "请输入要修改的XML文件名（多个用空格分隔，直接回车则修改全部）：" SELECTED_FILES

TARGET_FILES=()
if [ -z "$SELECTED_FILES" ]; then
    TARGET_FILES=("${xml_files[@]}")
    echo "你选择了修改所有XML文件"
else
    for file in $SELECTED_FILES; do
        full_path="${XML_BASE_DIR}/${file}"
        if [ -f "$full_path" ]; then
            TARGET_FILES+=("$full_path")
        else
            echo "警告：文件 ${full_path} 不存在，已跳过该文件！"
        fi
    done
    if [ ${#TARGET_FILES[@]} -eq 0 ]; then
        echo "错误：未找到任何有效的XML文件！"
        exit 1
    fi
fi

read -p "请输入需要统一设置的目标内存大小（单位：KiB）：" TARGET_MEM
if ! [[ "$TARGET_MEM" =~ ^[0-9]+$ ]]; then
    echo "错误：输入的内存大小必须是纯数字！"
    exit 1
fi

BACKUP_DIR="${XML_BASE_DIR}/backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp -f "${TARGET_FILES[@]}" "$BACKUP_DIR/"
echo "已备份待修改的XML文件至：$BACKUP_DIR"

echo "正在替换内存配置标签..."
for xml in "${TARGET_FILES[@]}"; do
    sed -i "s/<memory unit='KiB'>[0-9]*<\/memory>/<memory unit='KiB'>${TARGET_MEM}<\/memory>/g" "$xml"
    sed -i "s/<currentMemory unit='KiB'>[0-9]*<\/currentMemory>/<currentMemory unit='KiB'>${TARGET_MEM}<\/currentMemory>/g" "$xml"
done

echo -e "\n===== 替换后的内存配置 ====="
grep -E "<memory|currentMemory" "${TARGET_FILES[@]}"

echo -e "\n开始重新定义虚拟机并应用新配置..."
for xml in "${TARGET_FILES[@]}"; do
    vm_name=$(basename "$xml" .xml)
    vm_state=$(virsh domstate "$vm_name" 2>/dev/null || true)

    if [[ "$vm_state" == "running" ]]; then
        echo "关闭虚拟机：$vm_name"
        virsh shutdown "$vm_name"
        sleep 1
        while true; do
            st=$(virsh domstate "$vm_name" 2>/dev/null || true)
            [[ "$st" != "running" ]] && break
            sleep 1
        done
    fi

    virsh define "$xml"
    echo "已重新定义配置：$vm_name"

    if [[ "$vm_state" == "running" ]]; then
        virsh start "$vm_name"
        echo "已启动虚拟机：$vm_name"
    fi
done

echo -e "\n脚本执行完成：所有选中虚拟机内存已修改并生效"
