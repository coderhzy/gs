#!/bin/bash
#
# Infernet Hello-World 一键部署工具 - 土豆科技
#

set -e

# ============================================================================
#                              颜色与样式定义
# ============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# 日志文件
log_file="$HOME/infernet-deployment.log"

# ============================================================================
#                              美化输出函数
# ============================================================================
print_banner() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}     ${BOLD}${PURPLE}🚀 Infernet Hello-World 一键部署工具 🚀${NC}              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                  ${GREEN}土豆科技出品${NC}                              ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    local step=$1
    local total=$2
    local msg=$3
    echo ""
    echo -e "${BLUE}┌─────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│${NC} ${BOLD}[${step}/${total}]${NC} ${YELLOW}${msg}${NC}"
    echo -e "${BLUE}└─────────────────────────────────────────────────────────────┘${NC}"
}

info() {
    echo -e "${GREEN}  ✓${NC} $1" | tee -a "$log_file"
}

warn() {
    echo -e "${YELLOW}  ⚠${NC} $1" | tee -a "$log_file"
}

error() {
    echo -e "${RED}  ✗ 错误：${NC}$1" | tee -a "$log_file"
    exit 1
}

progress() {
    echo -e "${CYAN}  →${NC} $1" | tee -a "$log_file"
}

print_menu() {
    echo ""
    echo -e "${PURPLE}┌─────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${PURPLE}│${NC}              ${BOLD}请选择部署模式${NC}                               ${PURPLE}│${NC}"
    echo -e "${PURPLE}├─────────────────────────────────────────────────────────────┤${NC}"
    echo -e "${PURPLE}│${NC}  ${GREEN}1)${NC} 全新部署 (清除并重装)                                 ${PURPLE}│${NC}"
    echo -e "${PURPLE}│${NC}  ${GREEN}2)${NC} 继续现有环境                                         ${PURPLE}│${NC}"
    echo -e "${PURPLE}│${NC}  ${GREEN}3)${NC} 直接部署合约                                         ${PURPLE}│${NC}"
    echo -e "${PURPLE}│${NC}  ${GREEN}4)${NC} 更新配置并重启容器                                   ${PURPLE}│${NC}"
    echo -e "${PURPLE}│${NC}  ${GREEN}0)${NC} 退出                                                 ${PURPLE}│${NC}"
    echo -e "${PURPLE}└─────────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

print_success() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}                    ${BOLD}✅ 部署完成！${NC}                            ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ============================================================================
#                           许可证验证模块
# ============================================================================
LICENSE_SERVER_URL="license-api.hzy1257664828.workers.dev"
LICENSE_FILE="$HOME/.gensyn_license"
LICENSE_CACHE_FILE="$HOME/.gensyn_license_cache"
CACHE_VALID_HOURS=24

get_machine_fingerprint() {
    local fingerprint=""
    if [[ "$(uname -s)" == "Darwin" ]]; then
        fingerprint=$(ioreg -rd1 -c IOPlatformExpertDevice | awk '/IOPlatformUUID/ { print $3 }' | tr -d '"')
    else
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
    echo -n "$fingerprint" | shasum -a 256 | awk '{print $1}'
}

check_license_cache() {
    if [[ ! -f "$LICENSE_CACHE_FILE" ]]; then
        return 1
    fi
    local cache_time=$(cat "$LICENSE_CACHE_FILE" 2>/dev/null | head -1)
    local cache_fingerprint=$(cat "$LICENSE_CACHE_FILE" 2>/dev/null | tail -1)
    local current_time=$(date +%s)
    local current_fingerprint=$(get_machine_fingerprint)
    if [[ "$cache_fingerprint" != "$current_fingerprint" ]]; then
        return 1
    fi
    local cache_age=$(( (current_time - cache_time) / 3600 ))
    if [[ $cache_age -lt $CACHE_VALID_HOURS ]]; then
        return 0
    fi
    return 1
}

save_license_cache() {
    local current_time=$(date +%s)
    local fingerprint=$(get_machine_fingerprint)
    echo -e "${current_time}\n${fingerprint}" > "$LICENSE_CACHE_FILE"
    chmod 600 "$LICENSE_CACHE_FILE"
}

verify_license_online() {
    local license_key="$1"
    local fingerprint=$(get_machine_fingerprint)
    local response=$(curl -s -X POST "$LICENSE_SERVER_URL" \
        -H "Content-Type: application/json" \
        -d "{\"license_key\": \"$license_key\", \"fingerprint\": \"$fingerprint\"}" \
        --connect-timeout 10 \
        --max-time 30 2>/dev/null)
    if [[ -z "$response" ]]; then
        return 2
    fi
    if echo "$response" | grep -q '"valid":\s*true'; then
        return 0
    else
        return 1
    fi
}

