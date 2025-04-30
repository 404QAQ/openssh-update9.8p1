#!/bin/bash

# 设置颜色输出
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# 创建目录结构 - 使用当前目录作为基础
CURRENT_DIR="$(pwd)"
PACKAGE_NAME="openssh_9.8p1_package"
mkdir -p $PACKAGE_NAME/source
mkdir -p $PACKAGE_NAME/dependencies
# scripts 和 backup 目录不再由下载脚本创建

# 设置日志文件
LOG_FILE="$CURRENT_DIR/$PACKAGE_NAME/download.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo -e "${GREEN}开始准备OpenSSH 9.8p1源码和依赖包（服务端和客户端） - 增强依赖收集${NC}"

# 检查当前目录是否已有源码包
if [ -f "$CURRENT_DIR/openssh-9.8p1.tar.gz" ]; then
    echo -e "${GREEN}发现本地OpenSSH源码包，复制到 $PACKAGE_NAME/source/ 目录${NC}"
    cp "$CURRENT_DIR/openssh-9.8p1.tar.gz" "$CURRENT_DIR/$PACKAGE_NAME/source/"
else
    # 下载OpenSSH源码
    echo -e "${YELLOW}下载OpenSSH 9.8p1源码包${NC}"
    OPENSSH_URL="https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-9.8p1.tar.gz"
    # 备用镜像
    MIRROR_URLS=(
        "https://mirrors.aliyun.com/pub/OpenBSD/OpenSSH/portable/openssh-9.8p1.tar.gz"
        "https://mirrors.tuna.tsinghua.edu.cn/OpenBSD/OpenSSH/portable/openssh-9.8p1.tar.gz"
        "https://mirrors.ustc.edu.cn/OpenBSD/OpenSSH/portable/openssh-9.8p1.tar.gz"
    )
    
    # 尝试主源
    if curl -s --connect-timeout 5 --retry 3 -o "$CURRENT_DIR/$PACKAGE_NAME/source/openssh-9.8p1.tar.gz" "$OPENSSH_URL"; then
        echo -e "${GREEN}成功从主源下载OpenSSH源码${NC}"
    else
        # 尝试镜像
        echo -e "${YELLOW}主源下载失败，尝试镜像站点${NC}"
        for mirror in "${MIRROR_URLS[@]}"; do
            echo "尝试镜像: $mirror"
            if curl -s --connect-timeout 5 --retry 3 -o "$CURRENT_DIR/$PACKAGE_NAME/source/openssh-9.8p1.tar.gz" "$mirror"; then
                echo -e "${GREEN}成功从镜像下载OpenSSH源码${NC}"
                break
            fi
        done
    fi
    
    # 检查下载是否成功
    if [ ! -f "$CURRENT_DIR/$PACKAGE_NAME/source/openssh-9.8p1.tar.gz" ]; then
        echo -e "${RED}OpenSSH源码下载失败，请手动下载并放置到 $CURRENT_DIR/$PACKAGE_NAME/source/ 目录${NC}"
        exit 1
    fi
fi

# 验证源码包
echo -e "${YELLOW}验证OpenSSH源码包完整性${NC}"
if ! tar -tzf "$CURRENT_DIR/$PACKAGE_NAME/source/openssh-9.8p1.tar.gz" &>/dev/null; then
    echo -e "${RED}源码包验证失败，可能已损坏${NC}"
    exit 1
fi
echo -e "${GREEN}源码包验证通过${NC}"

# --- 2. 增强依赖收集 --- 
echo -e "${YELLOW}开始收集依赖包（服务端和客户端）...${NC}"

# 更新包列表
apt-get update

