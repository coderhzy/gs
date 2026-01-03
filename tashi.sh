#!/usr/bin/env bash
# shellcheck disable=SC2155,SC2181
#
# Tashi DePIN Worker 一键部署工具 - 土豆科技
#

IMAGE_TAG='ghcr.io/tashigg/tashi-depin-worker:0'

RUST_LOG='info,tashi_depin_worker=debug,tashi_depin_common=debug'

AGENT_PORT=39065

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

CHECKMARK="${GREEN}✓${NC}"
CROSSMARK="${RED}✗${NC}"
WARNING="${YELLOW}⚠${NC}"

STYLE_BOLD=$(tput bold 2>/dev/null || echo "")
STYLE_NORMAL=$(tput sgr0 2>/dev/null || echo "")

WARNINGS=0
ERRORS=0

# ============================================================================
#                              美化输出函数
# ============================================================================
print_banner() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}       ${BOLD}${PURPLE}Tashi DePIN Worker 一键部署工具${NC}                   ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                    ${GREEN}土豆科技出品${NC}                            ${CYAN}║${NC}"
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

log() {
    local level="$1"
    local message="${2:-$(cat)}"
    printf "%b\n" "$message"
}

info() {
    echo -e "${GREEN}  ✓${NC} $1"
}

warn() {
    echo -e "${YELLOW}  ⚠${NC} $1"
}

error() {
    echo -e "${RED}  ✗ 错误：${NC}$1"
}

progress() {
    echo -e "${CYAN}  →${NC} $1"
}

make_bold() {
    local s="${1:-$(cat)}"
    printf "%s%s%s" "$STYLE_BOLD" "${s}" "$STYLE_NORMAL"
}

horizontal_line() {
    local WIDTH=${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}
    local FILL_CHAR='-'
    printf '\n%*s\n\n' "$WIDTH" '' | tr ' ' "$FILL_CHAR"
}

# ============================================================================
#                           许可证验证模块
# ============================================================================
LICENSE_SERVER_URL="https://license-api.hzy1257664828.workers.dev"
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
    echo -e "${YELLOW}║       土豆科技 - 许可证验证系统            ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════╝${NC}"
    echo ""
    progress "正在验证许可证..."

    if check_license_cache; then
        info "许可证验证通过 (缓存有效)"
        echo -e "${GREEN}  欢迎使用！${NC}"
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
        echo -e "${RED}║           未找到许可证文件！               ║${NC}"
        echo -e "${RED}╚════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "  请将许可证密钥保存到: ${YELLOW}$LICENSE_FILE${NC}"
        echo ""
        echo -e "  获取许可证请添加微信: ${GREEN}tudou_eth${NC}"
        echo ""
        echo -e "  机器指纹: ${YELLOW}$(get_machine_fingerprint)${NC}"
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
        echo -e "${GREEN}║         许可证验证通过！                   ║${NC}"
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
            echo -e "${GREEN}║         许可证离线验证通过！               ║${NC}"
            echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
            echo ""
            save_license_cache
            return 0
        fi
    fi

    echo ""
    echo -e "${RED}╔════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║           许可证验证失败！                 ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  当前机器指纹: ${YELLOW}$(get_machine_fingerprint)${NC}"
    echo -e "  获取许可证请添加微信: ${GREEN}tudou_eth${NC}"
    echo ""
    exit 1
}

# ============================================================================
#                              参数处理
# ============================================================================
POSITIONAL_ARGS=()
SUBCOMMAND=install

while [[ $# -gt 0 ]]; do
    case $1 in
        --ignore-warnings)
            IGNORE_WARNINGS=y
            ;;
        -y | --yes)
            YES=1
            ;;
        --auto-update)
            AUTO_UPDATE=y
            ;;
        --image-tag=*)
            IMAGE_TAG="${1#"--image-tag="}"
            ;;
        --install)
            SUBCOMMAND=install
            ;;
        --update)
            SUBCOMMAND=update
            ;;
        -*)
            echo "Unknown option $1"
            exit 1
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            ;;
    esac
    shift
done

set -- "${POSITIONAL_ARGS[@]}"

# ============================================================================
#                              系统检测函数
# ============================================================================
detect_os() {
    OS=$(
        # shellcheck disable=SC1091
        source /etc/os-release >/dev/null 2>&1
        echo "${ID:-unknown}"
    )
    if [[ "$OS" == "unknown" && "$(uname -s)" == "Darwin" ]]; then
        OS="macos"
    fi
}

