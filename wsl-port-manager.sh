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
# 完全对齐go-wsl2-host的WSL版本检测逻辑
# 1. 执行wsl.exe -l -v获取原始输出
# 2. 解析输出提取当前发行版的版本号（1或2）
# --------------------------
get_wsl_version() {
    # 获取当前WSL实例的精确名称（从/proc/sys/kernel/hostname，同wsl2host）
    local current_hostname=$(cat /proc/sys/kernel/hostname)
    
    # 执行wsl.exe -l -v并处理编码（同wslcli.ListAll()）
    local wsl_list_output
    wsl_list_output=$(powershell.exe -Command "wsl.exe -l -v" 2>/dev/null)
    # 处理Windows命令输出的UTF-16LE编码问题
    wsl_list_output=$(echo "$wsl_list_output" | iconv -f UTF-16LE -t UTF-8 2>/dev/null | tr -d '\r')
    
    # 检查命令输出是否有效
    if [ -z "$wsl_list_output" ]; then
        echo -e "${YELLOW}${WARNING} 警告：wsl.exe -l -v执行失败，无法获取版本信息${NC}"
        return 1
    fi

    # 按行分割输出（同strings.Split(output, "\r\n")）
    local lines=()
    while IFS= read -r line; do
        lines+=("$line")
    done <<< "$wsl_list_output"

    # 跳过表头行（同lines = lines[1:]）
    if [ ${#lines[@]} -lt 2 ]; then
        echo -e "${YELLOW}${WARNING} 警告：WSL发行版列表为空${NC}"
        return 1
    fi
    local data_lines=("${lines[@]:1}")  # 从第2行开始处理数据

    # 遍历每行解析发行版信息（同Go代码的for循环）
    local version=""
    for line in "${data_lines[@]}"; do
        # 跳过空行
        line=$(echo "$line" | xargs)  # 等效于strings.TrimSpace()
        if [ -z "$line" ]; then
            continue
        fi

        # 处理默认发行版的"*"标记（同Go代码的if line[0] == '*'）
        local is_default=0
        if [[ "$line" == \* ]]; then
            is_default=1
            line=$(echo "$line" | cut -c 2- | xargs)  # 移除*并修剪空格
        fi

        # 按空格分割字段（同strings.Fields(line)）
        # 兼容发行版名称含空格的情况（如"Kali Linux"）
        local fields=($line)
        local field_count=${#fields[@]}
        if [ $field_count -lt 3 ]; then
            continue  # 跳过格式不正确的行
        fi

        # 提取名称、状态、版本（同Go代码的fields[0], fields[1], fields[2]）
        local distro_name="${fields[0]}"
        # 合并名称中包含空格的情况（合并前n-2个字段）
        if [ $field_count -gt 3 ]; then
            local name_parts=("${fields[@]:0:$field_count-2}")
            distro_name=$(IFS=' '; echo "${name_parts[*]}")
        fi
        local state="${fields[$field_count-2]}"
        local distro_version="${fields[$field_count-1]}"

        # 匹配当前发行版（通过hostname精确匹配）
        if [ "$distro_name" = "$current_hostname" ]; then
            # 验证版本号是否为1或2（同Go代码的strconv.ParseInt）
            if [[ "$distro_version" =~ ^[12]$ ]]; then
                version="$distro_version"
                break
            fi
        fi
    done

    # 返回版本检测结果
    if [ -n "$version" ]; then
        echo "$version"
        return 0
    else
        echo -e "${YELLOW}${WARNING} 警告：未找到当前发行版的版本信息${NC}"
        return 1
    fi
}

# --------------------------
# 精准生成 wsl2host 风格主机名（含版本号）
# --------------------------
get_current_wsl_distro_with_version() {
    # 从 os-release 获取基础信息（NAME + VERSION_ID）
    local name=$(grep -oP '(?<=^NAME=).+' /etc/os-release | tr -d '"' | tr ' ' '-')
    local version_id=$(grep -oP '(?<=^VERSION_ID=).+' /etc/os-release | tr -d '"')
    
    # 提取主版本号（如 22.04 → 2204，11 → 11）
    local main_version=$(echo "$version_id" | sed 's/\.[0-9]*$//' | tr -d '.')
    
    # 组合成 "名称-主版本" 格式（如 Ubuntu-2204，Debian-11）
    echo "${name}-${main_version}"
}

generate_wsl2host_hostname() {
    local distro=$(get_current_wsl_distro_with_version)
    
    # 1. 转为小写（Ubuntu-2204 → ubuntu-2204）
    local lower_case=$(echo "$distro" | tr '[:upper:]' '[:lower:]')
    
    # 2. 移除非字母数字字符（ubuntu-2204 → ubuntu2204）
    local cleaned=$(echo "$lower_case" | sed 's/[^a-z0-9]//g')
    
    # 3. 添加 .wsl 后缀（ubuntu2204 → ubuntu2204.wsl）
    echo "${cleaned}.wsl"
}

# --------------------------
# 原有核心功能（适配 WSL 版本）
# --------------------------
# 配置文件路径
PORT_CONFIG="/etc/wsl-port-manager/ports.conf"
FORWARD_SCRIPT="/etc/profile.d/wsl-ssh-portforward.sh"

# 确保配置目录和文件存在
sudo mkdir -p /etc/wsl-port-manager/
sudo touch "$PORT_CONFIG"
sudo chmod 644 "$PORT_CONFIG"

# 确保启动脚本存在
if [ ! -f "$FORWARD_SCRIPT" ]; then
    sudo touch "$FORWARD_SCRIPT"
    sudo chmod +x "$FORWARD_SCRIPT"
    echo "#!/bin/bash" | sudo tee "$FORWARD_SCRIPT" > /dev/null
    echo "/usr/local/bin/wsl-port-manager.sh --load-on-startup" | sudo tee -a "$FORWARD_SCRIPT" > /dev/null
fi

# 定义别名
define_aliases() {
    if ! alias | grep -q "portadd="; then
        alias port='wsl-port-manager.sh port'
        alias portadd='wsl-port-manager.sh portadd'
    fi
}

# 启动时自动加载端口转发（适配 WSL 1/2 差异）
load_ports_on_startup() {
    local WSL_HOSTNAME=$(generate_wsl2host_hostname)
    local WSL_VERSION=$(get_wsl_version)  # 获取 WSL 版本
    local WSL_IP

    # 严格区分WSL1/WSL2的IP处理（同go-wsl2-host逻辑）
    if [ "$WSL_VERSION" = "1" ]; then
        WSL_IP="127.0.0.1"  # WSL1固定IP
        echo -e "${GREEN}${ARROW} 检测到WSL1，使用固定IP: $WSL_IP（主机名: $WSL_HOSTNAME）${NC}"
    elif [ "$WSL_VERSION" = "2" ]; then
        # WSL2动态获取IP
        WSL_IP=$(hostname -I | awk '{print $1}')
        if [ -z "$WSL_IP" ]; then
            WSL_IP=$(grep -oP '(?<=inet\s)\d+(\.\d+){3}' /proc/net/fib_trie | grep -v '^127\.' | head -n 1)
        fi
        echo -e "${GREEN}${ARROW} 检测到WSL2，动态IP: $WSL_IP（主机名: $WSL_HOSTNAME）${NC}"
    else
        echo -e "${RED}${WARNING} 错误：WSL版本检测失败，无法加载端口转发${NC}"
        return 1
    fi

    # 加载端口转发规则
    while IFS= read -r port; do
        if [ -n "$port" ]; then
            sudo powershell.exe -Command "
                netsh interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=$port 2>&1 | Out-Null;
                netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=$port connectaddress=$WSL_IP connectport=$port
            " >/dev/null 2>&1
            echo -e "${BLUE}${CHECK} 已配置端口: $port${NC}"
        fi
    done < "$PORT_CONFIG"
    echo -e "${GREEN}${CHECK} 端口自动配置完成${NC}"
}

# 添加端口（适配 WSL 版本）
add_port() {
    local port=$1
    local WSL_HOSTNAME=$(generate_wsl2host_hostname)
    local WSL_VERSION=$(get_wsl_version)
    local WSL_IP

    # 验证端口有效性
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo -e "${RED}${WARNING} 错误：无效的端口号 $port，请使用1-65535之间的数字${NC}"
        return 1
    fi

    # 检查端口是否已存在
    if grep -q "^$port$" "$PORT_CONFIG"; then
        echo -e "${YELLOW}${INFO} 端口 $port 已存在${NC}"
        return 0
    fi

    # 适配 WSL 版本获取 IP
    if [ "$WSL_VERSION" = "1" ]; then
        WSL_IP="127.0.0.1"
    elif [ "$WSL_VERSION" = "2" ]; then
        WSL_IP=$(hostname -I | awk '{print $1}')
        if [ -z "$WSL_IP" ]; then
            WSL_IP=$(grep -oP '(?<=inet\s)\d+(\.\d+){3}' /proc/net/fib_trie | grep -v '^127\.' | head -n 1)
        fi
        if [ -z "$WSL_IP" ]; then
            echo -e "${RED}${WARNING} 错误：WSL2 IP 获取失败，无法添加端口转发${NC}"
            return 1
        fi
    else
        echo -e "${RED}${WARNING} 错误：WSL版本检测失败，无法添加端口转发${NC}"
        return 1
    fi

    # 配置端口转发
    echo -e "${GREEN}${PLUS} 配置端口 $port 转发（WSL$WSL_VERSION，主机名: $WSL_HOSTNAME，IP: $WSL_IP）...${NC}"
    if ! sudo powershell.exe -Command "
        netsh interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=$port 2>&1 | Out-Null;
        netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=$port connectaddress=$WSL_IP connectport=$port
    "; then
        echo -e "${RED}${WARNING} 错误：端口 $port 转发配置失败${NC}"
        return 1
    fi

    # 持久化端口
    echo "$port" | sudo tee -a "$PORT_CONFIG" > /dev/null
    echo -e "${GREEN}${CHECK} 端口 $port 已添加（WSL$WSL_VERSION 适配，重启后自动生效）${NC}"
}

# 删除端口（原有逻辑不变）
delete_port() {
    local port=$1
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo -e "${RED}${WARNING} 错误：无效的端口号 $port${NC}"
        return 1
    fi
    if ! grep -q "^$port$" "$PORT_CONFIG"; then
        echo -e "${YELLOW}${INFO} 端口 $port 不存在${NC}"
        return 0
    fi

    echo -e "${GREEN}${MINUS} 删除端口 $port 转发...${NC}"
    sudo powershell.exe -Command "netsh interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=$port" 2>/dev/null
    sudo sed -i "/^$port$/d" "$PORT_CONFIG"
    echo -e "${GREEN}${CHECK} 端口 $port 已删除（立即失效）${NC}"
}

# 列出端口（显示 WSL 版本信息）
list_ports() {
    local WSL_HOSTNAME=$(generate_wsl2host_hostname)
    local WSL_VERSION=$(get_wsl_version)
    local port_count=$(grep -v '^$' "$PORT_CONFIG" | wc -l | awk '{print $1}')

    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}           ${LIST} 已配置的端口转发列表 ${LIST}              ${NC}"
    echo -e "${BLUE}---------------------------------------------${NC}"
    echo -e "${YELLOW}  ${INFO} 主机名: $WSL_HOSTNAME${NC}"
    echo -e "${YELLOW}  ${INFO} WSL 版本: $WSL_VERSION${NC}"
    echo -e "${YELLOW}  ${INFO} 总数量: $port_count 个端口${NC}"
    echo -e "${CYAN}  ${INFO} 映射规则: Windows端口 → WSL对应端口${NC}"
    echo -e "${BLUE}---------------------------------------------${NC}"

    if [ "$port_count" -gt 0 ]; then
        grep -v '^$' "$PORT_CONFIG" | sort -n | nl -w2 -s'. ' | while read -r line; do
            echo -e "${BLUE}  ${ARROW} $line${NC}"
        done
    else
        echo -e "${YELLOW}  ${INFO} 暂无配置的端口，使用 'port add <端口号>' 添加${NC}"
    fi
    echo -e "${GREEN}=============================================${NC}"
}

# 帮助信息（新增 WSL 版本说明）
show_help() {
    local WSL_HOSTNAME=$(generate_wsl2host_hostname)
    local WSL_VERSION=$(get_wsl_version)
    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}           wsl2host-port-bridge              ${NC}"
    echo -e "${CYAN}      ${INFO} 适配 WSL1/WSL2 的端口转发管理工具 ${INFO}       ${NC}"
    echo -e "${CYAN}      ${INFO} 当前环境: $WSL_HOSTNAME (WSL$WSL_VERSION) ${INFO}       ${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo -e "使用方法: ${BLUE}port [命令] [参数]${NC}"
    echo
    echo -e "${YELLOW}端口管理命令:${NC}"
    echo -e "  ${BLUE}add${NC}    <端口号>   ${PLUS} 添加端口转发（适配 WSL 版本）"
    echo -e "  ${BLUE}open${NC}   <端口号>   ${PLUS} 同add，添加端口转发"
    echo -e "  ${BLUE}delete${NC} <端口号>   ${MINUS} 删除端口转发（立即失效）"
    echo -e "  ${BLUE}ban${NC}    <端口号>   ${MINUS} 同delete，删除端口转发"
    echo -e "  ${BLUE}list${NC}              ${LIST} 查看所有已配置端口（含 WSL 版本）"
    echo -e "  ${BLUE}ls${NC}                ${LIST} 同list，查看已配置端口"
    echo -e "  ${BLUE}check${NC}             ${LIST} 同list，查看已配置端口"
    echo -e "  ${BLUE}help${NC}              ${INFO} 显示本帮助信息"
    echo
    echo -e "${YELLOW}快捷命令:${NC}"
    echo -e "  ${BLUE}portadd${NC} <端口号>  ${PLUS} 直接添加端口（等效于port add）"
    echo
    echo -e "${YELLOW}示例:${NC}"
    echo -e "  ${CYAN}port add 22${NC}       ${PLUS} 添加22端口转发（自动适配 WSL1/WSL2）"
    echo -e "  ${CYAN}port delete 8080${NC}  ${MINUS} 删除8080端口转发"
    echo -e "  ${CYAN}port list${NC}         ${LIST} 查看端口列表及 WSL 版本"
    echo -e "${GREEN}=============================================${NC}"
}

# 命令解析
define_aliases

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