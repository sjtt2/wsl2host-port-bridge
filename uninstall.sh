#!/bin/bash

# 配置参数（与安装脚本保持一致）
SCRIPT_FILE="wsl-port-manager.sh"
FORWARD_SCRIPT_NAME="wsl-ssh-portforward.sh"
ALIAS_SCRIPT_NAME="wsl-port-aliases.sh"
PORT_CONFIG="/etc/wsl-port-manager/ports.conf"

# 路径定义
SCRIPT_DEST="/usr/local/bin/$SCRIPT_FILE"
PROFILE_D_DIR="/etc/profile.d"
FORWARD_SCRIPT_DEST="$PROFILE_D_DIR/$FORWARD_SCRIPT_NAME"
ALIAS_SCRIPT_DEST="$PROFILE_D_DIR/$ALIAS_SCRIPT_NAME"
ZSHRC="$HOME/.zshrc"

# 检查root权限
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：请使用sudo或root权限运行卸载脚本"
    echo "正确命令：sudo $0"
    exit 1
fi

echo "===== 开始卸载 wsl2host-port-bridge ====="

# 1. 清除所有已配置的端口转发规则
echo "1. 正在删除所有端口转发规则..."
if [ -f "$PORT_CONFIG" ]; then
    while IFS= read -r port; do
        if [ -n "$port" ] && [[ "$port" =~ ^[0-9]+$ ]]; then
            echo "   - 移除端口 $port 转发规则"
            powershell.exe -Command "netsh interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=$port" >/dev/null 2>&1
        fi
    done < "$PORT_CONFIG"
else
    echo "1. 未找到端口配置文件，跳过规则清理"
fi

# 2. 移除主程序脚本
if [ -f "$SCRIPT_DEST" ]; then
    echo "2. 移除主程序..."
    sudo rm -f "$SCRIPT_DEST"
else
    echo "2. 主程序不存在，跳过移除"
fi

# 3. 移除启动脚本
if [ -f "$FORWARD_SCRIPT_DEST" ]; then
    echo "3. 移除启动脚本..."
    sudo rm -f "$FORWARD_SCRIPT_DEST"
else
    echo "3. 启动脚本不存在，跳过移除"
fi

# 4. 移除别名配置脚本
if [ -f "$ALIAS_SCRIPT_DEST" ]; then
    echo "4. 移除别名配置..."
    sudo rm -f "$ALIAS_SCRIPT_DEST"
else
    echo "4. 别名配置不存在，跳过移除"
fi

# 5. 精准清理Zsh配置（只删除安装时添加的内容）
echo "5. 清理Zsh配置..."
if [ -f "$ZSHRC" ]; then
    # 定义要删除的特征行（与安装脚本添加的内容完全匹配）
    forward_comment="# 加载WSL端口转发启动脚本"
    forward_line="source $FORWARD_SCRIPT_DEST"
    alias_comment="# 加载WSL端口管理工具别名"
    alias_line="source $ALIAS_SCRIPT_DEST"

    # 逐个删除特征行，不影响其他内容
    sed -i "/^${forward_comment}$/d" "$ZSHRC"
    sed -i "/^${forward_line}$/d" "$ZSHRC"
    sed -i "/^${alias_comment}$/d" "$ZSHRC"
    sed -i "/^${alias_line}$/d" "$ZSHRC"

    # 清理可能产生的空行（连续空行保留一行）
    sed -i ':a;N;$!ba;s/\n\n\+/\n\n/g' "$ZSHRC"
    echo "   - 已移除Zsh配置中工具相关的内容"
else
    echo "5. Zsh配置文件不存在，跳过清理"
fi

# 6. 清理残留的端口配置文件和目录
if [ -d "/etc/wsl-port-manager/" ]; then
    echo "6. 清理端口配置目录..."
    sudo rm -rf /etc/wsl-port-manager/
else
    echo "6. 端口配置目录不存在，跳过清理"
fi

echo -e "\n===== 卸载完成！ ====="
echo "已完成以下操作："
echo "  - 删除所有通过本工具配置的端口转发规则"
echo "  - 移除所有工具相关文件"
echo "  - 精准清理Zsh配置中添加的内容（不影响用户其他修改）"
echo "请重启终端使所有更改生效"
