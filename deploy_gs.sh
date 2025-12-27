#!/bin/bash
#
# ============================================================================
#                         版权声明 / COPYRIGHT NOTICE
# ============================================================================
#
# 本软件受版权法保护，未经授权不得复制、修改、分发或用于商业用途。
# This software is protected by copyright law. Unauthorized copying,
# modification, distribution, or commercial use is prohibited.
#
# 版权所有 (C) 2024-2025 土豆科技. 保留所有权利。
# Copyright (C) 2024-2025 Tudou Tech. All rights reserved.
#
# 许可证类型: 商业许可证 / License Type: Commercial License
# 获取许可证请添加微信: tudou_eth
#
# 警告: 未经授权使用本软件将承担法律责任！
# WARNING: Unauthorized use of this software may result in legal action!
#
# ============================================================================

set -e
set -o pipefail

# ============================================================================
#                           许可证验证模块
# ============================================================================

# 配置项 - 请修改为你自己的验证服务器地址
LICENSE_SERVER_URL="license-api.hzy1257664828.workers.dev"
LICENSE_FILE="$HOME/.gensyn_license"
LICENSE_CACHE_FILE="$HOME/.gensyn_license_cache"
CACHE_VALID_HOURS=24

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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
    # 这是一个简单的验证逻辑，你可以根据需要加强
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
#                           执行许可证验证
# ============================================================================
verify_license

# ============================================================================
#                           主程序开始
# ============================================================================

echo ""
echo -e "${GREEN}💕🌿═══════════════════════════════════════════════🌿💕${NC}"
echo -e "${GREEN}💕      一键部署 RL-Swarm 环境 - 土豆科技出品       💕${NC}"
echo -e "${GREEN}💕🌿═══════════════════════════════════════════════🌿💕${NC}"
echo ""
echo "🚀 Starting one-click RL-Swarm environment deployment..."

# 仅支持 gensyn

# ----------- 检测操作系统 -----------
OS_TYPE="unknown"
if [[ "$(uname -s)" == "Darwin" ]]; then
  OS_TYPE="macos"
elif [[ -f /etc/os-release ]]; then
  . /etc/os-release
  if [[ "$ID" == "ubuntu" ]]; then
    OS_TYPE="ubuntu"
  fi
fi

if [[ "$OS_TYPE" == "unknown" ]]; then
  echo "❌ 不支持的操作系统。仅支持 macOS 和 Ubuntu。"
  exit 1
fi

# ----------- /etc/hosts Patch -----------
echo "🌿💕 检查 /etc/hosts 配置..."
if ! grep -q "raw.githubusercontent.com" /etc/hosts; then
  echo "💕 写入 GitHub 加速 Hosts 配置..."
  sudo tee -a /etc/hosts > /dev/null <<EOL
199.232.68.133 raw.githubusercontent.com
199.232.68.133 user-images.githubusercontent.com
199.232.68.133 avatars2.githubusercontent.com
199.232.68.133 avatars1.githubusercontent.com
EOL
else
  echo "🌿 Hosts 已配置完成"
fi

