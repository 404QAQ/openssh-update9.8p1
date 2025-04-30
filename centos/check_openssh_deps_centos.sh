#!/bin/bash

# OpenSSH 9.8p1依赖检查与下载工具 (CentOS 7版本)
# 该工具会根据系统OpenSSL版本决定是否包含OpenSSL 1.1.1的依赖

# 设置颜色输出
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
DEPS_CHECK_FILE="$SCRIPT_DIR/missing_deps.txt"
DEPS_DOWNLOAD_DIR="$SCRIPT_DIR/downloaded_deps"
LOG_FILE="$SCRIPT_DIR/deps_check.log"
OPENSSL_INFO_FILE="$SCRIPT_DIR/openssl_info.txt"

# 设置安装包和源码存放路径
INSTALL_DIR="$SCRIPT_DIR/openssh_9.8p1_package"
SOURCE_DIR="$INSTALL_DIR/source"
OPENSSL_SOURCE_DIR="$INSTALL_DIR/openssl_source"
DEPS_DIR="$INSTALL_DIR/dependencies"

# OpenSSH依赖包
OPENSSH_DEPS=(
    "gcc"
    "make"
    "cmake"
    "zlib-devel"
    "pam-devel"
    "libselinux-devel"
    "krb5-devel"
    "perl"
    "wget"
    "tar"
)

# OpenSSL编译需要的依赖
OPENSSL_BUILD_DEPS=(
    "perl"
    "perl-core"
    "gcc"
    "make"
    "zlib-devel"
)

# 设置日志输出
exec > >(tee -a "$LOG_FILE") 2>&1

# 检查是否为root用户
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}错误：请使用root权限运行此脚本${NC}"
    exit 1
fi

# 函数：检查OpenSSL版本
check_openssl_version() {
    echo -e "${YELLOW}检查OpenSSL版本...${NC}"
    
    # 检查是否安装了OpenSSL
    if ! command -v openssl &> /dev/null; then
        echo -e "${YELLOW}系统未安装OpenSSL，将需要安装OpenSSL 1.1.1${NC}"
        echo "NEED_OPENSSL=yes" > "$OPENSSL_INFO_FILE"
        return 1
    fi
    
    # 获取版本信息
    OPENSSL_VERSION=$(openssl version | awk '{print $2}')
    OPENSSL_MAJOR=$(echo "$OPENSSL_VERSION" | cut -d'.' -f1)
    OPENSSL_MINOR=$(echo "$OPENSSL_VERSION" | cut -d'.' -f2)
    OPENSSL_PATCH=$(echo "$OPENSSL_VERSION" | cut -d'.' -f3 | sed 's/[^0-9].*$//')
    
    echo -e "${YELLOW}检测到OpenSSL版本: $OPENSSL_VERSION${NC}"
    
    # 检查版本是否至少为1.1.1
    if [[ "$OPENSSL_MAJOR" -gt 1 ]] || 
       [[ "$OPENSSL_MAJOR" -eq 1 && "$OPENSSL_MINOR" -gt 1 ]] || 
       [[ "$OPENSSL_MAJOR" -eq 1 && "$OPENSSL_MINOR" -eq 1 && "$OPENSSL_PATCH" -ge 1 ]]; then
        echo -e "${GREEN}当前OpenSSL版本(${OPENSSL_VERSION})已是1.1.1或更高版本，无需升级${NC}"
        echo "NEED_OPENSSL=no" > "$OPENSSL_INFO_FILE"
        return 0
    else
        echo -e "${YELLOW}当前OpenSSL版本(${OPENSSL_VERSION})低于1.1.1，需要升级${NC}"
        echo "NEED_OPENSSL=yes" > "$OPENSSL_INFO_FILE"
        return 1
    fi
}