# 定义编译和运行所需的核心包列表
# openssh-client 和 openssh-server 主要用于依赖分析，最终会被源码编译版本替代
# 包含了之前讨论的基础库和编译工具
CORE_DEPS=(
    "build-essential"
    "pkg-config"
    "autoconf"
    "automake"
    "libtool"
    "openssh-client"
    "openssh-server"
    "zlib1g-dev"
    "libssl-dev" 
    "libpam0g-dev"
    "libselinux1-dev"
    "libkrb5-dev"
    "libaudit-dev"
    "libldap2-dev"
    "libsystemd-dev"
    "libedit-dev"
    # 明确添加一些基础库
    "libc6"
    "libssl3"
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

# 临时文件存储包名
TMP_PKG_LIST=$(mktemp)
TMP_SIM_LIST=$(mktemp)
TMP_CACHE_LIST=$(mktemp)

# 方法一：使用 apt --simulate install 获取完整的依赖列表
echo -e "${YELLOW}方法一：模拟安装获取依赖列表...${NC}"
apt-get install --simulate --no-install-recommends -y ${CORE_DEPS[@]} 2>&1 | \
  grep -E "^Inst|^Conf" | awk '{print $2}' | sort -u > $TMP_SIM_LIST

# 方法二：使用 apt-cache depends --recurse 获取依赖列表
echo -e "${YELLOW}方法二：递归缓存分析获取依赖列表...${NC}"
apt-cache depends --recurse --no-recommends --no-suggests \
  --no-conflicts --no-breaks --no-replaces --no-enhances \
  --no-pre-depends ${CORE_DEPS[@]} | grep -E "^\w" | awk '{print $1}' | sort -u > $TMP_CACHE_LIST

# 合并并去重两个列表，并加入核心包自身
echo -e "${YELLOW}合并依赖列表...${NC}"
cat $TMP_SIM_LIST $TMP_CACHE_LIST <(printf "%s\n" "${CORE_DEPS[@]}") | sort -u > $TMP_PKG_LIST

FINAL_DEPS_COUNT=$(cat $TMP_PKG_LIST | wc -l)
echo -e "${GREEN}共识别出 ${FINAL_DEPS_COUNT} 个需要下载的包（包含核心包及其所有依赖）${NC}"

# --- 3. 下载依赖包 --- 
echo -e "${YELLOW}开始下载所有识别出的依赖包...${NC}"
cd "$CURRENT_DIR/$PACKAGE_NAME/dependencies" || exit 1

DOWNLOAD_SUCCESS_COUNT=0
DOWNLOAD_FAIL_COUNT=0

# 逐个下载列表中的包
while IFS= read -r package; do
    if [ -z "$package" ]; then continue; fi
    
    # 检查本地是否已存在（避免重复下载）
    # 注意：这只检查文件名，不保证版本完全匹配，但在单一运行中通常足够
    if ls ${package}_*.deb 1> /dev/null 2>&1; then
        echo -e "${YELLOW}包 $package 已存在，跳过下载${NC}"
        ((DOWNLOAD_SUCCESS_COUNT++))
        continue
    fi

    echo -e "下载: $package"
    if apt-get download "$package"; then
        ((DOWNLOAD_SUCCESS_COUNT++))
    else
        echo -e "${RED}警告：下载 $package 失败，请检查网络或包名称/版本${NC}"
        ((DOWNLOAD_FAIL_COUNT++))
    fi
done < $TMP_PKG_LIST

# 清理临时文件
rm -f $TMP_PKG_LIST $TMP_SIM_LIST $TMP_CACHE_LIST

echo -e "${GREEN}依赖包下载完成。成功: ${DOWNLOAD_SUCCESS_COUNT}，失败: ${DOWNLOAD_FAIL_COUNT}${NC}"
if [ $DOWNLOAD_FAIL_COUNT -gt 0 ]; then
    echo -e "${RED}注意：有 ${DOWNLOAD_FAIL_COUNT} 个包下载失败，可能导致离线安装时依赖不足！请检查日志并手动补充。${NC}"
fi

# 回到原始目录
cd "$CURRENT_DIR"

# 移除创建安装/恢复脚本和README的部分
echo -e "${YELLOW}跳过创建安装脚本、恢复脚本和README文件（将由用户手动提供）${NC}"

# --- 4. 打包 --- 
echo -e "${YELLOW}创建包含源码和依赖的离线包...${NC}"
cd "$CURRENT_DIR"
tar -czf "openssh_9.8p1_source_deps_package.tar.gz" "$PACKAGE_NAME"

echo -e "${GREEN}离线源码和依赖包准备完成${NC}"
echo -e "${GREEN}所有文件都在当前目录的 $PACKAGE_NAME 文件夹下${NC}"
echo -e "${GREEN}打包文件为 openssh_9.8p1_source_deps_package.tar.gz${NC}"
echo -e "${YELLOW}请将此包或目录复制到目标服务器，并手动添加 install_openssh98_offline.sh 和恢复脚本（如果需要）${NC}"

exit 0 