suggest_install() {
    local package=$1
    case "$OS" in
        debian | ubuntu) echo "    sudo apt update && sudo apt install -y $package" ;;
        fedora) echo "    sudo dnf install -y $package" ;;
        arch) echo "    sudo pacman -S --noconfirm $package" ;;
        opensuse) echo "    sudo zypper install -y $package" ;;
        macos) echo "    brew install $package" ;;
        *) echo "    Please install '$package' manually for your OS." ;;
    esac
}

NPROC_CMD=$(command -v nproc || echo "")
GREP_CMD=$(command -v grep || echo "")
DF_CMD=$(command -v df || echo "")

check_command() {
    command -v "$1" >/dev/null 2>&1
}

# ============================================================================
#                              系统检查函数
# ============================================================================
check_platform() {
    PLATFORM_ARG=''
    local arch=$(uname -m)

    if [[ "$arch" == "amd64" || "$arch" == "x86_64" ]]; then
        info "平台检查: 支持的平台 $arch"
    elif [[ "$OS" == "macos" && "$arch" == arm64 ]]; then
        PLATFORM_ARG='--platform linux/amd64'
        warn "平台检查: 不支持的平台 $arch"
        log "INFO" "MacOS Apple Silicon 暂不原生支持，将通过 Rosetta 兼容层运行。"
        ((WARNINGS++))
    else
        error "平台检查: 不支持的平台 $arch"
        ((ERRORS++))
        return
    fi
}

check_cpu() {
    case "$OS" in
        "macos")
            threads=$(sysctl -n hw.ncpu)
            ;;
        *)
            if [[ -z "$NPROC_CMD" ]]; then
                warn "'nproc' 未找到。请安装 coreutils:"
                suggest_install "coreutils"
                ((ERRORS++))
                return
            fi
            threads=$("$NPROC_CMD")
            ;;
    esac

    if [[ "$threads" -ge 4 ]]; then
        info "CPU 检查: 发现 $threads 线程 (>= 4 推荐)"
    elif [[ "$threads" -ge 2 ]]; then
        warn "CPU 检查: 发现 $threads 线程 (>= 2 最低, 4 推荐)"
        ((WARNINGS++))
    else
        error "CPU 检查: 仅 $threads 线程 (最低需要 2)"
        ((ERRORS++))
    fi
}

check_memory() {
    if [[ -z "$GREP_CMD" ]]; then
        error "内存检查: 'grep' 未找到"
        suggest_install "grep"
        ((ERRORS++))
        return
    fi

    case "$OS" in
        "macos")
            total_mem_bytes=$(sysctl -n hw.memsize)
            total_mem_kb=$((total_mem_bytes / 1024))
            ;;
        *)
            total_mem_kb=$("$GREP_CMD" MemTotal /proc/meminfo | awk '{print $2}')
            ;;
    esac

    total_mem_gb=$((total_mem_kb / 1024 / 1024))

    if [[ "$total_mem_gb" -ge 4 ]]; then
        info "内存检查: 发现 ${total_mem_gb}GB RAM (>= 4GB 推荐)"
    elif [[ "$total_mem_gb" -ge 2 ]]; then
        warn "内存检查: 发现 ${total_mem_gb}GB RAM (>= 2GB 最低, 4GB 推荐)"
        ((WARNINGS++))
    else
        error "内存检查: 仅 ${total_mem_gb}GB RAM (最低需要 2GB)"
        ((ERRORS++))
    fi
}

check_disk() {
    case "$OS" in
        "macos")
            available_disk_kb=$(
                "$DF_CMD" -kcI 2>/dev/null |
                    tail -1 |
                    awk '{print $4}'
            )
            ;;
        *)
            available_disk_kb=$(
                "$DF_CMD" -kx tmpfs --total 2>/dev/null |
                    tail -1 |
                    awk '{print $4}'
            )
            ;;
    esac

    available_disk_gb=$((available_disk_kb / 1024 / 1024))

    if [[ "$available_disk_gb" -ge 20 ]]; then
        info "磁盘检查: 发现 ${available_disk_gb}GB 可用 (>= 20GB 需要)"
    else
        error "磁盘检查: 仅 ${available_disk_gb}GB 可用 (最低需要 20GB)"
        ((ERRORS++))
    fi
}