verify_license_offline() {
    local license_key="$1"
    local fingerprint=$(get_machine_fingerprint)
    local expected_suffix="${fingerprint:0:8}"
    if [[ "$license_key" =~ ^GENSYN-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-${expected_suffix}$ ]]; then
        return 0
    fi
    return 1
}

verify_license() {
    echo ""
    echo -e "${YELLOW}╔════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║       🔐 土豆科技 - 许可证验证系统 🔐       ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════╝${NC}"
    echo ""
    progress "正在验证许可证..."

    if check_license_cache; then
        info "许可证验证通过 (缓存有效)"
        echo -e "${GREEN}  🎉 欢迎使用！${NC}"
        echo ""
        return 0
    fi

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
        echo -e "  📂 请将许可证密钥保存到: ${YELLOW}$LICENSE_FILE${NC}"
        echo ""
        echo -e "  💬 获取许可证请添加微信: ${GREEN}tudou_eth${NC}"
        echo ""
        echo -e "  🖥️  机器指纹: ${YELLOW}$(get_machine_fingerprint)${NC}"
        echo ""
        exit 1
    fi

    progress "检测到许可证，正在验证..."
    progress "连接验证服务器..."

    verify_license_online "$license_key"
    local online_result=$?

    if [[ $online_result -eq 0 ]]; then
        echo ""
        echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║         ✅ 许可证验证通过！                ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
        echo ""
        save_license_cache
        return 0
    elif [[ $online_result -eq 2 ]]; then
        warn "无法连接验证服务器"
        progress "尝试离线验证模式..."
        if verify_license_offline "$license_key"; then
            echo ""
            echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
            echo -e "${GREEN}║         ✅ 许可证离线验证通过！            ║${NC}"
            echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
            echo ""
            save_license_cache
            return 0
        fi
    fi

    echo ""
    echo -e "${RED}╔════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║           ❌ 许可证验证失败！               ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  🖥️  当前机器指纹: ${YELLOW}$(get_machine_fingerprint)${NC}"
    echo -e "  💬 获取许可证请添加微信: ${GREEN}tudou_eth${NC}"
    echo ""
    exit 1
}

# ============================================================================
#                           配置管理
# ============================================================================
config_file="$HOME/.infernet_config"

