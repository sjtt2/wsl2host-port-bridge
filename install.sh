#!/bin/bash
# 配置参数
GITHUB_REPO="sjtt2/wsl2host-port-bridge"  # 你的GitHub仓库
MAIN_SCRIPT="wsl-port-manager.sh"         # 核心脚本名
FORWARD_SCRIPT="wsl-ssh-portforward.sh"   # 启动脚本名（放profile.d）
ALIAS_SCRIPT="wsl-port-aliases.sh"        # 别名脚本名（放profile.d）
WSL_INFO_FILE="wsl-info.conf"             # WSL信息文件（IP/版本）

# 关键修复：powershell.exe 绝对路径（WSL中固定）
POWERSHELL_PATH="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"

# 安装路径
DEST_DIR="/usr/local/bin"
MAIN_SCRIPT_DEST="$DEST_DIR/$MAIN_SCRIPT"
PROFILE_D_DIR="/etc/profile.d"
FORWARD_SCRIPT_DEST="$PROFILE_D_DIR/$FORWARD_SCRIPT"
ALIAS_SCRIPT_DEST="$PROFILE_D_DIR/$ALIAS_SCRIPT"
WSL_INFO_DEST="/etc/wsl-port-manager/$WSL_INFO_FILE"

# --------------------------
# 前置检查（修复WSL环境检测）
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
    echo "错误：请先安装wget或curl（命令：sudo apt install wget/curl）"
    exit 1
fi

# 3. 修复：WSL环境检测（用绝对路径检查powershell.exe）
if [ ! -x "$POWERSHELL_PATH" ]; then
    echo "错误：未找到powershell.exe（路径：$POWERSHELL_PATH）"
    echo "原因可能：1. 未挂载C盘 2. WSL未启用Windows命令访问"
    echo "修复建议：执行 'sudo mkdir -p /mnt/c' 后重新运行"
    exit 1
fi

# --------------------------
# 核心：WSL版本/IP检测（仅在install时执行，用绝对路径调用powershell）
# --------------------------
detect_wsl_env() {
    echo "1. 检测WSL环境..."
    local current_hostname=$(cat /proc/sys/kernel/hostname)
    
    # 修复：用绝对路径执行wsl.exe -l -v
    local wsl_list_output=$("$POWERSHELL_PATH" -Command "wsl.exe -l -v" 2>/dev/null | iconv -f UTF-16LE -t UTF-8 | tr -d '\r')

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
# 安装核心脚本（wsl-port-manager.sh）
# --------------------------
install_main_script() {
    echo -e "\n2. 安装核心脚本..."
    # 从GitHub下载核心脚本
    $DOWNLOAD_CMD "$MAIN_SCRIPT_DEST" "https://raw.githubusercontent.com/$GITHUB_REPO/main/$MAIN_SCRIPT" || {
        echo "错误：从GitHub下载 $MAIN_SCRIPT 失败"
        exit 1
    }
    sudo chmod +x "$MAIN_SCRIPT_DEST"
    echo "✅ 核心脚本安装完成：$MAIN_SCRIPT_DEST"
}

# --------------------------
# 创建启动脚本（profile.d/wsl-ssh-portforward.sh）
# --------------------------
create_forward_script() {
    echo -e "\n3. 创建启动脚本..."
    sudo tee "$FORWARD_SCRIPT_DEST" > /dev/null <<'EOF'
#!/bin/bash
# WSL端口转发自动启动脚本（由install.sh生成，wsl-port-manager维护）
WSL_INFO_FILE="/etc/wsl-port-manager/wsl-info.conf"

# 读取WSL信息
get_wsl_info() {
    local key=$1
    grep -oP "(?<=^$key=).+" "$WSL_INFO_FILE"
}

# 启动端口转发
start_port_forward() {
    if [ ! -f "$WSL_INFO_FILE" ]; then
        echo -e "\033[0;31m⚠️  错误：WSL信息文件不存在，请重新执行install.sh\033[0m"
        return 1
    fi

    local WSL_IP=$(get_wsl_info "WSL_IP")
    local WSL_VERSION=$(get_wsl_info "WSL_VERSION")
    local PORT_CONFIG="/etc/wsl-port-manager/ports.conf"

    if [ "$WSL_VERSION" -eq 1 ]; then
        WSL_IP="127.0.0.1"
    fi

    echo -e "\033[0;32m❯ 正在启动WSL端口转发（IP: $WSL_IP）...\033[0m"
    if [ -f "$PORT_CONFIG" ]; then
        while IFS= read -r port; do
            if [ -n "$port" ]; then
                /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -Command "
                    netsh interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=$port 2>&1 | Out-Null;
                    netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=$port connectaddress=$WSL_IP connectport=$port
                " >/dev/null 2>&1
                echo -e "\033[0;34m✅ 已转发端口: $port\033[0m"
            fi
        done < "$PORT_CONFIG"
    fi
    echo -e "\033[0;32m✅ WSL端口转发启动完成\033[0m"
}

# 自动执行转发（仅在交互式shell中运行）
if [ -n "$PS1" ] || [ -n "$ZSH_VERSION" ]; then
    start_port_forward
fi
EOF
    sudo chmod +x "$FORWARD_SCRIPT_DEST"
    echo "✅ 启动脚本创建完成：$FORWARD_SCRIPT_DEST"
}

# --------------------------
# 创建别名脚本（profile.d/wsl-port-aliases.sh）
# --------------------------
create_alias_script() {
    echo -e "\n4. 创建别名脚本..."
    sudo tee "$ALIAS_SCRIPT_DEST" > /dev/null <<EOF
#!/bin/bash
# WSL端口管理工具别名（由install.sh生成）
if [ -x "$MAIN_SCRIPT_DEST" ]; then
    alias port='$MAIN_SCRIPT_DEST port'
    alias portadd='$MAIN_SCRIPT_DEST port add'
    alias portdel='$MAIN_SCRIPT_DEST port delete'
    alias portlist='$MAIN_SCRIPT_DEST port list'
fi
EOF
    sudo chmod +x "$ALIAS_SCRIPT_DEST"
    echo "✅ 别名脚本创建完成：$ALIAS_SCRIPT_DEST"
}

# --------------------------
# 初始化端口配置文件
# --------------------------
init_port_config() {
    echo -e "\n5. 初始化端口配置..."
    sudo mkdir -p /etc/wsl-port-manager/
    if [ ! -f "/etc/wsl-port-manager/ports.conf" ]; then
        sudo touch "/etc/wsl-port-manager/ports.conf"
        sudo chmod 644 "/etc/wsl-port-manager/ports.conf"
    fi
    echo "✅ 端口配置文件初始化完成：/etc/wsl-port-manager/ports.conf"
}

# --------------------------
# 完成提示
# --------------------------
show_complete() {
    echo -e "\n======================================"
    echo -e "✅ 所有组件安装完成！"
    echo -e "\n请执行以下命令让配置立即生效："
    echo -e "  Bash用户：source /etc/profile"
    echo -e "  Zsh用户：source ~/.zshrc"
    echo -e "\n使用示例："
    echo -e "  port add 22    # 添加22端口转发"
    echo -e "  port list      # 查看已配置端口"
    echo -e "  port delete 22 # 删除22端口转发"
    echo -e "======================================"
}

# --------------------------
# 主安装流程
# --------------------------
detect_wsl_env
install_main_script
create_forward_script
create_alias_script
init_port_config
show_complete