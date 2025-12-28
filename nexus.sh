#!/bin/bash

# 柔和色彩设置
GREEN='\033[1;32m'
BLUE='\033[1;36m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 日志文件设置
LOG_DIR="$HOME/.nexus/logs"
CONFIG_PATH="$HOME/.nexus/config.json"

# ============================================================================
#                           许可证验证模块
# ============================================================================

# 配置项
LICENSE_SERVER_URL="license-api.hzy1257664828.workers.dev"
LICENSE_FILE="$HOME/.gensyn_license"
LICENSE_CACHE_FILE="$HOME/.gensyn_license_cache"
CACHE_VALID_HOURS=24

# 获取机器指纹
get_machine_fingerprint() {
    local fingerprint=""
    if [[ "$(uname -s)" == "Darwin" ]]; then
        # macOS: 使用硬件UUID
        fingerprint=$(ioreg -rd1 -c IOPlatformExpertDevice | awk '/IOPlatformUUID/ { print $3 }' | tr -d '"')
    else
        # Linux: 使用machine-id + 首个MAC地址
        local machine_id=""
        local mac_addr=""
        if [[ -f /etc/machine-id ]]; then
            machine_id=$(cat /etc/machine-id)
        elif [[ -f /var/lib/dbus/machine-id ]]; then
            machine_id=$(cat /var/lib/dbus/machine-id)
        fi
        mac_addr=$(ip link show 2>/dev/null | awk '/ether/ {print $2; exit}' | tr -d ':')
        fingerprint="${machine_id}-${mac_addr}"
    fi
    # 生成SHA256哈希作为最终指纹
    echo -n "$fingerprint" | shasum -a 256 | awk '{print $1}'
}

# 检查缓存是否有效
check_license_cache() {
    if [[ ! -f "$LICENSE_CACHE_FILE" ]]; then
        return 1
    fi

    local cache_time=$(cat "$LICENSE_CACHE_FILE" 2>/dev/null | head -1)
    local cache_fingerprint=$(cat "$LICENSE_CACHE_FILE" 2>/dev/null | tail -1)
    local current_time=$(date +%s)
    local current_fingerprint=$(get_machine_fingerprint)

    # 检查指纹是否匹配
    if [[ "$cache_fingerprint" != "$current_fingerprint" ]]; then
        return 1
    fi

    # 检查缓存是否过期
    local cache_age=$(( (current_time - cache_time) / 3600 ))
    if [[ $cache_age -lt $CACHE_VALID_HOURS ]]; then
        return 0
    fi
    return 1
}

# 保存验证缓存
save_license_cache() {
    local current_time=$(date +%s)
    local fingerprint=$(get_machine_fingerprint)
    echo -e "${current_time}\n${fingerprint}" > "$LICENSE_CACHE_FILE"
    chmod 600 "$LICENSE_CACHE_FILE"
}

# 在线验证许可证
verify_license_online() {
    local license_key="$1"
    local fingerprint=$(get_machine_fingerprint)

    # 调用验证服务器
    local response=$(curl -s -X POST "$LICENSE_SERVER_URL" \
        -H "Content-Type: application/json" \
        -d "{\"license_key\": \"$license_key\", \"fingerprint\": \"$fingerprint\"}" \
        --connect-timeout 10 \
        --max-time 30 2>/dev/null)

    if [[ -z "$response" ]]; then
        return 2  # 网络错误
    fi

    # 解析响应 (假设返回 {"valid": true/false, "message": "..."})
    if echo "$response" | grep -q '"valid":\s*true'; then
        return 0  # 验证成功
    else
        return 1  # 验证失败
    fi
}

# 离线验证许可证 (简单的本地验证)
verify_license_offline() {
    local license_key="$1"
    local fingerprint=$(get_machine_fingerprint)

    # 许可证格式: GENSYN-XXXX-XXXX-XXXX-指纹前8位
    local expected_suffix="${fingerprint:0:8}"

    if [[ "$license_key" =~ ^GENSYN-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-${expected_suffix}$ ]]; then
        return 0
    fi
    return 1
}

