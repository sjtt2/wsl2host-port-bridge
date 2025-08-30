#!/bin/bash
# 配置参数
GITHUB_REPO="sjtt2/wsl2host-port-bridge"  # 你的GitHub仓库（可修改）
MAIN_SCRIPT="wsl-port-manager.sh"         # 核心脚本名
FORWARD_SCRIPT="wsl-ssh-portforward.sh"   # 启动脚本名（放profile.d）
ALIAS_SCRIPT="wsl-port-aliases.sh"        # 别名脚本名（放profile.d）
WSL_INFO_FILE="wsl-info.conf"             # WSL信息文件（IP/版本）

# 安装路径
DEST_DIR="/usr/local/bin"
MAIN_SCRIPT_DEST="$DEST_DIR/$MAIN_SCRIPT"
PROFILE_D_DIR="/etc/profile.d"
FORWARD_SCRIPT_DEST="$PROFILE_D_DIR/$FORWARD_SCRIPT"
ALIAS_SCRIPT_DEST="$PROFILE_D_DIR/$ALIAS_SCRIPT"
WSL_INFO_DEST="/etc/wsl-port-manager/$WSL_INFO_FILE"

# --------------------------
# 前置检查
# --------------------------
# 1. 检查root权限
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：请用sudo运行，命令：sudo $0"
    exit 1
fi

# 2. 检查wget/curl
if command -v wget &> /dev/null; then
    DOWNLOAD_CMD="wget -q -O"
elif command -v curl &> /dev/null; then
    DOWNLOAD_CMD="curl -s -o"
else
    echo "错误：请先安装wget或curl"
    exit 1
fi

# 3. 检查WSL环境
if ! command -v powershell.exe &> /dev/null; then
    echo "错误：非WSL环境，无法执行Windows命令"
    exit 1
fi

# --------------------------
# 核心：WSL版本/IP检测（仅在install时执行）
# --------------------------
detect_wsl_env() {
    echo "1. 检测WSL环境..."
    local current_hostname=$(cat /proc/sys/kernel/hostname)
    local wsl_list_output=$(powershell.exe -Command "wsl.exe -l -v" 2>/dev/null | iconv -f UTF-16LE -t UTF-8 | tr -d '\r')

    # 检测WSL版本
    local wsl_version=$(echo "$wsl_list_output" | awk -v h="$current_hostname" '
        NR>1 {
            gsub(/^\*/, "", $1); line=$0; gsub(/\s+/, " ", line); split(line, f, " ")
            name=f[1]; for(i=2;i<=length(f)-2;i++) name=name" "f[i]
            if(name==h && f[length(f)]~/(1|2)/) print f[length(f)]
        }
    ' | head -n 1)
    if [ -z "$wsl_version" ]; then
        echo "警告：WSL版本检测失败，默认按WSL2处理"
        wsl_version=2
    fi

    # 检测WSL IP（WSL1固定127.0.0.1，WSL2动态获取）
    local wsl_ip
    if [ "$wsl_version" -eq 1 ]; then
        wsl_ip="127.0.0.1"
    else
        wsl_ip=$(hostname -I | awk '{print $1}')
        if [ -z "$wsl_ip" ]; then
            wsl_ip=$(grep -oP '(?<=inet\s)\d+(\.\d+){3}' /proc/net/fib_trie | grep -v '^127\.' | head -n 1)
        fi
        if [ -z "$wsl_ip" ]; then
            echo "错误：WSL2 IP获取失败"
            exit 1
        fi
    fi

    # 保存WSL信息到文件（供wsl-port-manager.sh读取）
    sudo mkdir -p /etc/wsl-port-manager/
    sudo tee "$WSL_INFO_DEST" > /dev/null <<EOF
WSL_IP=$wsl_ip
WSL_VERSION=$wsl_version
WSL_HOSTNAME=$current_hostname
EOF

    echo "✅ WSL环境检测完成：IP=$wsl_ip，版本=WSL$wsl_version"
}

# --------------------------
# 安装核心脚本
# --------------------------
install_main_script() {
    echo -e "\n2. 安装核心脚本..."
    # 从GitHub下载（或本地复制，根据实际情况修改）
    $DOWNLOAD_CMD "$MAIN_SCRIPT_DEST" "https://raw.githubusercontent.com/$GITHUB_REPO/main/$MAIN_SCRIPT" || {
        # 本地 fallback（如果没有GitHub，直接写入本地内容）
        echo "警告：GitHub下载失败，使用本地默认脚本"
        sudo tee "$MAIN_SCRIPT_DEST" > /dev/null <<'EOF'
# 此处替换为上面wsl-port-manager.sh的完整内容（如果不需要GitHub下载）
EOF
    }
    sudo chmod +x "$MAIN_SCRIPT_DEST"
    echo "✅ 核心脚本安装完成：$MAIN