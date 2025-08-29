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

# 获取当前WSL发行版名称并生成标准化主机名
get_wsl_hostname() {
    # 从/etc/os-release获取发行版名称（兼容大多数Linux发行版）
    if [ -f "/etc/os-release" ]; then
        . /etc/os-release
        local distro_name="$NAME"
    else
        #  fallback: 从hostname获取
        local distro_name=$(hostname)
    fi

    # 标准化处理：移除特殊字符+小写化+添加.wsl后缀
    # 例如 "Ubuntu-20.04" → "ubuntu2004.wsl"，"Debian GNU/Linux" → "debiangnulinux.wsl"
    local normalized_name=$(echo "$distro_name" | sed -E 's/[^a-zA-Z0-9]//g' | tr '[:upper:]' '[:lower:]')
    echo "${normalized_name}.wsl"
}

# 配置文件路径（系统级配置目录）
PORT_CONFIG="/etc/wsl-port-manager/ports.conf"
# 启动脚本路径（系统自动执行目录）
FORWARD_SCRIPT="/etc/profile.d/wsl-ssh-portforward.sh"

# 确保配置目录和文件存在（符合Linux规范）
sudo mkdir -p /etc/wsl-port-manager/
sudo touch "$PORT_CONFIG"
sudo chmod 644 "$PORT_CONFIG"  # 系统配置文件通常为644权限

# 确保启动脚本存在
if [ ! -f "$FORWARD_SCRIPT" ]; then
    sudo touch "$FORWARD_SCRIPT"
    sudo chmod +x "$FORWARD_SCRIPT"
    echo "#!/bin/bash" | sudo tee "$FORWARD_SCRIPT" > /dev/null
    # 添加启动加载逻辑
    echo "/usr/local/bin/wsl-port-manager.sh --load-on-startup" | sudo tee -a "$FORWARD_SCRIPT" > /dev/null
fi

# 定义别名
define_aliases() {
    if ! alias | grep -q "portadd="; then
        alias port='wsl-port-manager.sh port'
        alias portadd='wsl-port-manager.sh portadd'
    fi
}

# 启动时自动加载端口转发
load_ports_on_startup() {
    # 获取当前WSL的IP和标准化主机名
    WSL_IP=$(hostname -I | awk '{print $1}')
    WSL_HOSTNAME=$(get_wsl_hostname)
    
    if [ -z "$WSL_IP" ]; then
        echo -e "${RED}${WARNING} 警告：无法获取WSL IP，端口转发未自动配置${NC}"
        return 1
    fi

    echo -e "${GREEN}${ARROW} 正在自动配置端口转发（主机名: $WSL_HOSTNAME）...${NC}"
    while IFS= read -r port; do
        if [ -n "$port" ]; then
            sudo powershell.exe -Command "
                netsh interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=$port 2>&1 | Out-Null;
                netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=$port connectaddress=$WSL_HOSTNAME connectport=$port
            " >/dev/null 2>&1
            echo -e "${BLUE}${CHECK} 已自动配置端口: $port${NC}"
        fi
    done < "$PORT_CONFIG"
    echo -e "${GREEN}${CHECK} 端口自动配置完成${NC}"
}

# 添加端口函数
add_port() {
    local port=$1
    # 获取标准化主机名
    local wsl_hostname=$(get_wsl_hostname)
    
    # 验证端口有效性
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo -e "${RED}${WARNING} 错误：无效的端口号 $port，请使用1-65535之间的数字${NC}"
        return 1
    fi
    
    # 检查是否已存在
    if grep -q "^$port$" "$PORT_CONFIG"; then
        echo -e "${YELLOW}${INFO} 端口 $port 已存在${NC}"
        return 0
    fi
    
    # 立即生效：添加端口转发规则
    echo -e "${GREEN}${PLUS} 正在配置端口 $port 转发（主机名: $wsl_hostname，立即生效）...${NC}"
    if ! sudo powershell.exe -Command "
        netsh interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=$port 2>&1 | Out-Null;
        netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=$port connectaddress=$wsl_hostname connectport=$port
    "; then
        echo -e "${RED}${WARNING} 错误：端口 $port 转发配置失败${NC}"
        return 1
    fi
    
    # 持久化：添加到配置文件
    echo "$port" | sudo tee -a "$PORT_CONFIG" > /dev/null
    
    echo -e "${GREEN}${CHECK} 端口 $port 已成功添加（立即生效，重启后自动配置）${NC}"
}

