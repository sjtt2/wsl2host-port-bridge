#!/bin/bash
# 颜色定义
GREEN="\033[0;32m"    # 绿色：成功/标题
YELLOW="\033[1;33m"   # 黄色：提示/统计
BLUE="\033[0;34m"     # 蓝色：普通内容
CYAN="\033[0;36m"     # 青色：示例/说明
RED="\033[0;31m"      # 红色：错误信息
NC="\033[0m"          # 重置颜色

# 特殊字符定义
ARROW="❯"       # 箭头：用于引导操作
CHECK="✅"      # 对勾：用于成功提示
INFO="ℹ️"       # 信息：用于说明
WARNING="⚠️"    # 警告：用于提示
LIST="🔍"       # 列表：用于展示内容
PLUS="➕"       # 加号：用于添加操作
MINUS="➖"      # 减号：用于删除操作

# --------------------------
# 固定路径配置（与install.sh保持一致）
# --------------------------
# 启动脚本路径（port add/delete 会修改此文件）
FORWARD_SCRIPT="/etc/profile.d/wsl-ssh-portforward.sh"
# 端口配置文件（存储已添加的端口）
PORT_CONFIG="/etc/wsl-port-manager/ports.conf"
# 从install.sh生成的WSL信息文件（获取IP/版本）
WSL_INFO_FILE="/etc/wsl-port-manager/wsl-info.conf"

# --------------------------
# 辅助函数：读取WSL信息（IP/版本，由install.sh生成）
# --------------------------
get_wsl_info() {
    local key=$1
    if [ ! -f "$WSL_INFO_FILE" ]; then
        echo -e "${RED}${WARNING} 错误：WSL信息文件不存在，请重新执行install.sh${NC}"
        exit 1
    fi
    grep -oP "(?<=^$key=).+" "$WSL_INFO_FILE"
}

# --------------------------
# 核心功能：修改启动脚本（wsl-ssh-portforward.sh）
# --------------------------
# 1. 初始化启动脚本（确保基础结构）
init_forward_script() {
    if [ ! -f "$FORWARD_SCRIPT" ]; then
        sudo touch "$FORWARD_SCRIPT"
        sudo chmod +x "$FORWARD_SCRIPT"
        # 写入固定头部（包含WSL IP/版本，由install.sh生成）
        local WSL_IP=$(get_wsl_info "WSL_IP")
        local WSL_VERSION=$(get_wsl_info "WSL_VERSION")
        sudo tee "$FORWARD_SCRIPT" > /dev/null <<EOF
#!/bin/bash
# WSL端口转发自动启动脚本（由wsl-port-manager维护）
# 固定WSL信息（install.sh生成，请勿手动修改）
WSL_IP="$WSL_IP"
WSL_VERSION="$WSL_VERSION"

# 端口转发核心函数
start_port_forward() {
    if [ "\$WSL_VERSION" -eq 1 ]; then
        WSL_IP="127.0.0.1"
    fi
    echo -e "${GREEN}${ARROW} 正在启动WSL端口转发（IP: \$WSL_IP）...${NC}"
EOF
    fi
}

# 2. 同步端口配置到启动脚本（添加/删除后执行）
sync_ports_to_forward_script() {
    init_forward_script

    # 清空原有端口转发逻辑（保留头部）
    sudo sed -i '/^    # 自动生成的端口转发规则$/,$d' "$FORWARD_SCRIPT"

    # 写入新的端口转发规则
    sudo tee -a "$FORWARD_SCRIPT" > /dev/null <<EOF
    # 自动生成的端口转发规则（请勿手动修改）
EOF

    # 读取端口配置，逐行添加转发命令
    while IFS= read -r port; do
        if [ -n "$port" ]; then
            sudo tee -a "$FORWARD_SCRIPT" > /dev/null <<EOF
    powershell.exe -Command "
        netsh interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=$port 2>&1 | Out-Null;
        netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=$port connectaddress=\$WSL_IP connectport=$port
    " >/dev/null 2>&1
    echo -e "${BLUE}${CHECK} 已转发端口: $port${NC}"
EOF
        fi
    done < "$PORT_CONFIG"

    # 写入脚本尾部
    sudo tee -a "$FORWARD_SCRIPT" > /dev/null <<EOF
    echo -e "${GREEN}${CHECK} WSL端口转发启动完成${NC}"
}

# 启动端口转发（供启动脚本调用）
start_port_forward_wrapper() {
    if [ -f "$FORWARD_SCRIPT" ]; then
        bash "$FORWARD_SCRIPT"
    else
        echo -e "${RED}${WARNING} 错误：启动脚本不存在${NC}"
    fi
}

# --------------------------
# 端口管理命令（add/delete/list）
# --------------------------
# 添加端口
add_port() {
    local port=$1
    # 端口有效性校验
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo -e "${RED}${WARNING} 错误：无效端口 $port（需1-65535）${NC}"
        return 1
    fi

    # 检查端口是否已存在
    if grep -q "^$port$" "$PORT_CONFIG"; then
        echo -e "${YELLOW}${INFO} 提示：端口 $port 已配置${NC}"
        return 0
    fi

    # 添加到端口配置文件
    echo "$port" | sudo tee -a "$PORT_CONFIG" > /dev/null
    # 同步到启动脚本
    sync_ports_to_forward_script

    echo -e "${GREEN}${CHECK} 端口 $port 已添加（重启后自动生效，当前生效需执行：source $FORWARD_SCRIPT）${NC}"
}

# 删除端口
delete_port() {
    local port=$1
    # 端口有效性校验
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo -e "${RED}${WARNING} 错误：无效端口 $port${NC}"
        return 1
    fi

    # 检查端口是否存在
    if ! grep -q "^$port$" "$PORT_CONFIG"; then
        echo -e "${YELLOW}${INFO} 提示：端口 $port 未配置${NC}"
        return 0
    fi

    # 从配置文件删除
    sudo sed -i "/^$port$/d" "$PORT_CONFIG"
    # 同步到启动脚本
    sync_ports_to_forward_script

    # 立即删除当前转发规则
    sudo powershell.exe -Command "netsh interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=$port" 2>/dev/null
    echo -e "${GREEN}${CHECK} 端口 $port 已删除（重启后不再生效，当前已失效）${NC}"
}

# 列出端口
list_ports() {
    local port_count=$(grep -v '^$' "$PORT_CONFIG" | wc -l | awk '{print $1}')
    local WSL_IP=$(get_wsl_info "WSL_IP")
    local WSL_VERSION=$(get_wsl_info "WSL_VERSION")

    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}           ${LIST} 已配置端口转发列表 ${LIST}              ${NC}"
    echo -e "${BLUE}---------------------------------------------${NC}"
    echo -e "${YELLOW}  ${INFO} WSL IP: $WSL_IP${NC}"
    echo -e "${YELLOW}  ${INFO} WSL 版本: $WSL_VERSION${NC}"
    echo -e "${YELLOW}  ${INFO} 总端口数: $port_count 个${NC}"
    echo -e "${CYAN}  ${INFO} 启动脚本: $FORWARD_SCRIPT${NC}"
    echo -e "${BLUE}---------------------------------------------${NC}"

    if [ "$port_count" -gt 0 ]; then
        grep -v '^$' "$PORT_CONFIG" | sort -n | nl -w2 -s'. ' | while read -r line; do
            echo -e "${BLUE}  ${ARROW} $line${NC}"
        done
    else
        echo -e "${YELLOW}  ${INFO} 暂无配置端口，使用 'port add <端口号>' 添加${NC}"
    fi
    echo -e "${GREEN}=============================================${NC}"
}

