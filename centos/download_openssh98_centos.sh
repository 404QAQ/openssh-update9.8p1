#!/bin/bash

# OpenSSH 9.8p1 源码包和依赖下载脚本 (CentOS 7版本) - 本地执行版
# 此脚本用于在本地环境下载所需源码和依赖，生成安装包后可传输到目标服务器

# 设置颜色输出
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

# 创建临时目录和最终目录结构
TMP_DIR="$SCRIPT_DIR/tmp_download"
PACKAGE_DIR="$SCRIPT_DIR/tmp_package"
SOURCE_DIR="$PACKAGE_DIR/source"
DEPS_DIR="$PACKAGE_DIR/dependencies"
OPENSSL_SOURCE_DIR="$PACKAGE_DIR/openssl_source"

# 创建日志文件
LOG_FILE="$SCRIPT_DIR/download.log"
touch "$LOG_FILE"
echo "$(date) - 开始下载OpenSSH 9.8p1源码和依赖" > "$LOG_FILE"

# 提示用户此脚本适用于本地执行
echo -e "${YELLOW}注意：此脚本设计为在本地环境执行，生成的安装包将被传输到目标CentOS服务器${NC}"
echo -e "${YELLOW}如果您已经在目标服务器上执行此脚本，也可以继续进行${NC}"

# 检查是否为root用户，但允许非root用户执行
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${YELLOW}警告：您不是root用户，某些功能可能受限${NC}"
    echo -e "${YELLOW}建议使用sudo或root权限执行此脚本${NC}"
    echo "$(date) - 警告：非root用户执行脚本" >> "$LOG_FILE"
    
    # 询问用户是否继续
    read -p "是否继续执行？(y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${RED}已取消执行${NC}"
        exit 1
    fi
fi

# 检查网络连接 - 使用更通用的检查方式
check_network() {
    echo -e "${YELLOW}检查网络连接...${NC}"
    # 尝试连接多个常用网站以提高兼容性
    if ! ping -c 1 www.baidu.com &> /dev/null && 
       ! ping -c 1 www.google.com &> /dev/null &&
       ! ping -c 1 github.com &> /dev/null &&
       ! ping -c 1 www.openssl.org &> /dev/null; then
        echo -e "${RED}错误：无法连接到互联网，请检查网络连接${NC}"
        echo "$(date) - 错误：无法连接到互联网" >> "$LOG_FILE"
        exit 1
    fi
    echo -e "${GREEN}网络连接正常${NC}"
    echo "$(date) - 网络连接正常" >> "$LOG_FILE"
}