# 删除端口函数
delete_port() {
    local port=$1
    
    # 验证端口有效性
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo -e "${RED}${WARNING} 错误：无效的端口号 $port${NC}"
        return 1
    fi
    
    # 检查是否存在
    if ! grep -q "^$port$" "$PORT_CONFIG"; then
        echo -e "${YELLOW}${INFO} 端口 $port 不存在${NC}"
        return 0
    fi
    
    # 立即生效：删除端口转发规则
    echo -e "${GREEN}${MINUS} 正在删除端口 $port 转发（立即生效）...${NC}"
    sudo powershell.exe -Command "
        netsh interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=$port
    " 2>/dev/null
    
    # 从配置文件中删除
    sudo sed -i "/^$port$/d" "$PORT_CONFIG"
    
    echo -e "${GREEN}${CHECK} 端口 $port 已成功删除（立即失效，重启后不再配置）${NC}"
}

# 带特殊字符的端口列表展示
list_ports() {
    # 获取标准化主机名
    local wsl_hostname=$(get_wsl_hostname)
    # 统计端口数量
    local port_count=$(grep -v '^$' "$PORT_CONFIG" | wc -l | awk '{print $1}')
    
    # 打印标题和统计信息
    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}           ${LIST} 已配置的端口转发列表 ${LIST}              ${NC}"
    echo -e "${BLUE}---------------------------------------------${NC}"
    echo -e "${YELLOW}  ${INFO} 主机名: $wsl_hostname${NC}"
    echo -e "${YELLOW}  ${INFO} 总数量: $port_count 个端口${NC}"
    echo -e "${CYAN}  ${INFO} 映射规则: Windows端口 → WSL对应端口${NC}"
    echo -e "${BLUE}---------------------------------------------${NC}"
    
    # 显示端口列表（带序号）
    if [ "$port_count" -gt 0 ]; then
        grep -v '^$' "$PORT_CONFIG" | sort -n | nl -w2 -s'. ' | while read -r line; do
            echo -e "${BLUE}  ${ARROW} $line${NC}"
        done
    else
        echo -e "${YELLOW}  ${INFO} 暂无配置的端口，可使用 'port add <端口号>' 添加${NC}"
    fi
    
    # 底部边框
    echo -e "${GREEN}=============================================${NC}"
}

# 带特殊字符的帮助信息
show_help() {
    # 获取标准化主机名
    local wsl_hostname=$(get_wsl_hostname)
    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}           wsl2host-port-bridge              ${NC}"
    echo -e "${CYAN}      ${INFO} 配合wsl2host的WSL端口转发管理工具 ${INFO}       ${NC}"
    echo -e "${CYAN}      ${INFO} 当前主机名: $wsl_hostname ${INFO}       ${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo -e "使用方法: ${BLUE}port [命令] [参数]${NC}"
    echo
    echo -e "${YELLOW}端口管理命令:${NC}"
    echo -e "  ${BLUE}add${NC}    <端口号>   ${PLUS} 添加端口转发（立即生效）"
    echo -e "  ${BLUE}open${NC}   <端口号>   ${PLUS} 同add，添加端口转发"
    echo -e "  ${BLUE}delete${NC} <端口号>   ${MINUS} 删除端口转发（立即失效）"
    echo -e "  ${BLUE}ban${NC}    <端口号>   ${MINUS} 同delete，删除端口转发"
    echo -e "  ${BLUE}list${NC}              ${LIST} 查看所有已配置端口"
    echo -e "  ${BLUE}ls${NC}                ${LIST} 同list，查看已配置端口"
    echo -e "  ${BLUE}check${NC}             ${LIST} 同list，查看已配置端口"
    echo -e "  ${BLUE}help${NC}              ${INFO} 显示本帮助信息"
    echo
    echo -e "${YELLOW}快捷命令:${NC}"
    echo -e "  ${BLUE}portadd${NC} <端口号>  ${PLUS} 直接添加端口（等效于port add）"
    echo
    echo -e "${YELLOW}示例:${NC}"
    echo -e "  ${CYAN}port add 22${NC}       ${PLUS} 添加22端口转发"
    echo -e "  ${CYAN}port delete 8080${NC}  ${MINUS} 删除8080端口转发"
    echo -e "  ${CYAN}port list${NC}         ${LIST} 查看所有转发端口"
    echo -e "${GREEN}=============================================${NC}"
}

# 初始化别名
define_aliases() {
    if ! alias | grep -q "portadd="; then
        alias port='wsl-port-manager.sh port'
        alias portadd='wsl-port-manager.sh portadd'
    fi
}

# 命令解析
case "$1" in
    port)
        case "$2" in
            add|open)
                add_port "$3"
                ;;
            delete|ban)
                delete_port "$3"
                ;;
            check|list|ls)
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
    portadd)
        add_port "$2"
        ;;
    --load-on-startup)
        load_ports_on_startup
        ;;
    *)
        show_help
        ;;
esac
