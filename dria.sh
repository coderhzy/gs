#!/bin/bash
#
# Dria 节点安装脚本 - 土豆科技
#

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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
    echo -e "🔄 正在验证许可证..."

    if check_license_cache; then
        echo -e "${GREEN}🌿 许可证验证通过 (缓存有效)${NC}"
        echo -e "${GREEN}🎉 欢迎使用！祝您使用愉快！${NC}"
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
#                           主程序
# ============================================================================

# 首先验证许可证
verify_license

echo -e "${BLUE}🚀 开始安装 Dria...${NC}"

# 检测操作系统
OS=$(uname -s)
if [[ "$OS" != "Darwin" ]]; then
    echo -e "${RED}❌ 此脚本目前仅支持 macOS${NC}"
    exit 1
fi

# 检查并安装 Ollama
if [ -d "/Applications/Ollama.app" ]; then
    echo -e "${GREEN}✅ Ollama 已存在，跳过安装${NC}"
    echo -e "${BLUE}🚀 正在启动 Ollama...${NC}"
    open /Applications/Ollama.app
else
    echo -e "${BLUE}📥 正在下载 Ollama...${NC}"
    curl -L -o ~/Downloads/Ollama.dmg https://ollama.com/download/Ollama.dmg

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Ollama 下载完成${NC}"
        echo -e "${BLUE}🔧 正在挂载 Ollama.dmg...${NC}"

        hdiutil attach ~/Downloads/Ollama.dmg

        echo -e "${BLUE}📦 正在安装 Ollama 到 Applications 文件夹...${NC}"
        cp -R "/Volumes/Ollama/Ollama.app" /Applications/

        echo -e "${BLUE}🗑️ 清理临时文件...${NC}"
        hdiutil detach "/Volumes/Ollama"
        rm ~/Downloads/Ollama.dmg

        echo -e "${GREEN}✅ Ollama 安装完成！${NC}"

        echo -e "${BLUE}🚀 正在启动 Ollama...${NC}"
        open /Applications/Ollama.app

        echo -e "${YELLOW}⏳ 等待 Ollama 启动完成...${NC}"
        sleep 5
    else
        echo -e "${RED}❌ Ollama 下载失败，但继续安装 Dria...${NC}"
    fi
fi

echo ""
echo -e "${BLUE}📱 现在开始安装 Dria...${NC}"

# 检查 Dria 是否已安装
if command -v dkn-compute-launcher &> /dev/null; then
    echo -e "${GREEN}✅ Dria 已存在，跳过安装${NC}"
else
    echo -e "${BLUE}📥 正在下载并安装 Dria...${NC}"
    curl -fsSL https://dria.co/launcher | bash

    echo -e "${BLUE}🔄 重新加载 shell 配置...${NC}"
    source ~/.zshrc 2>/dev/null || source ~/.bashrc 2>/dev/null
fi

echo -e "${GREEN}✅ Dria 安装完成！${NC}"
echo ""
echo -e "${YELLOW}🔗 获取邀请码步骤：${NC}"
echo "请在新的终端窗口中运行以下命令获取你的邀请码："
echo ""
echo -e "   ${BLUE}dkn-compute-launcher referrals${NC}"
echo ""
echo "然后选择：Get referral code to refer someone"
echo ""
echo -e "${YELLOW}请在新的终端窗口中运行以下命令更改端口：${NC}"
echo ""
echo -e "   ${BLUE}dkn-compute-launcher settings${NC}"
echo ""
echo -e "${YELLOW}📝 全部设置完成后，请回到这里按回车键继续...${NC}"
read -p "按回车键继续..."

# 生成桌面启动文件
echo -e "${BLUE}📝 正在生成桌面启动文件...${NC}"
cat > ~/Desktop/dria_start.command <<'EOF'
#!/bin/bash

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}🚀 启动 Dria 节点...${NC}"

if ! command -v dkn-compute-launcher &> /dev/null; then
    echo -e "${RED}❌ dkn-compute-launcher 命令未找到，请检查安装${NC}"
    echo "按任意键退出..."
    read -n 1 -s
    exit 1
fi

echo -e "${BLUE}📡 正在启动 Dria 计算节点...${NC}"
dkn-compute-launcher start

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ 节点启动失败${NC}"
    echo "按任意键退出..."
    read -n 1 -s
fi
EOF

chmod +x ~/Desktop/dria_start.command
echo -e "${GREEN}✅ 桌面启动文件已创建: ~/Desktop/dria_start.command${NC}"

echo -e "${GREEN}✅ 安装和配置完成！${NC}"
echo -e "${BLUE}🚀 正在启动 Dria 节点...${NC}"
dkn-compute-launcher start
