#!/bin/bash

# 配置参数
GITHUB_REPO="sjtt2/wsl2host-port-bridge"  # 仓库路径
SCRIPT_FILE="wsl-port-manager.sh"         # 主脚本文件名
FORWARD_SCRIPT_NAME="wsl-ssh-portforward.sh"  # 转发脚本名
ALIAS_SCRIPT_NAME="wsl-port-aliases.sh"       # 别名脚本名

# 安装路径
DEST_DIR="/usr/local/bin"
SCRIPT_DEST="$DEST_DIR/$SCRIPT_FILE"
PROFILE_D_DIR="/etc/profile.d"
FORWARD_SCRIPT_DEST="$PROFILE_D_DIR/$FORWARD_SCRIPT_NAME"
ALIAS_SCRIPT_DEST="$PROFILE_D_DIR/$ALIAS_SCRIPT_NAME"

# 关键修改：获取登录用户的家目录
if [ -n "$SUDO_USER" ]; then
    # 如果是sudo运行，获取原始用户的家目录
    USER_HOME=$(eval echo ~"$SUDO_USER")
else
    # 如果不是sudo运行（直接root），使用当前用户家目录
    USER_HOME="$HOME"
fi

# 检查是否为root权限
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：请使用sudo或root权限运行安装脚本"
    echo "正确命令：sudo $0"
    exit 1
fi

# 检查依赖工具
check_dependency() {
    if ! command -v "$1" &> /dev/null; then
        echo "错误：未找到必要工具 '$1'，请先安装"
        exit 1
    fi
}

# 检查wget或curl是否存在
if command -v wget &> /dev/null; then
    DOWNLOAD_CMD="wget -q -O"
elif command -v curl &> /dev/null; then
    DOWNLOAD_CMD="curl -s -o"
else
    echo "错误：未找到wget或curl，请先安装其中一个"
    exit 1
fi

# 主安装流程
echo "===== 开始安装 wsl2host-port-bridge ====="

# 下载主脚本
echo "1. 从GitHub下载最新版本..."
$DOWNLOAD_CMD "$SCRIPT_DEST" "https://raw.githubusercontent.com/$GITHUB_REPO/main/$SCRIPT_FILE" || {
    echo "错误：下载主脚本失败"
    exit 1
}
chmod +x "$SCRIPT_DEST" || {
    echo "错误：设置主脚本执行权限失败"
    exit 1
}

# 创建端口转发启动脚本
echo "2. 配置启动脚本..."
cat <<'EOF' | tee "$FORWARD_SCRIPT_DEST" > /dev/null
#!/bin/bash
# WSL端口转发自动启动脚本

# 加载端口转发规则
if [ -x "/usr/local/bin/wsl-port-manager.sh" ]; then
    /usr/local/bin/wsl-port-manager.sh --load-on-startup
fi
EOF
chmod +x "$FORWARD_SCRIPT_DEST" || {
    echo "错误：设置启动脚本权限失败"
    exit 1
}

# 创建别名配置脚本
echo "3. 配置命令别名..."
cat <<'EOF' | tee "$ALIAS_SCRIPT_DEST" > /dev/null
#!/bin/bash
# 端口管理工具别名配置

# 开启别名扩展（兼容Bash）
if [ -n "$BASH_VERSION" ]; then
    shopt -s expand_aliases
fi

# 定义别名（使用绝对路径）
if [ -x "/usr/local/bin/wsl-port-manager.sh" ]; then
    alias port='/usr/local/bin/wsl-port-manager.sh port'
    alias portadd='/usr/local/bin/wsl-port-manager.sh portadd'
fi
EOF
chmod +x "$ALIAS_SCRIPT_DEST" || {
    echo "错误：设置别名脚本权限失败"
    exit 1
}

# 配置Zsh环境（修改.zshrc）
echo "4. 配置Zsh环境..."
# 使用登录用户的家目录路径
ZSHRC="$USER_HOME/.zshrc"

# 确保.zshrc存在
if [ ! -f "$ZSHRC" ]; then
    touch "$ZSHRC"
    # 修复权限：将文件所有者改为登录用户
    if [ -n "$SUDO_USER" ]; then
        chown "$SUDO_USER:$SUDO_USER" "$ZSHRC"
    fi
    chmod 644 "$ZSHRC"
fi

# 添加加载转发脚本
if ! grep -q "source $FORWARD_SCRIPT_DEST" "$ZSHRC"; then
    echo -e "\n# 加载WSL端口转发启动脚本" >> "$ZSHRC"
    echo "source $FORWARD_SCRIPT_DEST" >> "$ZSHRC"
fi

# 添加加载别名脚本
if ! grep -q "source $ALIAS_SCRIPT_DEST" "$ZSHRC"; then
    echo -e "\n# 加载WSL端口管理工具别名" >> "$ZSHRC"
    echo "source $ALIAS_SCRIPT_DEST" >> "$ZSHRC"
fi

# 完成提示
echo -e "\n===== 安装完成！ ====="
echo "请执行以下命令让配置立即生效："
echo "  • Bash用户：source /etc/profile"
echo "  • Zsh用户：source $ZSHRC"
echo "或重启终端后，直接使用 'port' 命令开始管理端口"
echo "示例：port add 22  # 添加22端口转发"
echo "Tip：Bash对全部用户起效，Zsh只对当前用户起效，切换用户请自行添加到~/.zshrc"