# 函数：检查缺失的依赖
check_missing_deps() {
    echo -e "${YELLOW}检查依赖...${NC}"
    echo -e "${BLUE}依赖检查日志将保存到 $DEPS_CHECK_FILE${NC}"
    
    # 先检查OpenSSL版本
    check_openssl_version
    NEED_OPENSSL=$?
    
    # 清空缺失依赖文件
    > "$DEPS_CHECK_FILE"
    
    # 检查OpenSSH依赖
    echo -e "${YELLOW}检查OpenSSH依赖包...${NC}"
    for pkg in "${OPENSSH_DEPS[@]}"; do
        echo -e "${BLUE}检查 $pkg...${NC}"
        if ! rpm -q "$pkg" &>/dev/null; then
            echo "$pkg" >> "$DEPS_CHECK_FILE"
            echo -e "${YELLOW}缺失依赖: $pkg${NC}"
        else
            echo -e "${GREEN}已安装: $pkg${NC}"
        fi
    done
    
    # 如果需要安装OpenSSL，检查其编译依赖
    if [ "$NEED_OPENSSL" -eq 1 ]; then
        echo -e "${YELLOW}检查OpenSSL编译依赖包...${NC}"
        for pkg in "${OPENSSL_BUILD_DEPS[@]}"; do
            echo -e "${BLUE}检查 $pkg...${NC}"
            if ! rpm -q "$pkg" &>/dev/null; then
                # 检查是否已经在缺失文件中
                if ! grep -q "^$pkg$" "$DEPS_CHECK_FILE"; then
                    echo "$pkg" >> "$DEPS_CHECK_FILE"
                    echo -e "${YELLOW}缺失依赖: $pkg${NC}"
                fi
            else
                echo -e "${GREEN}已安装: $pkg${NC}"
            fi
        done
    fi
    
    # 检查缺失依赖数量
    MISSING_COUNT=$(wc -l < "$DEPS_CHECK_FILE")
    if [ "$MISSING_COUNT" -eq 0 ]; then
        echo -e "${GREEN}所有依赖已安装${NC}"
        return 0
    else
        echo -e "${YELLOW}发现 $MISSING_COUNT 个缺失的依赖${NC}"
        return 1
    fi
}

# 函数：下载缺失的依赖
download_missing_deps() {
    # 检查是否有网络连接
    if ! ping -c 1 mirrors.aliyun.com &>/dev/null && ! ping -c 1 mirrors.cloud.tencent.com &>/dev/null; then
        echo -e "${RED}错误：无法连接到网络，请确保您的网络连接正常${NC}"
        return 1
    fi
    
    # 检查是否有yum
    if ! command -v yum &>/dev/null; then
        echo -e "${RED}错误：未找到yum包管理器${NC}"
        return 1
    fi
    
    # 创建下载目录
    mkdir -p "$DEPS_DOWNLOAD_DIR"
    
    # 检查是否存在缺失依赖列表
    if [ ! -f "$DEPS_CHECK_FILE" ]; then
        echo -e "${RED}错误：未找到缺失依赖列表，请先运行依赖检查${NC}"
        return 1
    fi
    
    # 读取缺失依赖
    MISSING_COUNT=$(wc -l < "$DEPS_CHECK_FILE")
    if [ "$MISSING_COUNT" -eq 0 ]; then
        echo -e "${GREEN}没有需要下载的依赖${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}开始下载 $MISSING_COUNT 个缺失的依赖...${NC}"
    
    while IFS= read -r pkg; do
        echo -e "${BLUE}下载 $pkg 及其依赖...${NC}"
        # 使用repotrack或yumdownloader下载包及其依赖
        if command -v repotrack &>/dev/null; then
            repotrack -a x86_64 -p "$DEPS_DOWNLOAD_DIR" "$pkg"
        elif command -v yumdownloader &>/dev/null; then
            yumdownloader --resolve --destdir="$DEPS_DOWNLOAD_DIR" "$pkg"
        else
            echo -e "${RED}错误：未找到repotrack或yumdownloader工具，请先安装yum-utils${NC}"
            yum install -y yum-utils
            repotrack -a x86_64 -p "$DEPS_DOWNLOAD_DIR" "$pkg"
        fi
        
        if [ $? -ne 0 ]; then
            echo -e "${RED}下载 $pkg 失败${NC}"
        else
            echo -e "${GREEN}下载 $pkg 成功${NC}"
        fi
    done < "$DEPS_CHECK_FILE"
    
    echo -e "${GREEN}依赖下载完成，保存在 $DEPS_DOWNLOAD_DIR${NC}"
    return 0
}