# 帮助信息
show_help() {
    local WSL_IP=$(get_wsl_info "WSL_IP")
    local WSL_VERSION=$(get_wsl_info "WSL_VERSION")
    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}           wsl-port-manager                  ${NC}"
    echo -e "${CYAN}      ${INFO} WSL端口转发管理工具（自动启动版） ${INFO}       ${NC}"
    echo -e "${CYAN}      ${INFO} 当前WSL环境: IP=$WSL_IP, 版本=$WSL_VERSION ${INFO}       ${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo -e "使用方法: ${BLUE}port [命令] [参数]${NC}"
    echo
    echo -e "${YELLOW}核心命令:${NC}"
    echo -e "  ${BLUE}add${NC}    <端口号>   ${PLUS} 添加端口（同步到启动脚本）"
    echo -e "  ${BLUE}delete${NC} <端口号>   ${MINUS} 删除端口（同步到启动脚本）"
    echo -e "  ${BLUE}list${NC}              ${LIST} 查看已配置端口"
    echo -e "  ${BLUE}start${NC}             ${ARROW} 立即启动所有端口转发"
    echo -e "  ${BLUE}help${NC}              ${INFO} 显示本帮助"
    echo
    echo -e "${YELLOW}说明:${NC}"
    echo -e "  ${CYAN}1. 添加/删除端口会自动修改 $FORWARD_SCRIPT${NC}"
    echo -e "  ${CYAN}2. 重启WSL后会自动执行启动脚本${NC}"
    echo -e "  ${CYAN}3. 当前生效需执行：source $FORWARD_SCRIPT${NC}"
    echo -e "${GREEN}=============================================${NC}"
}

# --------------------------
# 命令解析入口
# --------------------------
case "$1" in
    port)
        case "$2" in
            add)
                add_port "$3"
                ;;
            delete)
                delete_port "$3"
                ;;
            list|ls)
                list_ports
                ;;
            start)
                start_port_forward_wrapper
                ;;
            help)
                show_help
                ;;
            *)
                show_help
                ;;
        esac
        ;;
    # 供install.sh调用的初始化函数
    init-forward-script)
        sync_ports_to_forward_script
        ;;
    *)
        show_help
        ;;
esac