# 主验证函数
verify_license() {
    echo ""
    echo -e "${YELLOW}╔════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║       🔐 土豆科技 - 许可证验证系统 🔐       ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "🔄 正在验证许可证..."

    # 检查缓存
    if check_license_cache; then
        echo -e "${GREEN}🌿 许可证验证通过 (缓存有效)${NC}"
        echo -e "${GREEN}🎉 欢迎使用！祝您使用愉快！${NC}"
        echo ""
        return 0
    fi

    # 读取许可证密钥
    local license_key=""
    if [[ -f "$LICENSE_FILE" ]]; then
        license_key=$(cat "$LICENSE_FILE" | tr -d '\n\r ')
    fi

    if [[ -z "$license_key" ]]; then
        echo ""
        echo -e "${RED}╔════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║           ❌ 未找到许可证文件！             ║${NC}"
        echo -e "${RED}╚════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "📂 请将许可证密钥保存到: ${YELLOW}$LICENSE_FILE${NC}"
        echo ""
        echo -e "💬 获取许可证请添加微信: ${GREEN}tudou_eth${NC}"
        echo ""
        echo -e "🖥️  机器指纹: ${YELLOW}$(get_machine_fingerprint)${NC}"
        echo -e "📋 (请将此指纹发送给微信 tudou_eth 以获取绑定许可证)"
        echo ""
        exit 1
    fi

    echo -e "🔍 检测到许可证，正在验证..."
    echo -e "🌐 连接验证服务器..."

    # 尝试在线验证
    verify_license_online "$license_key"
    local online_result=$?

    if [[ $online_result -eq 0 ]]; then
        echo ""
        echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║         🌿 许可证在线验证通过！            ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
        echo -e "${GREEN}🎉 欢迎使用！祝您使用愉快！${NC}"
        echo ""
        save_license_cache
        return 0
    elif [[ $online_result -eq 2 ]]; then
        # 网络错误，尝试离线验证
        echo -e "${YELLOW}⚠️  无法连接验证服务器${NC}"
        echo -e "🔌 尝试离线验证模式..."
        if verify_license_offline "$license_key"; then
            echo ""
            echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
            echo -e "${GREEN}║         🌿 许可证离线验证通过！            ║${NC}"
            echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
            echo -e "${GREEN}🎉 欢迎使用！祝您使用愉快！${NC}"
            echo ""
            save_license_cache
            return 0
        fi
    fi

    # 验证失败
    echo ""
    echo -e "${RED}╔════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║           ❌ 许可证验证失败！               ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "🚫 可能的原因："
    echo -e "   ${RED}1.${NC} 📛 许可证密钥无效或已过期"
    echo -e "   ${RED}2.${NC} 🔒 许可证未绑定到此设备"
    echo -e "   ${RED}3.${NC} 🚷 许可证已被撤销"
    echo ""
    echo -e "🖥️  当前机器指纹: ${YELLOW}$(get_machine_fingerprint)${NC}"
    echo -e "💬 获取许可证请添加微信: ${GREEN}tudou_eth${NC}"
    echo ""
    exit 1
}

# ============================================================================

# 检测操作系统
OS=$(uname -s)
case "$OS" in
  Darwin) OS_TYPE="macOS" ;;
  Linux)
    if [[ -f /etc/os-release ]]; then
      . /etc/os-release
      [[ "$ID" == "ubuntu" ]] && OS_TYPE="Ubuntu" || OS_TYPE="Linux"
    else
      OS_TYPE="Linux"
    fi
    ;;
  *) echo -e "${RED}不支持的操作系统: $OS${NC}" ; exit 1 ;;
esac

# 检测 shell
if [[ -n "$ZSH_VERSION" ]]; then
  SHELL_TYPE="zsh"
  CONFIG_FILE="$HOME/.zshrc"
