#!/bin/bash

# 设置颜色输出
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
DEPS_CHECK_FILE="$SCRIPT_DIR/missing_deps.txt"
DEPS_DOWNLOAD_DIR="$SCRIPT_DIR/downloaded_deps"

# 设置日志文件
LOG_FILE="$SCRIPT_DIR/deps_check.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# 检查是否为root用户
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}错误：请使用root权限运行此脚本${NC}"
    exit 1
fi

# 基于安装脚本识别的核心依赖列表
OPENSSH_DEPS=(
    "build-essential"
    "pkg-config"
    "autoconf"
    "automake"
    "libtool"
    "zlib1g-dev"
    "libpam0g-dev"
    "libselinux1-dev"
    "libkrb5-dev"
    "libaudit-dev"
    "libldap2-dev"
    "libsystemd-dev"
    "libedit-dev"
    "libc6"
    "libpam0g"
    "libpam-modules"
    "zlib1g"
    "libselinux1"
    "libcom-err2"
    "libkrb5-3"
    "libk5crypto3"
    "libkeyutils1"
    "libgssapi-krb5-2"
    "libaudit1"
    "libcap-ng0"
    "libldap-common"
    "libsasl2-modules-db"
    "libsasl2-modules"
    "libsystemd0"
    "libedit2"
)

# SSL相关的依赖包，这些包会被忽略以防止升级系统SSL库
SSL_PACKAGES=(
    "libssl-dev"
    "libssl3"
    "libssl1.1"
    "openssl"
    "openssl-dev"
)

# 显示菜单
show_menu() {
    echo -e "${GREEN}====== OpenSSH 9.8p1 依赖检查工具 ======${NC}"
    echo -e "${YELLOW}说明：此工具不会升级系统SSL库，将使用系统自带SSL库${NC}"
    echo -e "${YELLOW}警告：已从依赖列表中移除SSL相关库，以防止升级系统SSL库${NC}"
    echo -e "1. ${YELLOW}检查系统中缺失的依赖${NC}"
    echo -e "2. ${YELLOW}下载缺失的依赖（需要网络）${NC}"
    echo -e "3. ${YELLOW}从依赖检查文件下载依赖（需要网络）${NC}"
    echo -e "4. ${YELLOW}检查已有依赖包完整性${NC}"
    echo -e "5. ${YELLOW}集成缺失依赖到安装包${NC}"
    echo -e "0. ${YELLOW}退出${NC}"
    echo -e "${GREEN}=======================================${NC}"
    echo -ne "请选择操作 [0-5]: "
    read -r choice
    echo ""
    
    case $choice in
        1) check_missing_deps ;;
        2) download_missing_deps ;;
        3) download_deps_from_file ;;
        4) check_deps_integrity ;;
        5) integrate_deps ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效的选项，请重新选择${NC}" ; show_menu ;;
    esac
}