# ----------- 安装依赖 -----------
if [[ "$OS_TYPE" == "macos" ]]; then
  echo "🌿💕 检查 Homebrew..."
  if ! command -v brew &>/dev/null; then
    echo "💕 正在安装 Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  else
    echo "🌿 Homebrew 已安装，跳过"
  fi
  # 配置 Brew 环境变量
  BREW_ENV='eval "$(/opt/homebrew/bin/brew shellenv)"'
  if ! grep -q "$BREW_ENV" ~/.zshrc; then
    echo "$BREW_ENV" >> ~/.zshrc
  fi
  eval "$(/opt/homebrew/bin/brew shellenv)"
  # 安装依赖
  echo "🌿💕 检查并安装依赖包..."
  deps=(node python3.10 curl screen git yarn)
  brew_names=(node python@3.10 curl screen git yarn)
  for i in "${!deps[@]}"; do
    dep="${deps[$i]}"
    brew_name="${brew_names[$i]}"
    if ! command -v $dep &>/dev/null; then
      echo "💕 安装 $brew_name..."
      while true; do
        if brew install $brew_name; then
          echo "🌿 $brew_name 安装成功"
          break
        else
          echo "⚠️ $brew_name 安装失败，3秒后重试..."
          sleep 3
        fi
      done
    else
      echo "🌿 $dep 已安装，跳过"
    fi
  done
  # 自动清理.zshrc中python3.12配置，并写入3.10配置
  if grep -q "# Python3.12 Environment Setup" ~/.zshrc; then
    echo "🧹 清理旧的 Python3.12 配置..."
    sed -i '' '/# Python3.12 Environment Setup/,/^fi$/d' ~/.zshrc
  fi
  PYTHON_ALIAS="# Python3.10 Environment Setup"
  if ! grep -q "$PYTHON_ALIAS" ~/.zshrc; then
    cat << 'EOF' >> ~/.zshrc

# Python3.10 Environment Setup
if [[ $- == *i* ]]; then
  alias python="/opt/homebrew/bin/python3.10"
  alias python3="/opt/homebrew/bin/python3.10"
  alias pip="/opt/homebrew/bin/pip3.10"
  alias pip3="/opt/homebrew/bin/pip3.10"
fi
EOF
  fi
  source ~/.zshrc || true