# 检查所需工具 - 适应多种系统
check_tools() {
    echo -e "${YELLOW}检查所需工具...${NC}"
    
    MISSING_TOOLS=()
    
    # 基本工具检查 - 将wget替换为curl
    for tool in curl tar gzip; do
        if ! command -v $tool &> /dev/null; then
            MISSING_TOOLS+=($tool)
        fi
    done
    
    # 如果有缺失工具，尝试安装
    if [ ${#MISSING_TOOLS[@]} -ne 0 ]; then
        echo -e "${YELLOW}缺少以下工具: ${MISSING_TOOLS[*]}${NC}"
        
        # 根据系统类型使用不同的包管理器
        if command -v apt-get &> /dev/null; then
            echo -e "${YELLOW}检测到Debian/Ubuntu系统，尝试安装缺失工具...${NC}"
            sudo apt-get update -y >> "$LOG_FILE" 2>&1
            sudo apt-get install -y ${MISSING_TOOLS[@]} >> "$LOG_FILE" 2>&1
        elif command -v yum &> /dev/null; then
            echo -e "${YELLOW}检测到CentOS/RHEL系统，尝试安装缺失工具...${NC}"
            sudo yum install -y ${MISSING_TOOLS[@]} >> "$LOG_FILE" 2>&1
        elif command -v dnf &> /dev/null; then
            echo -e "${YELLOW}检测到Fedora系统，尝试安装缺失工具...${NC}"
            sudo dnf install -y ${MISSING_TOOLS[@]} >> "$LOG_FILE" 2>&1
        elif command -v brew &> /dev/null; then
            echo -e "${YELLOW}检测到macOS系统，尝试使用Homebrew安装缺失工具...${NC}"
            brew install ${MISSING_TOOLS[@]} >> "$LOG_FILE" 2>&1
        else
            echo -e "${RED}无法确定系统类型或包管理器，请手动安装以下工具: ${MISSING_TOOLS[*]}${NC}"
            echo "$(date) - 错误：无法自动安装缺失工具" >> "$LOG_FILE"
            exit 1
        fi
        
        # 再次检查工具是否已安装
        for tool in ${MISSING_TOOLS[@]}; do
            if ! command -v $tool &> /dev/null; then
                echo -e "${RED}错误：安装 $tool 失败，请手动安装${NC}"
                echo "$(date) - 错误：安装 $tool 失败" >> "$LOG_FILE"
                exit 1
            fi
        done
    fi
    
    echo -e "${GREEN}所需基本工具已准备就绪${NC}"
    echo "$(date) - 所需基本工具已准备就绪" >> "$LOG_FILE"
    
    # 仅检查yumdownloader，不强制安装
    if command -v yumdownloader &> /dev/null; then
        echo -e "${GREEN}已安装yumdownloader，将用于下载RPM包依赖${NC}"
    else
        echo -e "${YELLOW}未找到yumdownloader，将使用备用方法下载依赖${NC}"
        echo -e "${YELLOW}注意：如果这是非CentOS/RHEL系统，缺少yumdownloader是正常的${NC}"
        echo "$(date) - 未找到yumdownloader，将使用备用方法" >> "$LOG_FILE"
    fi
}

# 清理旧文件和目录
cleanup_old_files() {
    echo -e "${YELLOW}清理旧文件和目录...${NC}"
    
    if [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
    
    if [ -d "$PACKAGE_DIR" ]; then
        rm -rf "$PACKAGE_DIR"
    fi
    
    mkdir -p "$TMP_DIR"
    mkdir -p "$SOURCE_DIR"
    mkdir -p "$DEPS_DIR"
    mkdir -p "$OPENSSL_SOURCE_DIR"
    mkdir -p "$PACKAGE_DIR/scripts"
    
    echo -e "${GREEN}目录准备完成${NC}"
    echo "$(date) - 目录准备完成" >> "$LOG_FILE"
}

# 下载文件的通用函数，使用curl代替wget
download_file() {
    local url=$1
    local output_file=$2
    local desc=$3
    
    echo -e "${YELLOW}下载${desc}...${NC}"
    
    # 使用curl下载文件，添加重试和进度条
    if curl -L --retry 3 --retry-delay 3 --connect-timeout 30 -# -o "${output_file}" "${url}"; then
        echo -e "${GREEN}下载完成${NC}"
    else
        echo -e "${RED}下载失败: ${url}${NC}"
        return 1
    fi
    
    # 检查文件是否成功下载
    if [ -f "${output_file}" ] && [ -s "${output_file}" ]; then
        return 0
    else
        echo -e "${RED}下载失败：文件为空或不存在${NC}"
        return 1
    fi
}

# 下载OpenSSH源码
download_openssh_source() {
    echo -e "${YELLOW}下载OpenSSH 9.8p1源码...${NC}"
    
    # 尝试直接从官方网站下载
    if download_file "https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-9.8p1.tar.gz" "$SOURCE_DIR/openssh-9.8p1.tar.gz" "OpenSSH源码"; then
        echo -e "${GREEN}OpenSSH 9.8p1源码下载完成${NC}"
    else
        # 尝试备用站点
        echo -e "${YELLOW}从官方站点下载失败，尝试备用站点...${NC}"
        if download_file "https://mirrors.tuna.tsinghua.edu.cn/OpenBSD/OpenSSH/portable/openssh-9.8p1.tar.gz" "$SOURCE_DIR/openssh-9.8p1.tar.gz" "OpenSSH源码(备用)"; then
            echo -e "${GREEN}OpenSSH 9.8p1源码(备用站点)下载完成${NC}"
        else
            echo -e "${RED}错误：无法下载OpenSSH源码${NC}"
            echo "$(date) - 错误：无法下载OpenSSH源码" >> "$LOG_FILE"
            exit 1
        fi
    fi
    
    echo "$(date) - OpenSSH 9.8p1源码下载完成" >> "$LOG_FILE"
}

# 下载OpenSSL源码
download_openssl_source() {
    echo -e "${YELLOW}下载OpenSSL 1.1.1w源码...${NC}"
    
    # 尝试从官方网站下载
    if download_file "https://www.openssl.org/source/openssl-1.1.1w.tar.gz" "$OPENSSL_SOURCE_DIR/openssl-1.1.1w.tar.gz" "OpenSSL源码"; then
        echo -e "${GREEN}OpenSSL 1.1.1w源码下载完成${NC}"
    else
        # 尝试备用站点
        echo -e "${YELLOW}从官方站点下载失败，尝试备用站点...${NC}"
        if download_file "https://mirrors.tuna.tsinghua.edu.cn/openssl/source/openssl-1.1.1w.tar.gz" "$OPENSSL_SOURCE_DIR/openssl-1.1.1w.tar.gz" "OpenSSL源码(备用)"; then
            echo -e "${GREEN}OpenSSL 1.1.1w源码(备用站点)下载完成${NC}"
        else
            echo -e "${RED}错误：无法下载OpenSSL源码${NC}"
            echo "$(date) - 错误：无法下载OpenSSL源码" >> "$LOG_FILE"
            exit 1
        fi
    fi
    
    echo "$(date) - OpenSSL 1.1.1w源码下载完成" >> "$LOG_FILE"
}

# 检查当前环境是否为CentOS/RHEL
check_current_system() {
    if [ -f /etc/redhat-release ]; then
        echo -e "${GREEN}检测到CentOS/RHEL系统${NC}"
        IS_CENTOS=true
        
        # 检查当前OpenSSL版本
        if command -v openssl &> /dev/null; then
            OPENSSL_VERSION=$(openssl version | awk '{print $2}')
            echo -e "${YELLOW}当前系统OpenSSL版本: $OPENSSL_VERSION${NC}"
            
            # 解析版本号
            OPENSSL_MAJOR=$(echo "$OPENSSL_VERSION" | cut -d'.' -f1)
            OPENSSL_MINOR=$(echo "$OPENSSL_VERSION" | cut -d'.' -f2)
            OPENSSL_PATCH=$(echo "$OPENSSL_VERSION" | cut -d'.' -f3 | sed 's/[^0-9].*$//')
            
            # 检查版本是否至少为1.1.1
            if [[ "$OPENSSL_MAJOR" -gt 1 ]] || 
               [[ "$OPENSSL_MAJOR" -eq 1 && "$OPENSSL_MINOR" -gt 1 ]] || 
               [[ "$OPENSSL_MAJOR" -eq 1 && "$OPENSSL_MINOR" -eq 1 && "$OPENSSL_PATCH" -ge 1 ]]; then
                echo -e "${GREEN}当前OpenSSL版本(${OPENSSL_VERSION})已是1.1.1或更高版本，不需要升级${NC}"
                NEED_OPENSSL="no"
            else
                echo -e "${YELLOW}当前OpenSSL版本(${OPENSSL_VERSION})低于1.1.1，将包含OpenSSL升级${NC}"
                NEED_OPENSSL="yes"
            fi
        else
            echo -e "${YELLOW}未检测到OpenSSL，将包含OpenSSL安装${NC}"
            NEED_OPENSSL="yes"
        fi
    else
        echo -e "${YELLOW}当前系统不是CentOS/RHEL，但仍然可以下载所需文件${NC}"
        echo -e "${YELLOW}将默认包含OpenSSL 1.1.1w源码${NC}"
        IS_CENTOS=false
        NEED_OPENSSL="yes"
    fi
    
    # 记录OpenSSL需求状态
    echo "NEED_OPENSSL=\"$NEED_OPENSSL\"" > "$PACKAGE_DIR/openssl_info.txt"
    echo "$(date) - OpenSSL状态: NEED_OPENSSL=$NEED_OPENSSL" >> "$LOG_FILE"
}

# 下载CentOS依赖包 - 仅在CentOS/RHEL系统上尝试
download_centos_dependencies() {
    echo -e "${YELLOW}下载CentOS依赖包...${NC}"
    
    # 如果当前系统是CentOS/RHEL并且有yumdownloader，则尝试下载依赖
    if $IS_CENTOS && command -v yumdownloader &> /dev/null; then
        echo -e "${GREEN}在CentOS/RHEL系统上使用yumdownloader下载依赖${NC}"
        
        # 基本编译工具和库
        BUILD_DEPS="gcc make zlib-devel pam-devel libselinux-devel krb5-devel perl"
        
        # OpenSSL编译依赖
        OPENSSL_DEPS=""
        if [ "$NEED_OPENSSL" = "yes" ]; then
            OPENSSL_DEPS="perl-core zlib-devel"
        fi
        
        # 合并所有依赖
        ALL_DEPS="$BUILD_DEPS $OPENSSL_DEPS"
        
        # 使用yumdownloader下载依赖
        cd "$DEPS_DIR" || {
            echo -e "${RED}无法切换到依赖目录${NC}"
            echo "$(date) - 错误：无法切换到依赖目录" >> "$LOG_FILE"
            exit 1
        }
        
        for pkg in $ALL_DEPS; do
            echo -e "${YELLOW}下载 $pkg 及其依赖...${NC}"
            yumdownloader --resolve "$pkg" >> "$LOG_FILE" 2>&1
            if [ $? -ne 0 ]; then
                echo -e "${YELLOW}使用yumdownloader下载 $pkg 失败，尝试使用yum...${NC}"
                yum install -y --downloadonly --downloaddir="$DEPS_DIR" "$pkg" >> "$LOG_FILE" 2>&1
                if [ $? -ne 0 ]; then
                    echo -e "${RED}警告：无法下载 $pkg 及其依赖${NC}"
                    echo "$(date) - 警告：无法下载 $pkg" >> "$LOG_FILE"
                fi
            fi
        done
        
        # 确认依赖下载情况
        DEPS_COUNT=$(ls -1 "$DEPS_DIR"/*.rpm 2>/dev/null | wc -l)
        if [ "$DEPS_COUNT" -eq 0 ]; then
            echo -e "${YELLOW}警告：未能下载任何依赖包，这可能会影响离线安装${NC}"
            echo "$(date) - 警告：未能下载任何依赖包" >> "$LOG_FILE"
        else
            echo -e "${GREEN}成功下载 $DEPS_COUNT 个依赖包${NC}"
            echo "$(date) - 成功下载 $DEPS_COUNT 个依赖包" >> "$LOG_FILE"
        fi
    else
        # 非CentOS系统或没有yumdownloader，提供依赖列表
        echo -e "${YELLOW}当前系统不是CentOS/RHEL或未找到yumdownloader${NC}"
        echo -e "${YELLOW}创建依赖列表文件供参考...${NC}"
        
        cat > "$DEPS_DIR/dependency_list.txt" << EOF
# CentOS/RHEL 7 所需依赖清单
# 请确保目标服务器安装了以下包：

# 基础编译工具
gcc
make
perl

# 开发库
zlib-devel
pam-devel
libselinux-devel
krb5-devel

# OpenSSL相关依赖（如需编译OpenSSL 1.1.1）
perl-core
zlib-devel

# 在目标服务器上，可以使用以下命令安装上述依赖：
# yum install -y gcc make perl zlib-devel pam-devel libselinux-devel krb5-devel perl-core
EOF
        
        echo -e "${YELLOW}依赖列表已保存到 $DEPS_DIR/dependency_list.txt${NC}"
        echo -e "${YELLOW}请参考此文件在目标服务器上安装必要的依赖${NC}"
        echo "$(date) - 创建依赖列表文件" >> "$LOG_FILE"
    fi
}

# 拷贝相关脚本到包目录
copy_scripts() {
    echo -e "${YELLOW}拷贝安装和恢复脚本...${NC}"
    
    # 拷贝安装脚本
    if [ -f "$SCRIPT_DIR/install_openssh98_offline_centos.sh" ]; then
        cp "$SCRIPT_DIR/install_openssh98_offline_centos.sh" "$PACKAGE_DIR/scripts/"
        chmod +x "$PACKAGE_DIR/scripts/install_openssh98_offline_centos.sh"
        echo -e "${GREEN}复制安装脚本成功${NC}"
    else
        echo -e "${YELLOW}未找到安装脚本，将创建基本脚本...${NC}"
        # 创建简单的安装脚本提示
        cat > "$PACKAGE_DIR/scripts/install_openssh98_offline_centos.sh" << 'EOF'
#!/bin/bash
echo "请使用centos目录下的install_openssh98_offline_centos.sh脚本进行安装"
echo "如果没有此脚本，请从项目仓库获取"
EOF
        chmod +x "$PACKAGE_DIR/scripts/install_openssh98_offline_centos.sh"
    fi
    
    # 拷贝恢复脚本
    if [ -f "$SCRIPT_DIR/restore_openssh_centos.sh" ]; then
        cp "$SCRIPT_DIR/restore_openssh_centos.sh" "$PACKAGE_DIR/scripts/"
        chmod +x "$PACKAGE_DIR/scripts/restore_openssh_centos.sh"
        echo -e "${GREEN}复制恢复脚本成功${NC}"
    else
        echo -e "${YELLOW}未找到恢复脚本，将创建基本脚本...${NC}"
        cat > "$PACKAGE_DIR/scripts/restore_openssh_centos.sh" << 'EOF'
#!/bin/bash
echo "请使用centos目录下的restore_openssh_centos.sh脚本进行恢复"
echo "如果没有此脚本，请从项目仓库获取"
EOF
        chmod +x "$PACKAGE_DIR/scripts/restore_openssh_centos.sh"
    fi
    
    # 创建README文件
    cat > "$PACKAGE_DIR/README.txt" << EOF
OpenSSH 9.8p1 离线安装包 (CentOS/RHEL)

本安装包包含：
1. OpenSSH 9.8p1 源码（位于source目录）
2. OpenSSL 1.1.1w 源码（位于openssl_source目录）
3. 安装和恢复脚本（位于scripts目录）
4. CentOS/RHEL依赖包（位于dependencies目录，如果在CentOS系统上创建）

使用方法：
1. 将此安装包传输到目标CentOS/RHEL服务器
2. 解压安装包：tar -xzf openssh_9.8p1_source_deps_package.tar.gz
3. 进入解压后的目录并执行安装脚本：
   cd openssh_9.8p1_package
   sudo ./scripts/install_openssh98_offline_centos.sh

注意事项：
- 安装前会自动备份原有SSH配置和二进制文件
- 安装完成后请在新的终端窗口测试SSH连接
- 如果安装失败，可以使用恢复脚本恢复原来的安装：
  sudo ./scripts/restore_openssh_centos.sh

EOF
    
    echo -e "${GREEN}相关脚本和文档已准备完成${NC}"
    echo "$(date) - 脚本和文档准备完成" >> "$LOG_FILE"
}

# 创建最终安装包
create_final_package() {
    echo -e "${YELLOW}创建最终安装包...${NC}"
    
    # 从当前目录创建安装包
    cd "$SCRIPT_DIR" || {
        echo -e "${RED}无法返回脚本目录${NC}"
        echo "$(date) - 错误：无法返回脚本目录" >> "$LOG_FILE"
        exit 1
    }
    
    # 创建安装包
    echo -e "${YELLOW}打包文件...${NC}"
    tar -czf "$SCRIPT_DIR/openssh_9.8p1_source_deps_package.tar.gz" -C "$SCRIPT_DIR" tmp_package || {
        echo -e "${RED}创建安装包失败${NC}"
        echo "$(date) - 错误：创建安装包失败" >> "$LOG_FILE"
        exit 1
    }
    
    # 重命名tmp_package为openssh_9.8p1_package以便后续利用
    mv "$PACKAGE_DIR" "$SCRIPT_DIR/openssh_9.8p1_package"
    
    echo -e "${GREEN}安装包创建成功: $SCRIPT_DIR/openssh_9.8p1_source_deps_package.tar.gz${NC}"
    echo "$(date) - 安装包创建成功" >> "$LOG_FILE"
}

# 清理临时文件
cleanup_temp_files() {
    echo -e "${YELLOW}清理临时文件...${NC}"
    
    if [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
        echo -e "${GREEN}清理临时目录成功${NC}"
        echo "$(date) - 清理临时目录成功" >> "$LOG_FILE"
    fi
}

# 创建使用说明
show_usage_guide() {
    echo -e "\n${GREEN}=== 使用指南 ===${NC}"
    echo -e "${YELLOW}您已成功创建OpenSSH 9.8p1离线安装包：${NC}"
    echo -e "${GREEN}$SCRIPT_DIR/openssh_9.8p1_source_deps_package.tar.gz${NC}"
    
    echo -e "\n${YELLOW}接下来步骤：${NC}"
    echo -e "1. 将安装包传输到目标CentOS/RHEL服务器，例如：${GREEN}scp openssh_9.8p1_source_deps_package.tar.gz user@server:/path/to/destination/${NC}"
    echo -e "2. 在目标服务器上解压安装包：${GREEN}tar -xzf openssh_9.8p1_source_deps_package.tar.gz${NC}"
    echo -e "3. 进入解压后的目录：${GREEN}cd openssh_9.8p1_package${NC}"
    echo -e "4. 执行安装脚本：${GREEN}sudo ./scripts/install_openssh98_offline_centos.sh${NC}"
    
    echo -e "\n${YELLOW}注意事项：${NC}"
    echo -e "- 安装前请确保已备份重要数据"
    echo -e "- 安装需要root权限"
    echo -e "- 如果安装失败，使用恢复脚本：${GREEN}sudo ./scripts/restore_openssh_centos.sh${NC}"
    echo -e "- 安装日志保存在install.log文件中"
    
    echo -e "\n${GREEN}更多详情请参考安装包中的README.txt文件${NC}"
}

# 主程序开始
echo -e "${GREEN}======= OpenSSH 9.8p1 下载脚本 (本地执行版) =======${NC}"
echo -e "${YELLOW}此脚本适用于本地环境，生成的安装包可传输到目标CentOS服务器${NC}"
echo -e "${YELLOW}当前使用curl替代wget下载文件，更好兼容macOS和其他系统${NC}"

# 检查网络连接
check_network

# 检查所需工具
check_tools

# 清理旧文件和目录
cleanup_old_files

# 检查当前系统类型
check_current_system

# 下载OpenSSH源码
download_openssh_source

# 下载OpenSSL源码
download_openssl_source

# 尝试下载CentOS依赖
download_centos_dependencies

# 拷贝相关脚本到包目录
copy_scripts

# 创建最终安装包
create_final_package

# 清理临时文件
cleanup_temp_files

# 显示使用指南
show_usage_guide

echo -e "\n${GREEN}安装包创建完成！${NC}"
echo "$(date) - 下载脚本执行完成" >> "$LOG_FILE"

exit 0 