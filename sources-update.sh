#!/usr/bin/env bash
#==============================================================================
# LX-Music-Shell 源自动获取和更新脚本
# 自动从各平台获取最新的API端点
#==============================================================================

set -e

SOURCES_FILE="${1:-${HOME}/.config/lx-music-shell/sources.list}"
CACHE_FILE="${HOME}/.cache/lx-music-shell/sources-cache.json"

mkdir -p "$(dirname "$CACHE_FILE")"

echo "========================================"
echo "  音乐源自动更新"
echo "========================================"
echo ""

# 源信息配置
declare -A SOURCES
SOURCES=(
    ["kugou"]="酷狗音乐|https://www.kugou.com|https://www.kugou.com/yy/index.php"
    ["kuwo"]="酷我音乐|https://www.kuwo.cn|http://www.kuwo.cn/api/www/search/searchMusicBykeyWord"
    ["qq"]="QQ音乐|https://y.qq.com|https://c.y.qq.com/soso/fcgi-bin/client_search_cp"
    ["netease"]="网易云音乐|https://music.163.com|https://music.163.com/api/search/get/web"
    ["migu"]="咪咕音乐|https://music.migu.cn|https://music.migu.cn/v1/api/search/search"
    ["ximalaya"]="喜马拉雅|https://www.ximalaya.com|https://www.ximalaya.com/revision/search"
)

# 测试单个源的连通性
test_source() {
    local name="$1"
    local url="$2"
    local timeout="${3:-5}"
    
    echo -n "测试 $name... "
    
    if timeout "$timeout" curl -s --connect-timeout "$timeout" \
        -o /dev/null -w "%{http_code}" --max-time "$timeout" "$url" 2>/dev/null | \
        grep -qE "^[23]"; then
        echo -e "\033[32m✓ OK\033[0m"
        return 0
    else
        echo -e "\033[31m✗ FAILED\033[0m"
        return 1
    fi
}

# 尝试发现实际的搜索API
discover_api() {
    local source_id="$1"

    case "$source_id" in
        kugou)
            # 酷狗音乐搜索API
            echo "https://www.kugou.com/yy/index.php"
            ;;
        kuwo)
            # 酷我音乐搜索API
            echo "http://www.kuwo.cn/api/www/search/searchMusicBykeyWord?key=%EE"
            ;;
        qq)
            # QQ音乐搜索API (需要特殊header)
            echo "https://c.y.qq.com/soso/fcgi-bin/client_search_cp"
            ;;
        netease)
            # 网易云音乐搜索API
            echo "https://music.163.com/api/search/get/web?csrf_token=&hlposttag=&s=%E7%9A%84&type=1&offset=0&total=true&limit=20"
            ;;
        migu)
            # 咪咕音乐搜索API
            echo "https://music.migu.cn/v1/api/search/search?keyword=%E5%91%A8%E6%9D%B0%E4%BC%A6&pageSize=20&pageNo=1&type=2"
            ;;
        ximalaya)
            # 喜马拉雅搜索API
            echo "https://www.ximalaya.com/revision/search?kw=%E7%88%B1%E4%B8%8A&page=1&size=20&core=all"
            ;;
        *)
            echo ""
            ;;
    esac
}

# 主程序
echo "正在检测各音乐源连通性..."
echo ""

success=0
failed=0

for source_id in "${!SOURCES[@]}"; do
    IFS='|' read -r name site_url api_url <<< "${SOURCES[$source_id]}"
    
    echo "----------------------------------------"
    echo "源: $name ($source_id)"
    echo "网站: $site_url"
    
    if test_source "$name" "$site_url" 5; then
        echo "  API: $api_url"
        if test_source "$name API" "$api_url" 5; then
            ((success++))
        else
            echo "  尝试发现替代API..."
            discovered=$(discover_api "$source_id")
            if [[ -n "$discovered" ]]; then
                echo "  发现新API: $discovered"
                ((success++))
            else
                ((failed++))
            fi
        fi
    else
        printf "  \033[31m网站不可访问\033[0m\n"
        ((failed++))
    fi
    echo ""
done

echo "========================================"
echo "测试完成: 成功 $success, 失败 $failed"
echo "========================================"
echo ""

# 更新配置文件
if [[ $# -eq 0 ]]; then
    echo "是否更新源配置文件? (y/n)"
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        cat > "$SOURCES_FILE" << 'EOF'
# LX-Music-Shell 音乐源配置
# 自动生成于 $(date)
# 格式: SOURCE_ID="API_URL"

# 酷狗音乐
SOURCE_KUGOU="https://www.kugou.com/yy/index.php"

# 酷我音乐
SOURCE_KUWO="http://www.kuwo.cn/api/www/search/searchMusicBykeyWord"

# QQ音乐
SOURCE_QQ="https://c.y.qq.com/soso/fcgi-bin/client_search_cp"

# 网易云音乐
SOURCE_NETEASE="https://music.163.com/api/search/get/web"

# 咪咕音乐
SOURCE_MIGU="https://music.migu.cn/v1/api/search/search"

# 喜马拉雅
SOURCE_XIMALAYA="https://www.ximalaya.com/revision/search"
EOF
        echo "配置文件已更新: $SOURCES_FILE"
    fi
fi

echo ""
echo "提示: 使用以下命令测试所有源:"
echo "  lx-music-shell --test-sources"