# 函数：检查已下载的包的完整性
check_packages_integrity() {
    echo -e "${YELLOW}检查已下载的包的完整性...${NC}"
    
    # 检查下载目录是否存在
    if [ ! -d "$DEPS_DOWNLOAD_DIR" ]; then
        echo -e "${RED}错误：未找到下载目录 $DEPS_DOWNLOAD_DIR${NC}"
        return 1
    fi
    
    # 检查是否有RPM文件
    RPM_COUNT=$(find "$DEPS_DOWNLOAD_DIR" -name "*.rpm" | wc -l)
    if [ "$RPM_COUNT" -eq 0 ]; then
        echo -e "${RED}错误：下载目录中没有找到RPM包${NC}"
        return 1
    fi
    
    echo -e "${BLUE}开始验证 $RPM_COUNT 个RPM包...${NC}"
    
    INVALID_COUNT=0
    for rpm_file in "$DEPS_DOWNLOAD_DIR"/*.rpm; do
        echo -e "${BLUE}验证 $(basename "$rpm_file")...${NC}"
        
        # 使用rpm命令验证包的完整性
        if ! rpm -K "$rpm_file" &>/dev/null; then
            echo -e "${RED}$(basename "$rpm_file") 验证失败${NC}"
            # 重命名无效的包
            mv "$rpm_file" "${rpm_file}.invalid"
            INVALID_COUNT=$((INVALID_COUNT + 1))
        else
            echo -e "${GREEN}$(basename "$rpm_file") 验证成功${NC}"
        fi
    done
    
    if [ "$INVALID_COUNT" -eq 0 ]; then
        echo -e "${GREEN}所有RPM包验证通过${NC}"
        return 0
    else
        echo -e "${YELLOW}发现 $INVALID_COUNT 个无效的RPM包，已重命名为 .invalid${NC}"
        return 1
    fi
}

# 函数：集成依赖和源码
integrate_deps() {
    echo -e "${YELLOW}开始集成依赖和源码...${NC}"
    
    # 检查下载目录是否存在
    if [ ! -d "$DEPS_DOWNLOAD_DIR" ]; then
        echo -e "${RED}错误：未找到下载目录 $DEPS_DOWNLOAD_DIR${NC}"
        return 1
    fi
    
    # 创建集成目录
    mkdir -p "$INSTALL_DIR" "$SOURCE_DIR" "$DEPS_DIR" "$OPENSSL_SOURCE_DIR"
    
    # 复制依赖到集成目录
    echo -e "${BLUE}复制依赖包...${NC}"
    cp "$DEPS_DOWNLOAD_DIR"/*.rpm "$DEPS_DIR/" 2>/dev/null
    if [ $? -ne 0 ]; then
        echo -e "${RED}警告：复制依赖包时出现错误，可能是下载目录中没有RPM文件${NC}"
    else
        echo -e "${GREEN}依赖包复制完成${NC}"
    fi
    
    # 下载OpenSSH源码
    echo -e "${BLUE}下载OpenSSH 9.8p1源码...${NC}"
    if [ ! -f "$SOURCE_DIR/openssh-9.8p1.tar.gz" ]; then
        wget -O "$SOURCE_DIR/openssh-9.8p1.tar.gz" "https://mirrors.tuna.tsinghua.edu.cn/OpenBSD/OpenSSH/portable/openssh-9.8p1.tar.gz" || \
        wget -O "$SOURCE_DIR/openssh-9.8p1.tar.gz" "https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-9.8p1.tar.gz" || \
        wget -O "$SOURCE_DIR/openssh-9.8p1.tar.gz" "https://ftp.jaist.ac.jp/pub/OpenBSD/OpenSSH/portable/openssh-9.8p1.tar.gz"
        
        if [ $? -ne 0 ]; then
            echo -e "${RED}错误：下载OpenSSH源码失败${NC}"
            echo -e "${YELLOW}请手动下载OpenSSH 9.8p1源码到 $SOURCE_DIR/openssh-9.8p1.tar.gz${NC}"
            echo -e "${YELLOW}链接：https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-9.8p1.tar.gz${NC}"
            return 1
        else
            echo -e "${GREEN}OpenSSH源码下载完成${NC}"
        fi
    else
        echo -e "${GREEN}OpenSSH源码已存在，跳过下载${NC}"
    fi
    
    # 检查是否需要OpenSSL
    source "$OPENSSL_INFO_FILE" 2>/dev/null || NEED_OPENSSL="yes"
    
    # 如果需要OpenSSL，下载OpenSSL源码
    if [ "$NEED_OPENSSL" = "yes" ]; then
        echo -e "${BLUE}下载OpenSSL 1.1.1w源码...${NC}"
        if [ ! -f "$OPENSSL_SOURCE_DIR/openssl-1.1.1w.tar.gz" ]; then
            # 镜像列表
            MIRRORS=(
                "https://www.openssl.org/source/openssl-1.1.1w.tar.gz"
                "https://mirrors.cloud.tencent.com/openssl/source/openssl-1.1.1w.tar.gz"
                "https://mirrors.aliyun.com/openssl/source/openssl-1.1.1w.tar.gz"
                "https://mirrors.huaweicloud.com/openssl/openssl-1.1.1w.tar.gz"
                "https://gitee.com/mirrors/openssl/raw/OpenSSL_1_1_1w/openssl-1.1.1w.tar.gz"
            )
            
            DOWNLOAD_SUCCESS=false
            for mirror in "${MIRRORS[@]}"; do
                echo -e "${BLUE}尝试从 $mirror 下载...${NC}"
                if wget -O "$OPENSSL_SOURCE_DIR/openssl-1.1.1w.tar.gz" "$mirror"; then
                    DOWNLOAD_SUCCESS=true
                    echo -e "${GREEN}OpenSSL源码从 $mirror 下载成功${NC}"
                    break
                else
                    echo -e "${YELLOW}从 $mirror 下载失败，尝试下一个镜像${NC}"
                fi
            done
            
            if ! $DOWNLOAD_SUCCESS; then
                echo -e "${RED}错误：从所有镜像下载OpenSSL源码均失败${NC}"
                echo -e "${YELLOW}请手动下载OpenSSL 1.1.1w源码到 $OPENSSL_SOURCE_DIR/openssl-1.1.1w.tar.gz${NC}"
                echo -e "${YELLOW}链接：https://www.openssl.org/source/openssl-1.1.1w.tar.gz${NC}"
                return 1
            fi
        else
            echo -e "${GREEN}OpenSSL源码已存在，跳过下载${NC}"
        fi
    else
        echo -e "${GREEN}检测到系统已有OpenSSL 1.1.1或更高版本，跳过OpenSSL源码下载${NC}"
    fi
    
    # 复制OpenSSL信息文件到包目录
    cp "$OPENSSL_INFO_FILE" "$INSTALL_DIR/" 2>/dev/null
    
    # 打包整个目录
    echo -e "${BLUE}创建完整的安装包...${NC}"
    PACKAGE_NAME="openssh_9.8p1_source_deps_package_updated.tar.gz"
    tar -czf "$SCRIPT_DIR/$PACKAGE_NAME" -C "$SCRIPT_DIR" "$(basename "$INSTALL_DIR")"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}错误：创建安装包失败${NC}"
        return 1
    else
        echo -e "${GREEN}安装包创建成功：$SCRIPT_DIR/$PACKAGE_NAME${NC}"
        echo -e "${BLUE}包含以下内容：${NC}"
        echo -e "${BLUE}- OpenSSH 9.8p1源码${NC}"
        if [ "$NEED_OPENSSL" = "yes" ]; then
            echo -e "${BLUE}- OpenSSL 1.1.1w源码${NC}"
        fi
        echo -e "${BLUE}- 所有必要的依赖包${NC}"
        return 0
    fi
}

# 显示菜单
show_menu() {
    # 检查OpenSSL版本
    check_openssl_version
    NEEDS_OPENSSL=$?
    
    echo -e "${PURPLE}=== OpenSSH 9.8p1依赖检查工具（CentOS 7版本）===${NC}"
    echo -e "${YELLOW}1. 检查缺失的依赖${NC}"
    echo -e "${YELLOW}2. 下载缺失的依赖${NC}"
    echo -e "${YELLOW}3. 检查已下载的包的完整性${NC}"
    if [ "$NEEDS_OPENSSL" -eq 1 ]; then
        echo -e "${YELLOW}4. 显示当前缺失的依赖${NC}"
        echo -e "${YELLOW}5. 集成依赖和源码（包括OpenSSL 1.1.1）${NC}"
        echo -e "${BLUE}注意: 此工具将升级系统的OpenSSL库到1.1.1版本${NC}"
    else
        echo -e "${YELLOW}4. 显示当前缺失的依赖${NC}"
        echo -e "${YELLOW}5. 集成依赖和源码（使用系统现有OpenSSL）${NC}"
        echo -e "${BLUE}注意: 系统已有OpenSSL 1.1.1或更高版本，将不会升级OpenSSL${NC}"
    fi
    echo -e "${YELLOW}0. 退出${NC}"
    echo -e "${PURPLE}=======================================${NC}"
    echo -e "${BLUE}脚本目录: $SCRIPT_DIR${NC}"
    echo -e "${BLUE}依赖检查文件: $DEPS_CHECK_FILE${NC}"
    echo -e "${BLUE}下载目录: $DEPS_DOWNLOAD_DIR${NC}"
    echo -e "${BLUE}日志文件: $LOG_FILE${NC}"
    echo
}

# 主程序
while true; do
    show_menu
    read -p "请选择操作 [0-5]: " choice
    case $choice in
        1)
            check_missing_deps
            ;;
        2)
            download_missing_deps
            ;;
        3)
            check_packages_integrity
            ;;
        4)
            if [ -f "$DEPS_CHECK_FILE" ]; then
                echo -e "${BLUE}当前缺失的依赖：${NC}"
                cat "$DEPS_CHECK_FILE"
                echo
            else
                echo -e "${YELLOW}未找到依赖检查文件，请先运行依赖检查${NC}"
            fi
            ;;
        5)
            integrate_deps
            ;;
        0)
            echo -e "${GREEN}感谢使用依赖检查工具，再见！${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效的选择，请重新输入${NC}"
            ;;
    esac
    echo
    read -p "按Enter键继续..."
done 