load_or_prompt_config() {
    if [ -f "$config_file" ]; then
        info "检测到已保存的配置：$config_file"
        source "$config_file"
        info "当前 RPC_URL: $RPC_URL"
        info "当前 PRIVATE_KEY: ${PRIVATE_KEY:0:6}...（已隐藏）"
        echo ""
        read -p "  是否更新 RPC_URL 和 PRIVATE_KEY？(y/n): " update_config
        if [[ "$update_config" != "y" && "$update_config" != "Y" ]]; then
            return
        fi
    fi

    echo ""
    echo -e "${CYAN}  请输入以下信息以继续部署：${NC}"
    echo ""
    read -p "  RPC URL (Alchemy/Infura): " RPC_URL
    read -p "  私钥 (0x开头): " PRIVATE_KEY

    if [[ -z "$RPC_URL" || -z "$PRIVATE_KEY" ]]; then
        error "RPC URL 和私钥不能为空"
    fi
    if [[ ! "$RPC_URL" =~ ^https?://[a-zA-Z0-9.-]+ ]]; then
        error "无效的 RPC URL 格式"
    fi
    if [[ ! "$PRIVATE_KEY" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
        error "无效的私钥格式（必须是 0x 开头的 64 位十六进制）"
    fi

    cat <<EOF > "$config_file"
RPC_URL="$RPC_URL"
PRIVATE_KEY="$PRIVATE_KEY"
EOF
    chmod 600 "$config_file"
    info "配置已保存至 $config_file"
}

# ============================================================================
#                           依赖安装函数
# ============================================================================
install_with_retry() {
    local name=$1
    local cmd=$2
    local max_attempts=3
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        progress "安装 $name (第 $attempt 次)..."
        if eval "$cmd"; then
            info "$name 安装成功"
            return 0
        fi
        warn "$name 安装失败，重试中..."
        sleep 5
        ((attempt++))
    done
    error "$name 安装失败，请手动安装"
}

check_and_install_deps() {
    print_step "1" "20" "检查系统依赖"

    # Homebrew
    if ! command -v brew &> /dev/null; then
        progress "安装 Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zshrc
        eval "$(/opt/homebrew/bin/brew shellenv)"
        info "Homebrew 安装成功"
    else
        info "Homebrew 已安装 ($(brew --version | head -n 1))"
    fi

    # 基础工具
    for pkg in curl git jq lz4 make; do
        if ! command -v $pkg &> /dev/null; then
            install_with_retry "$pkg" "brew install $pkg"
        else
            info "$pkg 已安装"
        fi
    done

    # coreutils
    if ! command -v gtimeout &> /dev/null && ! brew list | grep -q coreutils; then
        install_with_retry "coreutils" "brew install coreutils"
    else
        info "coreutils 已安装"
    fi
}

check_docker() {
    print_step "2" "20" "检查 Docker"

    if ! command -v docker &> /dev/null && [ ! -d "/Applications/Docker.app" ]; then
        progress "下载 Docker Desktop..."
        curl -L -o ~/Downloads/Docker.dmg "https://desktop.docker.com/mac/main/arm64/Docker.dmg"

        progress "挂载并安装..."
        hdiutil attach ~/Downloads/Docker.dmg -quiet
        cp -R "/Volumes/Docker/Docker.app" /Applications/
        hdiutil detach "/Volumes/Docker" -quiet
        rm -f ~/Downloads/Docker.dmg

        info "Docker Desktop 安装成功"
        echo ""
        echo -e "${YELLOW}  ⚠️  请手动打开 Docker Desktop: open -a Docker${NC}"
        echo -e "${YELLOW}  ⚠️  等待 Docker 启动完成后按 Enter 继续...${NC}"
        read -p ""
    elif [ -d "/Applications/Docker.app" ] && ! command -v docker &> /dev/null; then
        warn "Docker Desktop 已安装但未启动"
        echo -e "${YELLOW}  ⚠️  请打开 Docker Desktop: open -a Docker${NC}"
        echo -e "${YELLOW}  ⚠️  等待 Docker 启动完成后按 Enter 继续...${NC}"
        read -p ""
    else
        info "Docker 已安装 ($(docker --version))"
    fi

    # Docker Compose (Docker Desktop 自带，也可单独安装)
    if ! command -v docker-compose &> /dev/null; then
        progress "安装 Docker Compose..."
        brew install --formula docker-compose 2>/dev/null || true
        info "Docker Compose 已配置"
    else
        info "Docker Compose 已安装"
    fi
}

check_foundry() {
    print_step "3" "20" "检查 Foundry"

    if ! command -v forge &> /dev/null; then
        progress "安装 Foundry..."
        curl -L https://foundry.paradigm.xyz | bash
        echo 'export PATH="$HOME/.foundry/bin:$PATH"' >> ~/.zshrc
        source ~/.zshrc 2>/dev/null || true
        foundryup
        info "Foundry 安装成功"
    else
        info "Foundry 已安装 ($(forge --version 2>/dev/null | head -1))"
    fi
}

# ============================================================================
#                           端口检查
# ============================================================================
check_ports() {
    print_step "4" "20" "检查端口占用"

    for port in 4000 4001 6379 8545 5001; do
        if lsof -i :$port &> /dev/null; then
            progress "端口 $port 被占用，正在释放..."
            pids=$(lsof -t -i :$port)
            for pid in $pids; do
                kill -9 $pid 2>/dev/null && info "已终止进程 $pid"
            done
        else
            info "端口 $port 可用"
        fi
    done
}

# ============================================================================
#                           清理旧部署
# ============================================================================
cleanup_old_deployment() {
    print_step "5" "20" "清理旧部署"

    if [ -d "$HOME/infernet-container-starter" ]; then
        progress "停止现有容器..."
        cd "$HOME/infernet-container-starter"
        docker-compose -f deploy/docker-compose.yaml down -v 2>/dev/null || true
        cd "$HOME"
        progress "删除旧目录..."
        rm -rf infernet-container-starter
        info "清理完成"
    else
        info "无旧部署需要清理"
    fi
}

# ============================================================================
#                           克隆仓库
# ============================================================================
clone_repo() {
    print_step "6" "20" "下载项目文件"

    if [ ! -d "$HOME/infernet-container-starter" ]; then
        progress "下载 infernet-container-starter..."
        # 使用 curl 下载 zip 包，避免 git 认证问题
        curl -sL -o /tmp/infernet.zip "https://codeload.github.com/ScythianDeso6/infernet-container-starter/zip/refs/heads/main"
        progress "解压中..."
        unzip -q /tmp/infernet.zip -d /tmp/
        mv /tmp/infernet-container-starter-main "$HOME/infernet-container-starter"
        rm -f /tmp/infernet.zip
        info "下载成功"
    else
        info "使用现有目录"
    fi
    cd "$HOME/infernet-container-starter"
}

# ============================================================================
#                           拉取镜像
# ============================================================================
pull_images() {
    print_step "7" "20" "拉取 Docker 镜像"

    progress "拉取 hello-world-infernet 镜像..."
    docker pull ritualnetwork/hello-world-infernet:latest
    info "镜像拉取成功"
}

# ============================================================================
#                           写入配置
# ============================================================================
write_config() {
    print_step "8" "20" "写入配置文件"

    mkdir -p "$HOME/infernet-container-starter/deploy"

    cat <<EOF > "$HOME/infernet-container-starter/deploy/config.json"
{
  "log_path": "infernet_node.log",
  "server": {
    "port": 4001,
    "rate_limit": { "num_requests": 100, "period": 100 }
  },
  "chain": {
    "enabled": true,
    "trail_head_blocks": 3,
    "rpc_url": "$RPC_URL",
    "registry_address": "0x3B1554f346DFe5c482Bb4BA31b880c1C18412170",
    "wallet": {
      "max_gas_limit": 4000000,
      "private_key": "$PRIVATE_KEY",
      "allowed_sim_errors": []
    },
    "snapshot_sync": {
      "sleep": 3,
      "batch_size": 10,
      "starting_sub_id": 262500,
      "sync_period": 30,
      "retry_delay": 60
    }
  },
  "startup_wait": 1.0,
  "redis": { "host": "redis", "port": 6379 },
  "forward_stats": true,
  "containers": [{
    "id": "hello-world",
    "image": "ritualnetwork/hello-world-infernet:latest",
    "external": true,
    "port": "5001",
    "allowed_delegate_addresses": [],
    "allowed_addresses": [],
    "allowed_ips": [],
    "command": "--bind=0.0.0.0:5001 --workers=2",
    "env": {},
    "volumes": [],
    "accepted_payments": {},
    "generates_proofs": false
  }]
}
EOF

    cp "$HOME/infernet-container-starter/deploy/config.json" \
       "$HOME/infernet-container-starter/projects/hello-world/container/config.json" 2>/dev/null || true

    info "config.json 写入成功"
}

# ============================================================================
#                           写入 docker-compose
# ============================================================================
write_docker_compose() {
    print_step "9" "20" "写入 docker-compose.yaml"

    cat <<'EOF' > "$HOME/infernet-container-starter/deploy/docker-compose.yaml"
services:
  node:
    image: ritualnetwork/infernet-node:1.4.0
    ports: [ "0.0.0.0:4001:4000" ]
    volumes:
      - ./config.json:/app/config.json
      - node-logs:/logs
      - /var/run/docker.sock:/var/run/docker.sock
    tty: true
    networks: [ network ]
    depends_on: [ redis ]
    restart: on-failure
    extra_hosts: [ "host.docker.internal:host-gateway" ]
    stop_grace_period: 1m
    container_name: infernet-node
  redis:
    image: redis:7.4.0
    ports: [ "6379:6379" ]
    volumes:
      - ./redis.conf:/usr/local/etc/redis/redis.conf
      - redis-data:/data
    networks: [ network ]
    restart: on-failure
    container_name: infernet-redis
  fluentbit:
    image: fluent/fluent-bit:3.1.4
    expose: [ "24224" ]
    environment: [ "FLUENTBIT_CONFIG_PATH=/fluent-bit/etc/fluent-bit.conf" ]
    volumes:
      - ./fluent-bit.conf:/fluent-bit/etc/fluent-bit.conf
      - /var/log:/var/log:ro
    networks: [ network ]
    restart: on-failure
    container_name: infernet-fluentbit
networks:
  network:
volumes:
  node-logs:
  redis-data:
EOF

    info "docker-compose.yaml 写入成功"
}

# ============================================================================
#                           启动容器
# ============================================================================
start_containers() {
    print_step "10" "20" "启动 Docker 容器"

    cd "$HOME/infernet-container-starter/deploy"
    progress "启动容器..."
    docker-compose up -d
    info "容器启动成功"

    # 后台保存日志
    (docker logs -f infernet-node > "$HOME/infernet-deployment.log" 2>&1 &)
}

# ============================================================================
#                           安装 Forge 库
# ============================================================================
install_forge_libs() {
    print_step "11" "20" "安装 Forge 库"

    cd "$HOME/infernet-container-starter/projects/hello-world/contracts"
    rm -rf lib/forge-std lib/infernet-sdk 2>/dev/null || true

    progress "安装 forge-std..."
    forge install foundry-rs/forge-std --no-commit
    info "forge-std 安装成功"

    progress "安装 infernet-sdk..."
    forge install ritual-net/infernet-sdk --no-commit
    info "infernet-sdk 安装成功"
}

# ============================================================================
#                           写入部署脚本
# ============================================================================
write_deploy_script() {
    print_step "12" "20" "写入部署脚本"

    cat <<'EOF' > "$HOME/infernet-container-starter/projects/hello-world/contracts/script/Deploy.s.sol"
// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.13;
import {Script, console2} from "forge-std/Script.sol";
import {SaysGM} from "../src/SaysGM.sol";

contract Deploy is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address deployerAddress = vm.addr(deployerPrivateKey);
        console2.log("Loaded deployer: ", deployerAddress);
        address registry = 0x3B1554f346DFe5c482Bb4BA31b880c1C18412170;
        SaysGM saysGm = new SaysGM(registry);
        console2.log("Deployed SaysGM: ", address(saysGm));
        vm.stopBroadcast();
    }
}
EOF

    info "Deploy.s.sol 写入成功"
}

# ============================================================================
#                           部署合约
# ============================================================================
deploy_contract() {
    print_step "13" "20" "部署智能合约"

    cd "$HOME/infernet-container-starter/projects/hello-world/contracts"

    warn "请确保私钥有足够余额支付 gas 费用"
    echo ""

    progress "部署合约中..."
    deploy_log=$(mktemp)

    if PRIVATE_KEY="$PRIVATE_KEY" forge script script/Deploy.s.sol:Deploy --broadcast --rpc-url "$RPC_URL" > "$deploy_log" 2>&1; then
        info "合约部署成功！"
        echo ""
        echo -e "${GREEN}  部署输出：${NC}"
        cat "$deploy_log" | grep -E "(Deployed|deployer|SaysGM)" | while read line; do
            echo -e "  ${CYAN}$line${NC}"
        done

        # 提取合约地址
        contract_address=$(grep -i "Deployed SaysGM" "$deploy_log" | awk '{print $NF}' | head -n 1)
        if [ -n "$contract_address" ] && [[ "$contract_address" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
            echo ""
            echo -e "${GREEN}  📝 合约地址: ${YELLOW}$contract_address${NC}"
            echo -e "${GREEN}  💾 请保存此地址用于后续调用！${NC}"
        fi
    else
        warn "合约部署失败，详情见日志"
        cat "$deploy_log"
    fi

    rm -f "$deploy_log"
}

# ============================================================================
#                           主程序
# ============================================================================
main() {
    # 验证许可证
    verify_license

    # 打印横幅
    print_banner

    # 显示菜单
    print_menu
    read -p "  请选择 (0-4): " choice

    case $choice in
        1)
            info "选择: 全新部署"
            full_deploy=true
            ;;
        2)
            info "选择: 继续现有环境"
            full_deploy=false
            ;;
        3)
            info "选择: 直接部署合约"
            load_or_prompt_config
            check_foundry
            install_forge_libs
            write_deploy_script
            deploy_contract
            print_success
            exit 0
            ;;
        4)
            info "选择: 更新配置并重启"
            load_or_prompt_config
            write_config
            cd "$HOME/infernet-container-starter/deploy"
            docker-compose down 2>/dev/null || true
            docker-compose up -d
            info "容器已重启"
            print_success
            exit 0
            ;;
        0)
            warn "已退出"
            exit 0
            ;;
        *)
            error "无效选择"
            ;;
    esac

    # 执行部署流程
    check_and_install_deps
    check_docker
    check_foundry
    check_ports
    load_or_prompt_config

    if [ "$full_deploy" = "true" ]; then
        cleanup_old_deployment
    fi

    clone_repo
    pull_images
    write_config
    write_docker_compose
    start_containers
    install_forge_libs
    write_deploy_script
    deploy_contract

    print_success

    echo -e "${CYAN}  📋 常用命令：${NC}"
    echo -e "     查看容器状态: ${YELLOW}docker ps${NC}"
    echo -e "     查看节点日志: ${YELLOW}docker logs infernet-node${NC}"
    echo -e "     停止容器:     ${YELLOW}cd ~/infernet-container-starter/deploy && docker-compose down${NC}"
    echo ""
}

# 运行主程序
main