# 检查系统中缺失的依赖
check_missing_deps() {
    echo -e "${YELLOW}开始检查系统中缺失的依赖包...${NC}"
    
    # 清空缺失依赖文件
    > "$DEPS_CHECK_FILE"
    
    # 检查dpkg命令是否可用
    if ! command -v dpkg &> /dev/null; then
        echo -e "${RED}错误：dpkg命令不可用，无法检查依赖${NC}"
        return 1
    fi
    
    # 检查每个依赖
    MISSING_COUNT=0
    for pkg in "${OPENSSH_DEPS[@]}"; do
        if ! dpkg -l | grep -qE "^ii\s+$pkg"; then
            echo -e "${RED}未安装: $pkg${NC}"
            echo "$pkg" >> "$DEPS_CHECK_FILE"
            ((MISSING_COUNT++))
        else
            echo -e "${GREEN}已安装: $pkg${NC}"
        fi
    done
    
    # 还需要检查编译OpenSSH时的./configure过程可能需要的工具
    CONFIGURE_TOOLS=("gcc" "make" "pkg-config")
    for tool in "${CONFIGURE_TOOLS[@]}"; do
        if ! command -v $tool &> /dev/null; then
            echo -e "${RED}未安装工具: $tool${NC}"
            # 映射工具到包名
            case $tool in
                gcc) echo "gcc" >> "$DEPS_CHECK_FILE" ;;
                make) echo "make" >> "$DEPS_CHECK_FILE" ;;
                pkg-config) echo "pkg-config" >> "$DEPS_CHECK_FILE" ;;
            esac
            ((MISSING_COUNT++))
        else
            echo -e "${GREEN}已安装工具: $tool${NC}"
        fi
    done
    
    if [ $MISSING_COUNT -eq 0 ]; then
        echo -e "${GREEN}恭喜！所有必要依赖已安装，可以进行OpenSSH 9.8p1安装。${NC}"
    else
        echo -e "${YELLOW}发现 $MISSING_COUNT 个缺失的依赖/工具，已写入 $DEPS_CHECK_FILE${NC}"
        echo -e "${YELLOW}建议在有网络环境下运行此脚本选项2下载缺失依赖${NC}"
    fi
    
    # 分析依赖的依赖
    echo -e "${YELLOW}分析缺失依赖的深层依赖关系...${NC}"
    
    if [ $MISSING_COUNT -gt 0 ] && command -v apt-cache &> /dev/null; then
        TMP_DEEP_DEPS=$(mktemp)
        
        # 获取一级依赖的所有依赖
        for pkg in $(cat "$DEPS_CHECK_FILE"); do
            echo -e "${YELLOW}分析 $pkg 的依赖...${NC}"
            apt-cache depends "$pkg" 2>/dev/null | grep 'Depends:' | awk '{print $2}' >> "$TMP_DEEP_DEPS"
        done
        
        # 过滤、去重并添加到缺失依赖文件
        if [ -s "$TMP_DEEP_DEPS" ]; then
            DEEP_DEPS=$(sort -u "$TMP_DEEP_DEPS")
            for pkg in $DEEP_DEPS; do
                # 跳过SSL相关包
                SKIP=0
                for ssl_pkg in "${SSL_PACKAGES[@]}"; do
                    if [[ "$pkg" == "$ssl_pkg" ]]; then
                        echo -e "${YELLOW}跳过SSL相关包: $pkg${NC}"
                        SKIP=1
                        break
                    fi
                done
                
                if [ $SKIP -eq 1 ]; then
                    continue
                fi
                
                if ! dpkg -l | grep -qE "^ii\s+$pkg"; then
                    echo -e "${RED}未安装的深层依赖: $pkg${NC}"
                    grep -q "^$pkg$" "$DEPS_CHECK_FILE" || echo "$pkg" >> "$DEPS_CHECK_FILE"
                    ((MISSING_COUNT++))
                fi
            done
        fi
        
        rm -f "$TMP_DEEP_DEPS"
    fi
    
    # 最后清理掉可能仍存在的SSL相关依赖
    echo -e "${YELLOW}清理依赖列表中的SSL相关包...${NC}"
    TMP_CLEANED_DEPS=$(mktemp)
    while IFS= read -r pkg; do
        SKIP=0
        for ssl_pkg in "${SSL_PACKAGES[@]}"; do
            if [[ "$pkg" == "$ssl_pkg" ]]; then
                echo -e "${YELLOW}从最终列表中移除SSL相关包: $pkg${NC}"
                SKIP=1
                break
            fi
        done
        
        if [ $SKIP -eq 0 ]; then
            echo "$pkg" >> "$TMP_CLEANED_DEPS"
        fi
    done < "$DEPS_CHECK_FILE"
    
    # 用清理后的列表替换原列表
    mv "$TMP_CLEANED_DEPS" "$DEPS_CHECK_FILE"
    
    echo -e "${YELLOW}检查完成，共发现 $MISSING_COUNT 个缺失依赖，详见 $DEPS_CHECK_FILE${NC}"
    echo -e "${GREEN}注意：已从依赖列表中移除所有SSL相关包，以确保不会升级系统SSL库${NC}"
    echo ""
    show_menu
}