else
  # Ubuntu
  echo "🌿💕 检查并安装依赖包..."
  # 检查当前Node.js版本
  if command -v node &>/dev/null; then
    CURRENT_NODE_VERSION=$(node --version 2>/dev/null | sed 's/v//')
    echo "🔍 当前 Node.js 版本: $CURRENT_NODE_VERSION"
    # 获取最新LTS版本
    LATEST_LTS_VERSION=$(curl -s https://nodejs.org/dist/index.json | jq -r '.[0].version' 2>/dev/null | sed 's/v//')
    echo "🔍 最新 LTS 版本: $LATEST_LTS_VERSION"
    
    if [[ "$CURRENT_NODE_VERSION" != "$LATEST_LTS_VERSION" ]]; then
      echo "🔄 检测到版本不匹配，正在更新到最新 LTS 版本..."
      # 卸载旧版本
      sudo apt remove -y nodejs npm || true
      sudo apt autoremove -y || true
      # 清理可能的残留
      sudo rm -rf /usr/local/bin/npm /usr/local/bin/node || true
      sudo rm -rf ~/.npm || true
      # 安装最新LTS版本
      curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
      sudo apt-get install -y nodejs
      echo "🌿 Node.js 已更新到最新 LTS 版本"
    else
      echo "🌿 Node.js 已是最新 LTS 版本，跳过更新"
    fi
  else
    echo "📥 未检测到 Node.js，正在安装最新 LTS 版本..."
    # 安装最新Node.js（LTS）
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
    sudo apt-get install -y nodejs
    echo "🌿 Node.js 安装完成"
  fi
  # 其余依赖
  sudo apt update && sudo apt install -y python3 python3-venv python3-pip curl screen git gnupg jq
  # 官方推荐方式，若失败则用npm镜像
  if curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | gpg --dearmor | sudo tee /usr/share/keyrings/yarnkey.gpg > /dev/null \
    && echo "deb [signed-by=/usr/share/keyrings/yarnkey.gpg] https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list \
    && sudo apt update && sudo apt install -y yarn; then
    echo "🌿 yarn 安装成功（官方源）"
    # 升级到最新版yarn（Berry）
    yarn set version stable
    yarn -v
  else
    echo "⚠️ 官方源安装 yarn 失败，尝试用 npm 镜像安装..."
    if ! command -v npm &>/dev/null; then
      sudo apt install -y npm
    fi
    npm config set registry https://registry.npmmirror.com
    npm install -g yarn
    # 升级到最新版yarn（Berry）
    yarn set version stable
    yarn -v
  fi
  # Python alias 写入 bashrc
  PYTHON_ALIAS="# Python3.12 Environment Setup"
  if ! grep -q "$PYTHON_ALIAS" ~/.bashrc; then
    cat << 'EOF' >> ~/.bashrc

# Python3.12 Environment Setup
if [[ $- == *i* ]]; then
  alias python="/usr/bin/python3"
  alias python3="/usr/bin/python3"
  alias pip="/usr/bin/pip3"
  alias pip3="/usr/bin/pip3"
fi
EOF
  fi
  source ~/.bashrc || true
fi

# ----------- 克隆前备份关键文件 -----------
echo ""
echo "🌿💕 备份关键用户文件..."
TMP_USER_FILES="$HOME/rl-swarm-user-files"
mkdir -p "$TMP_USER_FILES"

# swarm.pem
if [ -f "$HOME/rl-swarm-0.5.3/swarm.pem" ]; then
  cp "$HOME/rl-swarm-0.5.3/swarm.pem" "$TMP_USER_FILES/swarm.pem" && echo "🌿 已备份 swarm.pem"
elif [ -f "$HOME/rl-swarm-0.5.3/user/keys/swarm.pem" ]; then
  cp "$HOME/rl-swarm-0.5.3/user/keys/swarm.pem" "$TMP_USER_FILES/swarm.pem" && echo "🌿 已备份 swarm.pem"
elif [ -f "$HOME/rl-swarm-0.5/user/keys/swarm.pem" ]; then
  cp "$HOME/rl-swarm-0.5/user/keys/swarm.pem" "$TMP_USER_FILES/swarm.pem" && echo "🌿 已备份 swarm.pem"
elif [ -f "$HOME/rl-swarm/swarm.pem" ]; then
  cp "$HOME/rl-swarm/swarm.pem" "$TMP_USER_FILES/swarm.pem" && echo "🌿 已备份 swarm.pem"
else
  echo "💕 未检测到 swarm.pem，首次安装无需备份"
fi

# userApiKey.json
if [ -f "$HOME/rl-swarm-0.5.3/modal-login/temp-data/userApiKey.json" ]; then
  cp "$HOME/rl-swarm-0.5.3/modal-login/temp-data/userApiKey.json" "$TMP_USER_FILES/userApiKey.json" && echo "🌿 已备份 userApiKey.json"
elif [ -f "$HOME/rl-swarm-0.5.3/user/modal-login/userApiKey.json" ]; then
  cp "$HOME/rl-swarm-0.5.3/user/modal-login/userApiKey.json" "$TMP_USER_FILES/userApiKey.json" && echo "🌿 已备份 userApiKey.json"
elif [ -f "$HOME/rl-swarm-0.5/user/modal-login/userApiKey.json" ]; then
  cp "$HOME/rl-swarm-0.5/user/modal-login/userApiKey.json" "$TMP_USER_FILES/userApiKey.json" && echo "🌿 已备份 userApiKey.json"
elif [ -f "$HOME/rl-swarm/modal-login/temp-data/userApiKey.json" ]; then
  cp "$HOME/rl-swarm/modal-login/temp-data/userApiKey.json" "$TMP_USER_FILES/userApiKey.json" && echo "🌿 已备份 userApiKey.json"
else
  echo "💕 未检测到 userApiKey.json，首次安装无需备份"
fi

# userData.json
if [ -f "$HOME/rl-swarm-0.5.3/modal-login/temp-data/userData.json" ]; then
  cp "$HOME/rl-swarm-0.5.3/modal-login/temp-data/userData.json" "$TMP_USER_FILES/userData.json" && echo "🌿 已备份 userData.json"
elif [ -f "$HOME/rl-swarm-0.5.3/user/modal-login/userData.json" ]; then
  cp "$HOME/rl-swarm-0.5.3/user/modal-login/userData.json" "$TMP_USER_FILES/userData.json" && echo "🌿 已备份 userData.json"
elif [ -f "$HOME/rl-swarm-0.5/user/modal-login/userData.json" ]; then
  cp "$HOME/rl-swarm-0.5/user/modal-login/userData.json" "$TMP_USER_FILES/userData.json" && echo "🌿 已备份 userData.json"
elif [ -f "$HOME/rl-swarm/modal-login/temp-data/userData.json" ]; then
  cp "$HOME/rl-swarm/modal-login/temp-data/userData.json" "$TMP_USER_FILES/userData.json" && echo "🌿 已备份 userData.json"
else
  echo "💕 未检测到 userData.json，首次安装无需备份"
fi

# ----------- Clone Repo -----------
echo ""
echo "🌿💕 准备克隆项目仓库..."
if [[ -d "rl-swarm" ]]; then
  echo "💕 检测到已存在目录 'rl-swarm'"
  read -p "是否覆盖（删除后重新克隆）该目录？(y/n): " confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    echo "🗑️ 正在删除旧目录..."
    rm -rf rl-swarm
    echo "💕 正在克隆 rl-swarm 仓库..."
    git clone -b v0.5.8 https://github.com/readyName/rl-swarm.git
    echo "🌿 仓库克隆完成"
  else
    echo "💕 跳过克隆，继续后续流程"
  fi
else
  echo "💕 正在克隆 rl-swarm 仓库..."
  git clone -b v0.5.8 https://github.com/readyName/rl-swarm.git
  echo "🌿 仓库克隆完成"
fi

# ----------- 复制临时目录中的 user 关键文件 -----------
KEY_DST="rl-swarm/swarm.pem"
MODAL_DST="rl-swarm/modal-login/temp-data"
mkdir -p "$MODAL_DST"

if [ -f "$TMP_USER_FILES/swarm.pem" ]; then
  cp "$TMP_USER_FILES/swarm.pem" "$KEY_DST" && echo "🌿 恢复 swarm.pem 到新目录" || echo "⚠️ 恢复 swarm.pem 失败"
else
  echo "⚠️ 临时目录缺少 swarm.pem，如有需要请手动补齐。"
fi

for fname in userApiKey.json userData.json; do
  if [ -f "$TMP_USER_FILES/$fname" ]; then
    cp "$TMP_USER_FILES/$fname" "$MODAL_DST/$fname" && echo "🌿 恢复 $fname 到新目录" || echo "⚠️ 恢复 $fname 失败"
  else
    echo "⚠️ 临时目录缺少 $fname，如有需要请手动补齐。"
  fi
  
done

# ----------- 生成桌面可双击运行的 .command 文件 -----------
if [[ "$OS_TYPE" == "macos" ]]; then
  CURRENT_USER=$(whoami)
  PROJECT_DIR="/Users/$CURRENT_USER/rl-swarm"
  DESKTOP_DIR="/Users/$CURRENT_USER/Desktop"
  mkdir -p "$DESKTOP_DIR"

  # 生成 gensyn.command 文件
  cat > "$DESKTOP_DIR/gensyn.command" <<EOF
#!/bin/bash

set -e
trap 'echo -e "\n\033[33m⚠️ 脚本被中断，但终端将继续运行...\033[0m"; exit 0' INT TERM

cd "$PROJECT_DIR" || { echo "❌ 无法进入项目目录"; exit 1; }
echo "🚀 正在执行 gensyn.sh..."
./gensyn.sh
echo -e "\n\033[32m🌿 gensyn.sh 执行完成\033[0m"
echo "按任意键关闭此窗口..."
read -n 1 -s
EOF
  chmod +x "$DESKTOP_DIR/gensyn.command"

  echo "🌿 已在桌面生成 gensyn.command 文件。"
fi

# ----------- Clean Port 3000 ----------- 
echo "🧹 Cleaning up port 3000..."
pid=$(lsof -ti:3000) && [ -n "$pid" ] && kill -9 $pid && echo "🌿 Killed: $pid" || echo "🌿 Port 3000 is free."

# ----------- 进入rl-swarm目录并执行-----------
cd rl-swarm || { echo "❌ 进入 rl-swarm 目录失败"; exit 1; }
chmod +x gensyn.sh
./gensyn.sh
