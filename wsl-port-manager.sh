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
# 路径配置（均为相对/标准路径，依赖系统PATH）
# --------------------------
FORWARD_SCRIPT="/etc/profile.d/wsl-ssh-portforward.sh"  # 启动脚本
PORT_CONFIG="/etc/wsl-port-manager/ports.conf"          # 端口配置
WSL_INFO_FILE="/etc/wsl-port-manager/wsl-info.conf"     # WSL信息（install生成）

# --------------------------
# 辅助函数：读取WSL信息（IP/版本）
# --------------------------
get_wsl_info() {
    local key=$1
    if [ ! -f "$WSL_INFO_FILE" ]; then
        echo -e "${RED}${WARNING} 错误：WSL信息文件不存在，请用 sudo -E 重新执行install.sh${NC}"
        exit 1
    fi
    grep -oP "(?<=^$key=).+" "$WSL_INFO_FILE"
}

# --------------------------
# 核心：初始化/同步启动脚本
# --------------------------
init_forward_script() {
    if [ ! -f "$FORWARD_SCRIPT" ]; then
        sudo touch "$FORWARD_SCRIPT"
        sudo chmod +x "$FORWARD_SCRIPT"
        # 写入启动脚本头部（含WSL信息读取逻辑）
        local WSL_IP=$(get_wsl_info "WSL_IP")
        local WSL_VERSION=$(get_wsl_info "WSL_VERSION")
        sudo tee "$FORWARD_SCRIPT" > /dev/null <<EOF
#!/bin/bash
# WSL端口转发自动启动脚本（依赖PATH，由wsl-port-manager维护）
WSL_INFO_FILE="$WSL_INFO_FILE"
PORT_CONFIG="$PORT_CONFIG"

# 读取WSL信息
get_wsl_info() {
    local key=\$1
    grep -oP "(?<=^\$key=).+" "\$WSL_INFO_FILE"
}

# 端口转发核心逻辑
start_port_forward() {
    local WSL_IP=\$(get_wsl_info "WSL_IP")
    local WSL_VERSION=\$(get_wsl_info "WSL_VERSION")
    
    # WSL1固定IP，WSL2用动态IP
    if [ "\$WSL_VERSION" -eq 1 ]; then
        WSL_IP="127.0.0.1"
    fi

    echo -e "${GREEN}${ARROW} 正在启动WSL端口转发（IP: \$WSL_IP）...${NC}"
EOF
    fi
}

# 同步端口到启动脚本
sync_ports_to_forward_script() {
    init_forward_script

    # 清空原有端口规则（保留头部）
    sudo sed -i '/^    # 自动生成的端口规则$/,$d' "$FORWARD_SCRIPT"

    # 写入新端口规则（调用powershell.exe，依赖PATH）
    sudo tee -a "$FORWARD_SCRIPT" > /dev/null <<EOF
    # 自动生成的端口规则（请勿手动修改）
EOF

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

# 自动执行（仅交互式shell）
if [ -n "\$PS1" ] || [ -n "\$ZSH_VERSION" ]; then
    start_port_forward
fi
EOF
}

# --------------------------
# 端口管理命令（add/delete/list）
# --------------------------
add_port() {
    local port=$1
    # 端口校验
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo -e "${RED}${WARNING} 错误：无效端口 $port（需1-65535）${NC}"
        return 1
    fi

    # 检查重复
    if grep -q "^$port$" "$PORT_CONFIG"; then
        echo -e "${YELLOW}${INFO} 提示：端口 $port 已配置${NC}"
        return 0
    fi

    # 添加并同步
    echo "$port" | sudo tee -a "$PORT_CONFIG" > /dev/null
    sync_ports_to_forward_script
    echo -e "${GREEN}${CHECK} 端口 $port 已添加（重启生效，当前生效：source $FORWARD_SCRIPT）${NC}"
}

delete_port() {
    local port=$1
    # 端口校验
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo -e "${RED}${WARNING} 错误：无效端口 $port${NC}"
        return 1
    fi

    # 检查存在
    if ! grep -q "^$port$" "$PORT_CONFIG"; then
        echo -e "${YELLOW}${INFO} 提示：端口 $port 未配置${NC}"
        return 0
    fi

    # 删除并同步
    sudo sed -i "/^$port$/d" "$PORT_CONFIG"
    sync_ports_to_forward_script
    # 立即删除当前转发（依赖PATH调用powershell）
    sudo powershell.exe -Command "netsh interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=$port" 2>/dev/null
    echo -e "${GREEN}${CHECK} 端口 $port 已删除（当前失效，重启不再生效）${NC}"
}

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
    echo -e "${CYAN}  ${INFO} 依赖PATH：powershell.exe 可直接调用${NC}"
    echo -e "${BLUE}---------------------------------------------${NC}"

    if [ "$port_count" -gt 0 ]; then
        grep -v '^$' "$PORT_CONFIG" | sort -n | nl -w2 -s'. ' | while read -r line; do
            echo -e "${BLUE}  ${ARROW} $line${NC}"
        done
    else
        echo -e "${YELLOW}  ${INFO} 暂无端口，使用 'port add <端口号>' 添加${NC}"
    fi
    echo -e "${GREEN}=============================================${NC}"
}

# 帮助信息
show_help() {
    local WSL_IP=$(get_wsl_info "WSL_IP")
    local WSL_VERSION=$(get_wsl_info "WSL_VERSION")
    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}           wsl-port-manager（依赖PATH版）      ${NC}"
    echo -e "${CYAN}      ${INFO} 执行安装需用：sudo -E bash install.sh ${INFO}       ${NC}"
    echo -e "${CYAN}      ${INFO} 当前环境：IP=$WSL_IP，版本=WSL$WSL_VERSION ${INFO}       ${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo -e "使用方法: ${BLUE}port [命令] [参数]${NC}"
    echo
    echo -e "${YELLOW}核心命令:${NC}"
    echo -e "  ${BLUE}add${NC}    <端口号>   ${PLUS} 添加端口（同步启动脚本）"
    echo -e "  ${BLUE}delete${NC} <端口号>   ${MINUS} 删除端口（同步启动脚本）"
    echo -e "  ${BLUE}list${NC}              ${LIST} 查看已配置端口"
    echo -e "  ${BLUE}help${NC}              ${INFO} 显示本帮助"
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
            help)
                show_help
                ;;
            *)
                show_help
                ;;
        esac
        ;;
    init-forward-script)
        sync_ports_to_forward_script
        ;;
    *)
        show_help
        ;;
esac