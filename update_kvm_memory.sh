#!/bin/bash
set -euo pipefail

# ====================== 配置项 ======================
XML_BASE_DIR="/etc/libvirt/qemu"
XML_DEFAULT_PATH="${XML_BASE_DIR}/*.xml"
# ====================================================

clear
echo "========================================"
echo "      KVM 虚拟机内存批量修改工具"
echo "========================================"
echo "当前目录：${XML_BASE_DIR}"
echo "========================================"

# 1. 获取XML文件列表
xml_files=("${XML_BASE_DIR}"/*.xml)
if [ ${#xml_files[@]} -eq 0 ]; then
    echo "❌ 错误：未找到任何虚拟机XML文件！"
    exit 1
fi

# 展示文件列表
echo "可用虚拟机XML文件："
for i in "${!xml_files[@]}"; do
    filename=$(basename "${xml_files[$i]}")
    echo "$((i+1))) $filename"
done
echo "========================================"

# 2. 选择要修改的文件
read -p "请输入要修改的XML文件名（多个用空格分隔，直接回车修改全部）：" SELECTED_FILES

# 处理选中文件
TARGET_FILES=()
if [ -z "$SELECTED_FILES" ]; then
    TARGET_FILES=("${xml_files[@]}")
    echo "✅ 你选择了修改所有XML文件"
else
    for file in $SELECTED_FILES; do
        full_path="${XML_BASE_DIR}/${file}"
        if [ -f "$full_path" ]; then
            TARGET_FILES+=("$full_path")
        else
            echo "⚠️  警告：文件不存在，已跳过 -> ${file}"
        fi
    done

    if [ ${#TARGET_FILES[@]} -eq 0 ]; then
        echo "❌ 错误：未找到任何有效XML文件！"
        exit 1
    fi
fi

echo -e "\n✅ 待修改的文件："
for f in "${TARGET_FILES[@]}"; do
    echo " - $(basename "$f")"
done

# 3. 输入目标内存大小
read -p "请输入统一内存大小（单位：KiB，例如 62914560）：" TARGET_MEM
if ! [[ "$TARGET_MEM" =~ ^[0-9]+$ ]]; then
    echo "❌ 错误：必须输入纯数字！"
    exit 1
fi
echo -e "\n✅ 目标内存：${TARGET_MEM} KiB"

# 4. 自动备份
BACKUP_DIR="${XML_BASE_DIR}/backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp -f "${TARGET_FILES[@]}" "$BACKUP_DIR/"
echo -e "\n✅ 备份完成：${BACKUP_DIR}"

# 5. 批量修改XML内存配置
echo -e "\n========================================"
echo "开始修改内存配置..."
for xml in "${TARGET_FILES[@]}"; do
    vm_name=$(basename "$xml" .xml)
    echo -e "\n📌 处理虚拟机：$vm_name"

    # 替换 memory 标签
    sed -i "s/<memory unit='KiB'>[0-9]*<\/memory>/<memory unit='KiB'>${TARGET_MEM}<\/memory>/g" "$xml"
    # 替换 currentMemory 标签
    sed -i "s/<currentMemory unit='KiB'>[0-9]*<\/currentMemory>/<currentMemory unit='KiB'>${TARGET_MEM}<\/memory>/g" "$xml"

    # 打印修改结果
    echo "修改后配置："
    grep -E "<memory|currentMemory" "$xml"
done

# 6. 重新定义虚拟机配置 + 重启对应虚拟机
echo -e "\n========================================"
echo "重新定义虚拟机并重启服务..."
for xml in "${TARGET_FILES[@]}"; do
    vm_name=$(basename "$xml" .xml)
    
    # 重新加载XML
    virsh define "$xml"
    echo "✅ 已重新定义：$vm_name"

    # 检查虚拟机状态，只重启运行中的虚拟机
    vm_state=$(virsh list --all | grep "$vm_name" | awk '{print $3}')
    if [ "$vm_state" = "running" ]; then
        echo "🔄 虚拟机正在运行，执行重启..."
        virsh reboot "$vm_name"
        echo "✅ 虚拟机 $vm_name 重启完成"
    else
        echo "ℹ️  虚拟机 $vm_name 当前未运行，无需重启"
    fi
done

# 7. 完成提示
echo -e "\n========================================"
echo "🎉 脚本执行全部完成！"
echo "📊 修改结果："
echo "  - 虚拟机数量：${#TARGET_FILES[@]}"
echo "  - 统一内存：${TARGET_MEM} KiB"
echo "  - 未重启 libvirtd 服务"
echo "  - 仅重启了【正在运行】的被修改虚拟机"
echo "========================================"