# 下载缺失的依赖
download_missing_deps() {
    echo -e "${YELLOW}开始下载缺失的依赖包...${NC}"
    
    # 检查网络连接
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        echo -e "${RED}错误：无法连接到网络，请确保网络正常${NC}"
        return 1
    fi
    
    # 检查apt-get命令是否可用
    if ! command -v apt-get &> /dev/null; then
        echo -e "${RED}错误：apt-get命令不可用，无法下载依赖${NC}"
        return 1
    fi
    
    # 检查是否有缺失依赖文件
    if [ ! -f "$DEPS_CHECK_FILE" ] || [ ! -s "$DEPS_CHECK_FILE" ]; then
        echo -e "${RED}未找到缺失依赖文件或文件为空，请先运行选项1检查依赖${NC}"
        show_menu
        return 1
    fi
    
    # 创建下载目录
    mkdir -p "$DEPS_DOWNLOAD_DIR"
    
    # 更新包索引
    echo -e "${YELLOW}更新包索引...${NC}"
    apt-get update
    
    # 过滤掉SSL相关包
    echo -e "${YELLOW}过滤掉SSL相关包...${NC}"
    TMP_FILTERED_DEPS=$(mktemp)
    while IFS= read -r pkg; do
        SKIP=0
        for ssl_pkg in "${SSL_PACKAGES[@]}"; do
            if [[ "$pkg" == "$ssl_pkg" ]]; then
                echo -e "${YELLOW}跳过SSL相关包: $pkg${NC}"
                SKIP=1
                break
            fi
        done
        
        if [ $SKIP -eq 0 ]; then
            echo "$pkg" >> "$TMP_FILTERED_DEPS"
        fi
    done < "$DEPS_CHECK_FILE"
    
    # 下载每个缺失的依赖
    echo -e "${YELLOW}开始下载依赖...${NC}"
    cd "$DEPS_DOWNLOAD_DIR" || { echo -e "${RED}无法进入下载目录${NC}"; return 1; }
    
    DOWNLOAD_SUCCESS=0
    DOWNLOAD_FAILED=0
    
    while IFS= read -r pkg; do
        echo -e "${YELLOW}下载: $pkg${NC}"
        if apt-get download "$pkg"; then
            echo -e "${GREEN}成功下载: $pkg${NC}"
            ((DOWNLOAD_SUCCESS++))
        else
            echo -e "${RED}下载失败: $pkg${NC}"
            ((DOWNLOAD_FAILED++))
        fi
    done < "$TMP_FILTERED_DEPS"
    
    # 下载包的依赖
    echo -e "${YELLOW}尝试解析并下载包的依赖...${NC}"
    TMP_DEPS_LIST=$(mktemp)
    
    # 使用apt-cache depends递归获取所有依赖
    cat "$TMP_FILTERED_DEPS" | xargs apt-cache depends --recurse | grep '^\s*Depends:' | awk '{print $2}' | sort -u > "$TMP_DEPS_LIST"
    
    # 再次过滤SSL相关包
    TMP_FILTERED_DEEP_DEPS=$(mktemp)
    while IFS= read -r dep_pkg; do
        if [ -n "$dep_pkg" ] && [[ ! "$dep_pkg" =~ ":<none>$" ]]; then
            SKIP=0
            for ssl_pkg in "${SSL_PACKAGES[@]}"; do
                if [[ "$dep_pkg" == "$ssl_pkg" ]]; then
                    echo -e "${YELLOW}跳过SSL相关深层依赖: $dep_pkg${NC}"
                    SKIP=1
                    break
                fi
            done
            
            if [ $SKIP -eq 0 ]; then
                echo "$dep_pkg" >> "$TMP_FILTERED_DEEP_DEPS"
            fi
        fi
    done < "$TMP_DEPS_LIST"
    
    # 下载过滤后的深层依赖
    while IFS= read -r dep_pkg; do
        echo -e "${YELLOW}下载依赖: $dep_pkg${NC}"
        if apt-get download "$dep_pkg" 2>/dev/null; then
            echo -e "${GREEN}成功下载依赖: $dep_pkg${NC}"
            ((DOWNLOAD_SUCCESS++))
        else
            echo -e "${RED}下载依赖失败: $dep_pkg${NC}"
            ((DOWNLOAD_FAILED++))
        fi
    done < "$TMP_FILTERED_DEEP_DEPS"
    
    rm -f "$TMP_DEPS_LIST" "$TMP_FILTERED_DEPS" "$TMP_FILTERED_DEEP_DEPS"
    
    echo -e "${GREEN}依赖下载完成，成功: $DOWNLOAD_SUCCESS, 失败: $DOWNLOAD_FAILED${NC}"
    echo -e "${GREEN}注意：已跳过所有SSL相关包，确保不会升级系统SSL库${NC}"
    echo -e "${GREEN}下载的依赖包位于: $DEPS_DOWNLOAD_DIR${NC}"
    
    cd "$SCRIPT_DIR" || return 1
    echo ""
    show_menu
}

