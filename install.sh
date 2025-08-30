#!/bin/bash
# 配置参数（依赖PATH，无绝对路径）
GITHUB_REPO="sjtt2/wsl2host-port-bridge"
MAIN_SCRIPT="wsl-port-manager.sh"
FORWARD_SCRIPT="wsl-ssh-portforward.sh"
ALIAS_SCRIPT="wsl-port-aliases.sh"
WSL_INFO_FILE="wsl-info.conf"

# 安装路径（标准路径，无需绝对路径）
DEST_DIR="/usr/local/bin"
MAIN_SCRIPT_DEST="$DEST_DIR/$MAIN_SCRIPT"
PROFILE_D_DIR="/etc/profile.d"
FORWARD_SCRIPT_DEST="$PROFILE_D_DIR/$FORWARD_SCRIPT"
ALIAS_SCRIPT_DEST="$PROFILE_D_DIR/$ALIAS_SCRIPT"
WSL_INFO_DEST="/etc/wsl-port-manager/$WSL_INFO_FILE"

# --------------------------
# 前置检查（依赖PATH，提示用sudo -E）
# --------------------------
# 1. 检查root权限
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：请用 sudo -E 运行（保留PATH），命令：sudo -E $0"
    exit 1
fi

# 2. 检查wget/curl（依赖PATH）
if command -v wget &> /dev/null; then
    DOWNLOAD_CMD="wget -q -O"
elif command -v curl &> /dev/null; then
    DOWNLOAD_CMD="curl -s -o"
else
    echo "错误：请先安装wget或curl（sudo apt install wget）"
    exit 1
fi

# 3. 检查powershell.exe（依赖PATH，必须用sudo -E）
if ! command -v powershell.exe &> /dev/null; then
    echo "错误：未找到powershell.exe，请用 sudo -E 重新执行（保留普通用户PATH）"
    echo "示例：curl ... | sudo -E bash"
    exit 1
fi

# --------------------------
# WSL环境检测（依赖PATH调用powershell.exe）
# --------------------------
detect_wsl_env() {
    echo "1. 检测WSL环境（依赖PATH，powershell.exe 已识别）..."
    local current_hostname=$(cat /proc/sys/kernel/hostname)
    
    # 调用wsl.exe -l -v（依赖PATH，无需绝对路径）
    local wsl_list_output=$(powershell.exe -Command "wsl.exe -l -v" 2>/dev/null | iconv -f UTF-16LE -t UTF-8 | tr -d '\r')

    # 提取WSL版本
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

    # 提取WSL IP
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

    # 保存WSL信息
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
    $DOWNLOAD_CMD "$MAIN_SCRIPT_DEST" "https://raw.githubusercontent.com/$GITHUB_REPO/main/$MAIN_SCRIPT" || {
        echo "错误：从GitHub下载 $MAIN_SCRIPT 失败"
        exit 1
    }
    sudo chmod +x "$MAIN_SCRIPT_DEST"
    echo "✅ 核心脚本安装完成：$MAIN_SCRIPT_DEST"
}

# --------------------------
# 创建别名脚本（profile.d）
# --------------------------
create_alias_script() {
    echo -e "\n3. 创建别名脚本..."
    sudo tee "$ALIAS_SCRIPT_DEST" > /dev/null <<EOF
#!/bin/bash
# WSL端口管理别名（依赖PATH）
if [ -x "$MAIN_SCRIPT_DEST" ]; then
    alias port='$MAIN_SCRIPT_DEST port'
    alias portadd='$MAIN_SCRIPT_DEST port add'
    alias portdel='$MAIN_SCRIPT_DEST port delete'
    alias portlist='$MAIN_SCRIPT_DEST port list'
fi
EOF
    sudo chmod +x "$ALIAS_SCRIPT_DEST"
    echo "✅ 别名脚本安装完成：$ALIAS_SCRIPT_DEST"
}

# --------------------------
# 初始化端口配置
# --------------------------
init_port_config() {
    echo -e "\n4. 初始化端口配置..."
    if [ ! -f "/etc/wsl-port-manager/ports.conf" ]; then
        sudo touch "/etc/wsl-port-manager/ports.conf"
        sudo chmod 644 "/etc/wsl-port-manager/ports.conf"
    fi
    # 初始化