check_container_runtime() {
    detect_os

    if check_command "docker"; then
        info "容器运行时检查: Docker 已安装"
        CONTAINER_RT=docker

        if docker info >/dev/null 2>&1; then
            info "Docker 运行时检查: Docker 正在运行"
        else
            warn "Docker 运行时检查: Docker 已安装但未运行"

            if [[ "$OS" == "macos" ]]; then
                progress "尝试启动 Docker Desktop..."
                open -a Docker 2>/dev/null || {
                    warn "无法自动启动 Docker Desktop"
                    progress "请手动启动 Docker Desktop 并按 Enter 继续..."
                    read -r
                }

                progress "等待 Docker Desktop 启动..."
                local waited=0
                local max_wait=60
                while [ $waited -lt $max_wait ]; do
                    if docker info >/dev/null 2>&1; then
                        info "Docker 运行时检查: Docker 现在正在运行"
                        break
                    fi
                    sleep 2
                    waited=$((waited + 2))
                    echo -n "."
                done
                echo ""

                if ! docker info >/dev/null 2>&1; then
                    error "Docker 运行时检查: Docker 启动失败 (${max_wait} 秒后超时)"
                    progress "请确保 Docker Desktop 正在运行后重试"
                    ((ERRORS++))
                fi
            else
                if command -v systemctl >/dev/null 2>&1; then
                    progress "尝试启动 Docker 服务..."
                    if sudo systemctl start docker 2>/dev/null; then
                        sleep 3
                        if docker info >/dev/null 2>&1; then
                            info "Docker 运行时检查: Docker 现在正在运行"
                        else
                            error "Docker 运行时检查: Docker 服务启动失败"
                            ((ERRORS++))
                        fi
                    else
                        error "Docker 运行时检查: 无法启动 Docker 服务"
                        progress "请手动启动: sudo systemctl start docker"
                        ((ERRORS++))
                    fi
                else
                    error "Docker 运行时检查: Docker 未运行且无法自动启动"
                    ((ERRORS++))
                fi
            fi
        fi
    elif check_command "podman"; then
        info "容器运行时检查: Podman 已安装"
        CONTAINER_RT=podman
    else
        warn "容器运行时检查: Docker 和 Podman 均未安装"

        if [[ "$OS" == "macos" ]]; then
            if ! check_command "brew"; then
                progress "安装 Homebrew..."
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
                    error "Homebrew 安装失败"
                    ((ERRORS++))
                    return
                }
                if [[ -f "/opt/homebrew/bin/brew" ]]; then
                    eval "$(/opt/homebrew/bin/brew shellenv)"
                elif [[ -f "/usr/local/bin/brew" ]]; then
                    eval "$(/usr/local/bin/brew shellenv)"
                fi
            fi

            progress "安装 Docker Desktop..."
            if brew install --cask docker; then
                info "Docker Desktop 安装成功！"
                progress "请手动启动 Docker Desktop: open -a Docker"
                progress "等待 Docker Desktop 完全启动后按 Enter 继续..."
                read -r

                open -a Docker 2>/dev/null || true

                progress "等待 Docker Desktop 启动..."
                local waited=0
                local max_wait=60
                while [ $waited -lt $max_wait ]; do
                    if docker info >/dev/null 2>&1; then
                        info "Docker 运行时检查: Docker 现在正在运行"
                        CONTAINER_RT=docker
                        return
                    fi
                    sleep 2
                    waited=$((waited + 2))
                    echo -n "."
                done
                echo ""

                if docker info >/dev/null 2>&1; then
                    CONTAINER_RT=docker
                    return
                else
                    warn "Docker 已安装但未运行。请手动启动 Docker Desktop。"
                    ((ERRORS++))
                fi
            else
                error "Docker Desktop 安装失败"
                ((ERRORS++))
            fi
        else
            error "容器运行时检查: Docker 未安装"
            suggest_install "docker.io"
            ((ERRORS++))
        fi
    fi
}

check_internet() {
    if curl -s --head --connect-timeout 3 https://google.com | grep "HTTP" >/dev/null 2>&1; then
        info "网络连接: 设备可访问公网"
    elif wget --spider --timeout=3 --quiet https://google.com; then
        info "网络连接: 设备可访问公网"
    else
        error "网络连接: 未检测到网络访问！"
        ((ERRORS++))
    fi
}