# 从依赖检查文件下载依赖
download_deps_from_file() {
    echo -e "${YELLOW}从指定文件下载依赖...${NC}"
    
    echo -ne "${YELLOW}请输入包含依赖列表的文件路径（默认: $DEPS_CHECK_FILE）: ${NC}"
    read -r deps_file
    
    if [ -z "$deps_file" ]; then
        deps_file="$DEPS_CHECK_FILE"
    fi
    
    if [ ! -f "$deps_file" ] || [ ! -s "$deps_file" ]; then
        echo -e "${RED}文件不存在或为空: $deps_file${NC}"
        show_menu
        return 1
    fi
    
    # 检查网络连接
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        echo -e "${RED}错误：无法连接到网络，请确保网络正常${NC}"
        return 1
    fi
    
    # 创建下载目录
    mkdir -p "$DEPS_DOWNLOAD_DIR"
    
    # 更新包索引
    echo -e "${YELLOW}更新包索引...${NC}"
    apt-get update
    
    # 过滤掉SSL相关包
    echo -e "${YELLOW}过滤掉SSL相关包...${NC}"
    TMP_FILTERED_DEPS=$(mktemp)
    while IFS= read -r pkg; do
        if [ -z "$pkg" ] || [[ "$pkg" =~ ^# ]]; then
            continue
        fi
        
        SKIP=0
        for ssl_pkg in "${SSL_PACKAGES[@]}"; do
            if [[ "$pkg" == "$ssl_pkg" ]]; then
                echo -e "${YELLOW}跳过SSL相关包: $pkg${NC}"
                SKIP=1
                break
            fi
        done
        
        if [ $SKIP -eq 0 ]; then
            echo "$pkg" >> "$TMP_FILTERED_DEPS"
        fi
    done < "$deps_file"
    
    # 下载每个依赖
    echo -e "${YELLOW}开始下载依赖...${NC}"
    cd "$DEPS_DOWNLOAD_DIR" || { echo -e "${RED}无法进入下载目录${NC}"; return 1; }
    
    DOWNLOAD_SUCCESS=0
    DOWNLOAD_FAILED=0
    
    while IFS= read -r pkg; do
        echo -e "${YELLOW}下载: $pkg${NC}"
        if apt-get download "$pkg"; then
            echo -e "${GREEN}成功下载: $pkg${NC}"
            ((DOWNLOAD_SUCCESS++))
        else
            echo -e "${RED}下载失败: $pkg${NC}"
            ((DOWNLOAD_FAILED++))
        fi
    done < "$TMP_FILTERED_DEPS"
    
    rm -f "$TMP_FILTERED_DEPS"
    
    echo -e "${GREEN}依赖下载完成，成功: $DOWNLOAD_SUCCESS, 失败: $DOWNLOAD_FAILED${NC}"
    echo -e "${GREEN}注意：已跳过所有SSL相关包，确保不会升级系统SSL库${NC}"
    echo -e "${GREEN}下载的依赖包位于: $DEPS_DOWNLOAD_DIR${NC}"
    
    cd "$SCRIPT_DIR" || return 1
    echo ""
    show_menu
}

# 检查已有依赖包完整性
check_deps_integrity() {
    echo -e "${YELLOW}检查已下载依赖包的完整性...${NC}"
    
    if [ ! -d "$DEPS_DOWNLOAD_DIR" ] || [ -z "$(ls -A "$DEPS_DOWNLOAD_DIR" 2>/dev/null)" ]; then
        echo -e "${RED}下载目录不存在或为空: $DEPS_DOWNLOAD_DIR${NC}"
        show_menu
        return 1
    fi
    
    TOTAL_PACKAGES=$(ls "$DEPS_DOWNLOAD_DIR"/*.deb 2>/dev/null | wc -l)
    VALID_PACKAGES=0
    INVALID_PACKAGES=0
    
    echo -e "${YELLOW}共发现 $TOTAL_PACKAGES 个.deb包，开始校验...${NC}"
    
    for pkg in "$DEPS_DOWNLOAD_DIR"/*.deb; do
        pkg_name=$(basename "$pkg")
        echo -ne "${YELLOW}校验: $pkg_name ${NC}"
        
        if dpkg-deb --info "$pkg" &>/dev/null; then
            echo -e "${GREEN}[有效]${NC}"
            ((VALID_PACKAGES++))
        else
            echo -e "${RED}[无效]${NC}"
            ((INVALID_PACKAGES++))
            mv "$pkg" "$pkg.invalid"
        fi
    done
    
    echo -e "${GREEN}依赖包校验完成${NC}"
    echo -e "${GREEN}有效包: $VALID_PACKAGES, 无效包: $INVALID_PACKAGES${NC}"
    
    if [ $INVALID_PACKAGES -gt 0 ]; then
        echo -e "${YELLOW}无效包已被重命名为.invalid后缀${NC}"
    fi
    
    echo ""
    show_menu
}

# 集成缺失依赖到安装包
integrate_deps() {
    echo -e "${YELLOW}将下载的依赖集成到OpenSSH安装包中...${NC}"
    
    # 检查安装包存在
    TARBALL_NAME="openssh_9.8p1_source_deps_package.tar.gz"
    if [ ! -f "$SCRIPT_DIR/$TARBALL_NAME" ]; then
        echo -e "${RED}未找到安装包: $SCRIPT_DIR/$TARBALL_NAME${NC}"
        show_menu
        return 1
    fi
    
    # 检查下载的依赖
    if [ ! -d "$DEPS_DOWNLOAD_DIR" ] || [ -z "$(ls -A "$DEPS_DOWNLOAD_DIR"/*.deb 2>/dev/null)" ]; then
        echo -e "${RED}未找到已下载的依赖或目录为空: $DEPS_DOWNLOAD_DIR${NC}"
        show_menu
        return 1
    fi
    
    echo -e "${YELLOW}解压现有安装包...${NC}"
    TEMP_DIR=$(mktemp -d)
    
    if ! tar -xzf "$SCRIPT_DIR/$TARBALL_NAME" -C "$TEMP_DIR"; then
        echo -e "${RED}解压安装包失败${NC}"
        rm -rf "$TEMP_DIR"
        show_menu
        return 1
    fi
    
    # 定位dependencies目录
    DEPS_DIR=$(find "$TEMP_DIR" -type d -name "dependencies" | head -n 1)
    
    if [ -z "$DEPS_DIR" ]; then
        echo -e "${RED}在安装包中未找到dependencies目录${NC}"
        rm -rf "$TEMP_DIR"
        show_menu
        return 1
    fi
    
    echo -e "${YELLOW}将下载的依赖复制到安装包中...${NC}"
    cp -v "$DEPS_DOWNLOAD_DIR"/*.deb "$DEPS_DIR"/ 2>/dev/null
    
    echo -e "${YELLOW}重新打包安装包...${NC}"
    PACKAGE_DIR=$(dirname "$DEPS_DIR")
    PACKAGE_NAME=$(basename "$PACKAGE_DIR")
    
    cd "$TEMP_DIR" || { echo -e "${RED}无法进入临时目录${NC}"; rm -rf "$TEMP_DIR"; return 1; }
    
    NEW_TARBALL="$SCRIPT_DIR/openssh_9.8p1_source_deps_package_updated.tar.gz"
    if tar -czf "$NEW_TARBALL" "$PACKAGE_NAME"; then
        echo -e "${GREEN}新的安装包已创建: $NEW_TARBALL${NC}"
    else
        echo -e "${RED}创建新安装包失败${NC}"
        rm -rf "$TEMP_DIR"
        show_menu
        return 1
    fi
    
    rm -rf "$TEMP_DIR"
    echo -e "${GREEN}依赖集成完成${NC}"
    echo ""
    show_menu
}

# 主程序
echo -e "${GREEN}OpenSSH 9.8p1 离线安装依赖检查与下载工具${NC}"
echo -e "${YELLOW}此工具可以帮助检查系统中缺失的依赖并在有网络环境下下载${NC}"
echo -e "${GREEN}特别说明：此工具不会升级系统SSL库，但会完全支持SSH升级到9.8p1版本${NC}"
echo -e "${YELLOW}使用方法：${NC}"
echo -e "${YELLOW}1. 在无网络环境中运行选项1检查缺失依赖${NC}"
echo -e "${YELLOW}2. 将生成的missing_deps.txt文件复制到有网络环境${NC}"
echo -e "${YELLOW}3. 在有网络环境中运行选项3下载依赖${NC}"
echo -e "${YELLOW}4. 将下载的依赖复制回无网络环境，或集成到安装包中${NC}"
echo -e ""

show_menu 