elif [[ -n "$BASH_VERSION" ]]; then
  SHELL_TYPE="bash"
  CONFIG_FILE="$HOME/.bashrc"
else
  echo -e "${RED}不支持的 shell${NC}"
  exit 1
fi

# 创建日志目录
mkdir -p "$LOG_DIR"

# 打印标题
print_header() {
  echo -e "${BLUE}=====================================${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}=====================================${NC}"
}

# 日志函数
log() {
  echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# 检查命令是否存在
check_command() {
  command -v "$1" &> /dev/null
}

# 配置 shell 环境变量
configure_shell() {
  local env_path="$1"
  local env_var="export PATH=$env_path:\$PATH"
  if [[ -f "$CONFIG_FILE" ]] && grep -Fx "$env_var" "$CONFIG_FILE" > /dev/null; then
    return
  fi
  echo "$env_var" >> "$CONFIG_FILE"
  source "$CONFIG_FILE" 2>/dev/null
}

# ============ 依赖安装 ============

install_dependencies() {
  if [[ "$OS_TYPE" == "Ubuntu" ]]; then
    print_header "安装基础依赖"
    sudo apt-get update -y
    sudo apt-get install -y curl jq screen build-essential || exit 1
  fi
}

install_homebrew() {
  if check_command brew; then return; fi
  print_header "安装 Homebrew"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || exit 1
  [[ "$OS_TYPE" == "macOS" ]] && configure_shell "/opt/homebrew/bin"
}

install_cmake() {
  if check_command cmake; then return; fi
  print_header "安装 CMake"
  [[ "$OS_TYPE" == "Ubuntu" ]] && sudo apt-get install -y cmake || brew install cmake
}

install_protobuf() {
  if check_command protoc; then return; fi
  print_header "安装 Protobuf"
  [[ "$OS_TYPE" == "Ubuntu" ]] && sudo apt-get install -y protobuf-compiler || brew install protobuf
}

install_rust() {
  if check_command rustc; then return; fi
  print_header "安装 Rust"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y || exit 1
  source "$HOME/.cargo/env" 2>/dev/null
  configure_shell "$HOME/.cargo/bin"
}

configure_rust_target() {
  if rustup target list --installed | grep -q "riscv32i-unknown-none-elf"; then return; fi
  print_header "配置 Rust RISC-V 目标"
  rustup target add riscv32i-unknown-none-elf || exit 1
}

install_nexus_cli() {
  print_header "安装/更新 Nexus CLI"
  local attempt=1
  while [[ $attempt -le 3 ]]; do
    log "${BLUE}尝试安装 (第 $attempt 次)...${NC}"
    # 不隐藏输出，允许用户交互
    if curl -sSf https://cli.nexus.xyz/ | sh; then
      log "${GREEN}Nexus CLI 安装成功！${NC}"
      break
    fi
    log "${YELLOW}安装失败，2秒后重试...${NC}"
    ((attempt++))
    sleep 2
  done

  source "$CONFIG_FILE" 2>/dev/null
  [[ -f "$HOME/.zshrc" ]] && source "$HOME/.zshrc" 2>/dev/null
  sleep 2
}

# ============ ID 池管理 ============

setup_node_ids() {
  print_header "配置 Node ID 池"
  
  # 检查是否已有配置
  if [[ -f "$CONFIG_PATH" ]] && jq -e '.node_ids' "$CONFIG_PATH" &>/dev/null; then
    local pool_size=$(jq '.node_ids | length' "$CONFIG_PATH")
    echo -e "${GREEN}检测到已有 $pool_size 个 Node ID：${NC}"
    jq -r '.node_ids | to_entries | .[] | "  [\(.key + 1)] \(.value)"' "$CONFIG_PATH"
    
    echo -e "${BLUE}是否重新配置? (y/n, 默认 n, 5秒后自动继续): ${NC}"
    read -t 5 -r reconfigure
    [[ ! "$reconfigure" =~ ^[Yy]$ ]] && return
  fi
  
  echo -e "${BLUE}════════════════════════════════════════${NC}"
  echo -e "${YELLOW}请输入多个 Node ID（逗号或空格分隔）：${NC}"
  echo -e "${GREEN}示例: id1,id2,id3,id4,id5${NC}"
  echo -e "${BLUE}════════════════════════════════════════${NC}"
  
  local node_ids=()
  
  while true; do
    read -r input_line
    
    if [[ -z "$input_line" && ${#node_ids[@]} -ge 1 ]]; then
      break
    fi
    
    [[ -z "$input_line" ]] && { echo -e "${RED}请至少输入 1 个 ID${NC}"; continue; }
    
    # 逗号替换为空格，分割
    input_line="${input_line//,/ }"
    
    for new_id in $input_line; do
      new_id=$(echo "$new_id" | xargs)
      [[ -z "$new_id" ]] && continue
      
      if [[ ! "$new_id" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo -e "${RED}跳过无效 ID: $new_id${NC}"
        continue
      fi
      
      # 检查重复
      local dup=false
      for id in "${node_ids[@]}"; do
        [[ "$id" == "$new_id" ]] && dup=true && break
      done
      
      if [[ "$dup" == false ]]; then
        node_ids+=("$new_id")
        echo -e "${GREEN}✓ 已添加: $new_id${NC}"
      fi
    done
    
    echo -e "${BLUE}已添加 ${#node_ids[@]} 个 ID，按回车确认或继续添加：${NC}"
  done
  
  # 保存配置
  mkdir -p "$HOME/.nexus"
  local ids_json=$(printf '%s\n' "${node_ids[@]}" | jq -R . | jq -s .)
  jq -n --argjson ids "$ids_json" '{node_ids: $ids}' > "$CONFIG_PATH"
  
  echo -e "${GREEN}════════════════════════════════════════${NC}"
  echo -e "${GREEN}已保存 ${#node_ids[@]} 个 Node ID${NC}"
  echo -e "${GREEN}════════════════════════════════════════${NC}"
}

# 获取所有 Node ID
get_all_node_ids() {
  if [[ ! -f "$CONFIG_PATH" ]]; then
    echo -e "${RED}配置文件不存在${NC}"
    exit 1
  fi
  mapfile -t NODE_IDS < <(jq -r '.node_ids[]' "$CONFIG_PATH")
}

# ============ 进程管理 ============

# 停止所有节点
stop_all_nodes() {
  log "${YELLOW}正在停止所有 Nexus 节点...${NC}"
  
  # 停止所有 screen 会话
  for session in $(screen -ls | grep -o 'nexus_[0-9]*' | sort -u); do
    log "${BLUE}停止 $session...${NC}"
    screen -S "$session" -X quit 2>/dev/null
  done
  
  # 终止所有进程
  local pids=$(pgrep -f "nexus-network\|nexus-cli" | tr '\n' ' ')
  if [[ -n "$pids" ]]; then
    for pid in $pids; do
      kill -9 "$pid" 2>/dev/null
    done
  fi
  
  # macOS: 关闭终端窗口
  if [[ "$OS_TYPE" == "macOS" ]]; then
    osascript -e 'tell application "Terminal" to close (every window whose name contains "nexus-")' 2>/dev/null || true
  fi
  
  sleep 2
  log "${GREEN}所有节点已停止${NC}"
}

# 启动单个节点
start_single_node() {
  local node_id="$1"
  local index="$2"
  local log_file="$LOG_DIR/node_${index}.log"
  
  log "${BLUE}启动节点 [$index]: $node_id${NC}"
  
  if [[ "$OS_TYPE" == "macOS" ]]; then
    # macOS: 使用新终端窗口
    local screen_width=1920
    local screen_height=1080
    
    # 尝试获取屏幕尺寸
    local screen_info=$(system_profiler SPDisplaysDataType 2>/dev/null | grep Resolution | head -1 | awk '{print $2, $4}' | tr 'x' ' ')
    if [[ -n "$screen_info" ]]; then
      read -r screen_width screen_height <<< "$screen_info"
    fi
    
    # 计算窗口位置（网格布局）
    local cols=3  # 每行3个窗口
    local win_width=$((screen_width / cols - 20))
    local win_height=300
    local row=$(((index - 1) / cols))
    local col=$(((index - 1) % cols))
    local x=$((col * (win_width + 10) + 10))
    local y=$((row * (win_height + 30) + 50))
    
    osascript <<EOF
tell application "Terminal"
  set newWindow to do script "echo '🚀 节点 $index: $node_id' && nexus-network start --node-id $node_id 2>&1 | tee '$log_file'"
  tell front window
    set custom title to "nexus-$index"
    set bounds to {$x, $y, $((x + win_width)), $((y + win_height))}
  end tell
end tell
EOF
  else
    # Linux: 使用 screen
    screen -dmS "nexus_$index" bash -c "nexus-network start --node-id '$node_id' 2>&1 | tee '$log_file'"
    
    # 如果 nexus-network 失败，尝试 nexus-cli
    sleep 2
    if ! screen -ls | grep -q "nexus_$index"; then
      screen -dmS "nexus_$index" bash -c "nexus-cli start --node-id '$node_id' 2>&1 | tee '$log_file'"
    fi
  fi
}

# 启动所有节点
start_all_nodes() {
  log "${BLUE}正在启动所有节点...${NC}"
  
  get_all_node_ids
  local total=${#NODE_IDS[@]}
  
  echo -e "${GREEN}════════════════════════════════════════${NC}"
  echo -e "${GREEN}即将启动 $total 个节点${NC}"
  echo -e "${GREEN}════════════════════════════════════════${NC}"
  
  local index=1
  for node_id in "${NODE_IDS[@]}"; do
    start_single_node "$node_id" "$index"
    ((index++))
    sleep 2  # 间隔启动，避免冲突
  done
  
  echo -e "${GREEN}════════════════════════════════════════${NC}"
  log "${GREEN}已启动 $total 个节点${NC}"
  echo -e "${GREEN}════════════════════════════════════════${NC}"
}

# 显示节点状态
show_status() {
  print_header "节点运行状态"
  
  get_all_node_ids
  local total=${#NODE_IDS[@]}
  local running=0
  
  echo -e "${BLUE}配置的节点数: $total${NC}"
  echo ""
  
  local index=1
  for node_id in "${NODE_IDS[@]}"; do
    local status="${RED}未运行${NC}"
    local pid=""
    
    if [[ "$OS_TYPE" == "macOS" ]]; then
      pid=$(pgrep -f "nexus.*--node-id.*$node_id" | head -1)
    else
      if screen -ls | grep -q "nexus_$index"; then
        status="${GREEN}运行中${NC}"
        ((running++))
      fi
    fi
    
    if [[ -n "$pid" ]]; then
      status="${GREEN}运行中 (PID: $pid)${NC}"
      ((running++))
    fi
    
    echo -e "  [$index] $node_id: $status"
    ((index++))
  done
  
  echo ""
  echo -e "${BLUE}运行中: $running / $total${NC}"
  
  # 显示日志文件位置
  echo ""
  echo -e "${BLUE}日志目录: $LOG_DIR${NC}"
}

# 查看节点日志
view_logs() {
  print_header "节点日志"
  
  get_all_node_ids
  
  echo -e "${BLUE}选择要查看的节点:${NC}"
  local index=1
  for node_id in "${NODE_IDS[@]}"; do
    echo "  [$index] $node_id"
    ((index++))
  done
  echo "  [0] 返回"
  
  read -rp "请输入编号: " choice
  
  if [[ "$choice" == "0" || -z "$choice" ]]; then
    return
  fi
  
  local log_file="$LOG_DIR/node_${choice}.log"
  if [[ -f "$log_file" ]]; then
    echo -e "${BLUE}显示最后 50 行日志 ($log_file):${NC}"
    tail -50 "$log_file"
  else
    echo -e "${YELLOW}日志文件不存在${NC}"
  fi
}

# 清理退出
cleanup_exit() {
  log "${YELLOW}收到退出信号...${NC}"
  stop_all_nodes
  exit 0
}

trap 'cleanup_exit' SIGINT SIGTERM SIGHUP

# ============ 主菜单 ============

show_menu() {
  echo ""
  echo -e "${BLUE}════════════════════════════════════════${NC}"
  echo -e "${BLUE}    Nexus 多节点管理器${NC}"
  echo -e "${BLUE}════════════════════════════════════════${NC}"
  echo -e "  ${GREEN}1${NC}) 启动所有节点"
  echo -e "  ${GREEN}2${NC}) 停止所有节点"
  echo -e "  ${GREEN}3${NC}) 重启所有节点"
  echo -e "  ${GREEN}4${NC}) 查看节点状态"
  echo -e "  ${GREEN}5${NC}) 查看节点日志"
  echo -e "  ${GREEN}6${NC}) 重新配置 ID 池"
  echo -e "  ${GREEN}7${NC}) 后台持续运行（自动更新）"
  echo -e "  ${GREEN}0${NC}) 退出"
  echo -e "${BLUE}════════════════════════════════════════${NC}"
}

# 后台监控模式
daemon_mode() {
  log "${BLUE}进入后台监控模式...${NC}"
  log "${BLUE}每 30 分钟检查 GitHub 更新${NC}"
  log "${BLUE}按 Ctrl+C 退出${NC}"
  
  # 首次启动
  start_all_nodes
  
  while true; do
    sleep 1800  # 30 分钟
    
    # 检查更新
    local repo_url="https://github.com/nexus-xyz/nexus-cli.git"
    local current_commit=$(git ls-remote --heads "$repo_url" main 2>/dev/null | cut -f1)
    
    if [[ -f "$HOME/.nexus/last_commit" ]]; then
      local last_commit=$(cat "$HOME/.nexus/last_commit")
      if [[ "$current_commit" != "$last_commit" && -n "$current_commit" ]]; then
        log "${GREEN}检测到更新，重启所有节点...${NC}"
        echo "$current_commit" > "$HOME/.nexus/last_commit"
        install_nexus_cli
        stop_all_nodes
        start_all_nodes
      else
        log "${BLUE}无更新，节点继续运行...${NC}"
      fi
    else
      [[ -n "$current_commit" ]] && echo "$current_commit" > "$HOME/.nexus/last_commit"
    fi
  done
}

# ============ 主函数 ============

main() {
  # 首先验证许可证
  verify_license

  print_header "Nexus 多节点管理器"

  # 安装依赖
  [[ "$OS_TYPE" == "Ubuntu" ]] && install_dependencies
  [[ "$OS_TYPE" == "macOS" || "$OS_TYPE" == "Linux" ]] && install_homebrew
  install_cmake
  install_protobuf
  install_rust
  configure_rust_target
  install_nexus_cli
  
  # 配置 ID
  setup_node_ids
  
  # 主循环
  while true; do
    show_menu
    read -rp "请选择操作: " choice
    
    case "$choice" in
      1) start_all_nodes ;;
      2) stop_all_nodes ;;
      3) stop_all_nodes; sleep 2; start_all_nodes ;;
      4) show_status ;;
      5) view_logs ;;
      6) setup_node_ids ;;
      7) daemon_mode ;;
      0) stop_all_nodes; exit 0 ;;
      *) echo -e "${RED}无效选项${NC}" ;;
    esac
  done
}

main