get_local_ip() {
    if [[ "$OS" == "macos" ]]; then
        LOCAL_IP=$(ifconfig -l | xargs -n1 ipconfig getifaddr 2>/dev/null | head -1)
    elif check_command hostname; then
        LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    elif check_command ip; then
        LOCAL_IP=$(ip route get '1.0.0.0' | grep -Po "src \K(\S+)")
    fi
}

get_public_ip() {
    PUBLIC_IP=$(curl -s https://api.ipify.org || wget -qO- https://api.ipify.org)
}

check_nat() {
    local nat_message="如果此设备无法从公网访问，某些 DePIN 服务将被禁用，收益可能低于公网可访问节点。"

    get_local_ip
    get_public_ip

    if [[ -z "$LOCAL_IP" ]]; then
        warn "NAT 检查: 无法确定本地 IP"
        warn "$nat_message"
        return
    fi

    if [[ -z "$PUBLIC_IP" ]]; then
        warn "NAT 检查: 无法确定公网 IP"
        warn "$nat_message"
        return
    fi

    if [[ "$LOCAL_IP" == "$PUBLIC_IP" ]]; then
        info "NAT 检查: 开放 NAT / 公网可访问 (公网 IP: $PUBLIC_IP)"
        return
    fi

    warn "NAT 检查: 检测到 NAT (本地: $LOCAL_IP, 公网: $PUBLIC_IP)"
    warn "$nat_message"
}

check_root_required() {
    if [[ "$OS" == "macos" ]]; then
        SUDO_CMD=''
        info "权限检查: MacOS 不需要 root 权限"
        return
    fi

    if [[ "$CONTAINER_RT" == "docker" ]]; then
        if (groups "$USER" | grep docker >/dev/null); then
            info "权限检查: 用户在 'docker' 组中"
        elif [[ -w "$DOCKER_HOST" ]] || [[ -w "/var/run/docker.sock" ]]; then
            info "权限检查: 用户可访问 Docker daemon socket"
        else
            SUDO_CMD="sudo -g docker"
            warn "权限检查: 用户不在 'docker' 组中"
            warn "'docker run' 命令将使用 '${SUDO_CMD}' 执行"
            ((WARNINGS++))
        fi
    elif [[ "$CONTAINER_RT" == "podman" ]]; then
        if (grep "^$USER:" /etc/subuid >/dev/null) && (grep "^$(id -gn):" /etc/subgid >/dev/null); then
            info "权限检查: 用户可创建 Podman 容器无需 root"
        else
            SUDO_CMD="sudo"
            warn "权限检查: 用户无法创建 rootless Podman 容器"
            warn "'podman run' 命令将使用 '${SUDO_CMD}' 执行"
            ((WARNINGS++))
        fi
    fi
}

prompt_auto_updates() {
    progress "您的 DePIN worker 需要定期更新以保持最新功能和修复。"
    progress "过时的 worker 可能被排除在网络之外，无法完成任务或获得奖励。"
    echo ""
    info "自动更新已启用 (默认: 是)"
    AUTO_UPDATE=y
    echo ""
}

check_warnings() {
    if [[ "$ERRORS" -gt 0 ]]; then
        error "系统不满足最低要求。退出。"
        exit 1
    elif [[ "$WARNINGS" -eq 0 ]]; then
        info "系统要求已满足。"
        return
    fi

    warn "系统满足最低要求但不满足推荐要求。"

    if [[ "$IGNORE_WARNINGS" ]]; then
        info "'--ignore-warnings' 已传递。继续安装。"
        return
    fi

    info "继续安装 (默认: 是)"
}

prompt_continue() {
    info "准备 $SUBCOMMAND worker 节点。继续中..."
    echo ""
}

# ============================================================================
#                              容器配置
# ============================================================================
CONTAINER_NAME=tashi-depin-worker
AUTH_VOLUME=tashi-depin-worker-auth
AUTH_DIR="/home/worker/auth"

PULL_FLAG=$([[ "$IMAGE_TAG" == ghcr* ]] && echo "--pull=always")

make_setup_cmd() {
    local sudo="${1-$SUDO_CMD}"

    if [[ -z "$PUBLIC_IP" ]]; then
        get_public_ip
    fi

    cat <<-EOF
        ${sudo:+"$sudo "}${CONTAINER_RT} run --rm -it \\
            --mount type=volume,src=$AUTH_VOLUME,dst=$AUTH_DIR \\
            ${PUBLIC_IP:+-e PUBLIC_IP="$PUBLIC_IP"} \\
            $PULL_FLAG $PLATFORM_ARG $IMAGE_TAG \\
            interactive-setup $AUTH_DIR
EOF
}

make_run_cmd() {
    local sudo="${1-$SUDO_CMD}"
    local cmd="${2-"run -d"}"
    local name="${3-$CONTAINER_NAME}"
    local volumes_from="${4+"--volumes-from=$4"}"

    local auto_update_arg=''
    local restart_arg=''

    if [[ $AUTO_UPDATE == "y" ]]; then
        auto_update_arg="--unstable-update-download-path /tmp/tashi-depin-worker"
    fi

    if [[ "$CONTAINER_RT" == "docker" ]]; then
        restart_arg="--restart=unless-stopped"
    fi

    local health_check_args=''
    if [[ "$CONTAINER_RT" == "docker" ]] && [[ "$cmd" == "run -d" ]]; then
        health_check_args="--health-cmd='pgrep -f tashi-depin-worker || exit 1' --health-interval=30s --health-timeout=10s --health-retries=3"
    fi

    cat <<-EOF
        ${sudo:+"$sudo "}${CONTAINER_RT} $cmd -p "$AGENT_PORT:$AGENT_PORT" -p 127.0.0.1:9000:9000 \\
            --mount type=volume,src=$AUTH_VOLUME,dst=$AUTH_DIR \\
            --name "$name" -e RUST_LOG="$RUST_LOG" $volumes_from \\
            $PULL_FLAG $restart_arg $health_check_args $PLATFORM_ARG $IMAGE_TAG \\
            run $AUTH_DIR \\
            $auto_update_arg \\
            ${PUBLIC_IP:+"--agent-public-addr=$PUBLIC_IP:$AGENT_PORT"}
EOF
}

check_and_stop_existing_container() {
    if ${CONTAINER_RT} ps -a --format "{{.Names}}" 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
        info "发现已存在的容器: ${CONTAINER_NAME}"

        if ${CONTAINER_RT} ps --format "{{.Names}}" 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
            progress "停止运行中的容器..."
            ${SUDO_CMD:+"$SUDO_CMD "}${CONTAINER_RT} stop "$CONTAINER_NAME" >/dev/null 2>&1
        fi

        progress "移除已存在的容器..."
        ${SUDO_CMD:+"$SUDO_CMD "}${CONTAINER_RT} rm "$CONTAINER_NAME" >/dev/null 2>&1

        info "已存在的容器已移除"
    fi
}

# ============================================================================
#                              安装函数
# ============================================================================
install() {
    check_and_stop_existing_container

    progress "安装 worker。将打印正在运行的命令以便透明。"
    echo ""

    progress "以交互式设置模式启动 worker。"
    echo ""

    local setup_cmd=$(make_setup_cmd)

    sh -c "set -ex; $setup_cmd"

    local exit_code=$?

    echo ""

    if [[ $exit_code -eq 130 ]]; then
        info "Worker 设置已取消。您可以随时重新运行此脚本。"
        exit 0
    elif [[ $exit_code -ne 0 ]]; then
        error "设置失败 ($exit_code)"
        exit 1
    fi

    local run_cmd=$(make_run_cmd)

    sh -c "set -ex; $run_cmd"

    exit_code=$?

    echo ""

    if [[ $exit_code -ne 0 ]]; then
        error "Worker 启动失败 ($exit_code)"

        local logs_output=$(docker logs "$CONTAINER_NAME" 2>&1 | tail -5)
        if echo "$logs_output" | grep -q "node_auth.txt\|No such file or directory"; then
            echo ""
            error "未找到授权文件。这通常意味着："
            error "  1. 交互式设置未完成"
            error "  2. 未输入授权令牌"
            echo ""
            error "请重新运行此脚本并确保完成交互式设置"
            error "并在提示时输入授权令牌。"
        fi
    fi
}

update() {
    progress "更新 worker。将打印正在运行的命令以便透明。"
    echo ""

    local container_old="$CONTAINER_NAME"
    local container_new="$CONTAINER_NAME-new"

    local create_cmd=$(make_run_cmd "" "create" "$container_new" "$container_old")

    ${SUDO_CMD+"$SUDO_CMD "}bash <<-EOF
        set -x

        ($CONTAINER_RT inspect "$CONTAINER_NAME-old" >/dev/null 2>&1)

        if [ \$? -eq 0 ]; then
            echo "$CONTAINER_NAME-old 已存在 (可能来自失败的运行)，请在继续前删除它" 1>&2
            exit 1
        fi

        ($CONTAINER_RT inspect "$container_new" >/dev/null 2>&1)

        if [ \$? -eq 0 ]; then
            echo "$container_new 已存在 (可能来自失败的运行)，请在继续前删除它" 1>&2
            exit 1
        fi

        set -ex

        $create_cmd
        $CONTAINER_RT stop $container_old
        $CONTAINER_RT start $container_new
        $CONTAINER_RT rename $container_old $CONTAINER_NAME-old
        $CONTAINER_RT rename $container_new $CONTAINER_NAME

        echo -n "是否删除 $CONTAINER_NAME-old? (Y/n) "
        read -r choice </dev/tty

        if [[ "\$choice" != [nN] ]]; then
            $CONTAINER_RT rm $CONTAINER_NAME-old
        fi
EOF

    if [[ $? -ne 0 ]]; then
        error "Worker 升级失败"
        exit 1
    fi
}

# ============================================================================
#                              监控和快捷方式
# ============================================================================
setup_monitor_script() {
    local monitor_script="$HOME/.local/bin/monitor_tashi.sh"
    local log_file="/tmp/tashi_monitor.log"

    mkdir -p "$HOME/.local/bin" 2>/dev/null || true

    if [[ ! -d "$HOME/.local/bin" ]] || [[ ! -w "$HOME/.local/bin" ]]; then
        monitor_script="/usr/local/bin/monitor_tashi.sh"
    fi

    if [[ "$monitor_script" == "/usr/local/bin/monitor_tashi.sh" ]]; then
        ${SUDO_CMD:+"$SUDO_CMD "}bash -c "cat > '$monitor_script'" << 'MONITOR_EOF'
#!/bin/bash
CONTAINER_NAME="tashi-depin-worker"
LOG_FILE="/tmp/tashi_monitor.log"

if ! docker ps -a --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    exit 0
fi

if ! docker ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    exit 0
fi

if docker logs --since 5m "$CONTAINER_NAME" 2>&1 | grep -q "disconnected from orchestrator"; then
    if ! docker logs --since 2m "$CONTAINER_NAME" 2>&1 | grep -q "resource node successfully bonded"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S'): Restarting container due to disconnection" >> "$LOG_FILE" 2>/dev/null
        docker restart "$CONTAINER_NAME" >/dev/null 2>&1
    fi
fi
MONITOR_EOF
        ${SUDO_CMD:+"$SUDO_CMD "}chmod +x "$monitor_script" 2>/dev/null || true
    else
        cat > "$monitor_script" << 'MONITOR_EOF'
#!/bin/bash
CONTAINER_NAME="tashi-depin-worker"
LOG_FILE="/tmp/tashi_monitor.log"

if ! docker ps -a --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    exit 0
fi

if ! docker ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    exit 0
fi

if docker logs --since 5m "$CONTAINER_NAME" 2>&1 | grep -q "disconnected from orchestrator"; then
    if ! docker logs --since 2m "$CONTAINER_NAME" 2>&1 | grep -q "resource node successfully bonded"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S'): Restarting container due to disconnection" >> "$LOG_FILE" 2>/dev/null
        docker restart "$CONTAINER_NAME" >/dev/null 2>&1
    fi
fi
MONITOR_EOF
        chmod +x "$monitor_script" 2>/dev/null || true
    fi

    if [[ ! -f "$monitor_script" ]]; then
        warn "无法创建监控脚本: $monitor_script"
        return 1
    fi

    local cron_entry="*/5 * * * * $monitor_script >/dev/null 2>&1"

    local existing_cron=$(crontab -l 2>/dev/null | grep "monitor_tashi.sh" || true)
    if [[ -n "$existing_cron" ]] && [[ "$existing_cron" != *"$monitor_script"* ]]; then
        crontab -l 2>/dev/null | grep -v "monitor_tashi.sh" | crontab - 2>/dev/null || true
    fi

    if ! crontab -l 2>/dev/null | grep -q "monitor_tashi.sh"; then
        (crontab -l 2>/dev/null; echo "$cron_entry") | crontab - 2>/dev/null || true
    fi

    if crontab -l 2>/dev/null | grep -q "monitor_tashi.sh"; then
        return 0
    else
        warn "无法添加监控脚本到 crontab"
        return 1
    fi
}

create_desktop_shortcut() {
    local desktop_path=""

    if [[ -n "$HOME" ]]; then
        if [[ "$OS" == "macos" ]]; then
            desktop_path="$HOME/Desktop"
        elif [[ -d "$HOME/Desktop" ]]; then
            desktop_path="$HOME/Desktop"
        elif [[ -d "$HOME/桌面" ]]; then
            desktop_path="$HOME/桌面"
        fi
    fi

    if [[ -z "$desktop_path" || ! -d "$desktop_path" ]]; then
        info "未找到桌面目录，跳过创建快捷方式。"
        return
    fi

    local shortcut_file="$desktop_path/Tashi.command"

    cat > "$shortcut_file" <<'SCRIPT_EOF'
#!/bin/bash

# Tashi DePIN Worker 重启脚本 - 土豆科技

GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

CONTAINER_NAME="tashi-depin-worker"
AUTH_VOLUME="tashi-depin-worker-auth"
AUTH_DIR="/home/worker/auth"
AGENT_PORT=39065
IMAGE_TAG="ghcr.io/tashigg/tashi-depin-worker:0"
PLATFORM_ARG="--platform linux/amd64"
RUST_LOG="info,tashi_depin_worker=debug,tashi_depin_common=debug"

cd "$(dirname "$0")" || exit 1

clear

if docker stop "$CONTAINER_NAME" >/dev/null 2>&1; then
    docker rm "$CONTAINER_NAME" >/dev/null 2>&1
fi

if docker run -d \
    -p "$AGENT_PORT:$AGENT_PORT" \
    -p 127.0.0.1:9000:9000 \
    --mount type=volume,src="$AUTH_VOLUME",dst="$AUTH_DIR" \
    --name "$CONTAINER_NAME" \
    -e RUST_LOG="$RUST_LOG" \
    --health-cmd='pgrep -f tashi-depin-worker || exit 1' \
    --health-interval=30s \
    --health-timeout=10s \
    --health-retries=3 \
    --restart=unless-stopped \
    --pull=always \
    $PLATFORM_ARG \
    "$IMAGE_TAG" \
    run "$AUTH_DIR" \
    --unstable-update-download-path /tmp/tashi-depin-worker; then
    :
else
    exit 1
fi

docker logs -f "$CONTAINER_NAME"
SCRIPT_EOF

    chmod +x "$shortcut_file"

    info "桌面快捷方式已创建: $shortcut_file"
}

post_install() {
    echo ""

    info "Worker 正在运行！"

    echo ""

    local status_cmd="${SUDO_CMD:+"$SUDO_CMD "}${CONTAINER_RT} ps"
    local logs_cmd="${SUDO_CMD:+"$SUDO_CMD "}${CONTAINER_RT} logs $CONTAINER_NAME"

    info "查看 worker 状态: '$status_cmd' (名称: $CONTAINER_NAME)"
    info "查看 worker 日志: '$logs_cmd'"

    setup_monitor_script

    create_desktop_shortcut

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}                    ${BOLD}部署完成！${NC}                               ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ============================================================================
#                              主程序
# ============================================================================

# 首先验证许可证
verify_license

# 检测操作系统
detect_os

# 打印横幅
print_banner

# 检查 Docker
print_step "1" "8" "检查 Docker 安装"
check_container_runtime

# 运行系统检查
print_step "2" "8" "系统检查"
echo ""
check_platform
check_cpu
check_memory
check_disk
check_root_required
check_internet

echo ""
check_warnings

horizontal_line

print_step "3" "8" "NAT 检查"
check_nat

horizontal_line

print_step "4" "8" "自动更新设置"
prompt_auto_updates

horizontal_line

prompt_continue

case "$SUBCOMMAND" in
    install) install ;;
    update) update ;;
    *)
        error "BUG: 无 $SUBCOMMAND 处理程序"
        exit 1
esac

post_install
