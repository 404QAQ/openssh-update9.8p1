#!/bin/bash

# 设置颜色输出
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ORIGINAL_TARBALL_NAME="openssh_9.8p1_source_deps_package.tar.gz"
UPDATED_TARBALL_NAME="openssh_9.8p1_source_deps_package_updated.tar.gz"
PACKAGE_EXTRACT_DIR="openssh_9.8p1_package"

# 设置日志文件 (在脚本所在目录下)
LOG_FILE="$SCRIPT_DIR/install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# 检查是否为root用户
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}错误：请使用root权限运行此脚本${NC}"
    exit 1
fi

echo -e "${GREEN}开始离线安装OpenSSH 9.8p1（服务端和客户端）${NC}"
echo -e "${YELLOW}脚本运行目录: $SCRIPT_DIR${NC}"

# --- 1. 检查并解压源码和依赖包 ---
echo -e "${YELLOW}检查并解压源码和依赖包...${NC}"

# 首先尝试查找更新版本的包
if [ -f "$SCRIPT_DIR/$UPDATED_TARBALL_NAME" ]; then
    echo -e "${GREEN}找到更新版本的依赖包: $UPDATED_TARBALL_NAME${NC}"
    TARBALL_NAME="$UPDATED_TARBALL_NAME"
elif [ -f "$SCRIPT_DIR/$ORIGINAL_TARBALL_NAME" ]; then
    echo -e "${YELLOW}找到原始依赖包: $ORIGINAL_TARBALL_NAME${NC}"
    TARBALL_NAME="$ORIGINAL_TARBALL_NAME"
else
    echo -e "${RED}错误：未在脚本目录找到源码依赖包 $UPDATED_TARBALL_NAME 或 $ORIGINAL_TARBALL_NAME ${NC}"
    exit 1
fi

# 解压到当前目录（脚本所在目录）
if ! tar -xzf "$SCRIPT_DIR/$TARBALL_NAME" -C "$SCRIPT_DIR"; then
    echo -e "${RED}错误：解压 $TARBALL_NAME 失败${NC}"
    exit 1
fi
echo -e "${GREEN}源码和依赖包解压完成到 $SCRIPT_DIR/$PACKAGE_EXTRACT_DIR ${NC}"

# --- 2. 定义路径 ---
PACKAGE_DIR="$SCRIPT_DIR/$PACKAGE_EXTRACT_DIR"
SOURCE_DIR="$PACKAGE_DIR/source"
DEPENDENCIES_DIR="$PACKAGE_DIR/dependencies"
BACKUP_DIR="$PACKAGE_DIR/backup/openssh-backup-$(date +%Y%m%d-%H%M%S)"

# 确保备份目录存在 (在解压后的包内)
mkdir -p $BACKUP_DIR

# 检查解压后的源码包是否存在
if [ ! -f "$SOURCE_DIR/openssh-9.8p1.tar.gz" ]; then
    echo -e "${RED}错误：解压后未找到OpenSSH源码包 $SOURCE_DIR/openssh-9.8p1.tar.gz ${NC}"
    exit 1
fi

# --- 3. 验证目标系统环境 ---
echo -e "${YELLOW}验证系统环境...${NC}"
if [ ! -f /etc/lsb-release ] || ! grep -q "Ubuntu 22.04" /etc/lsb-release; then
    echo -e "${YELLOW}警告：系统可能不是Ubuntu 22.04 LTS，继续安装可能会有兼容性问题${NC}"
    read -p "是否继续安装？(y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${RED}安装已取消${NC}"
        exit 1
    fi
fi

# --- 4. 备份当前OpenSSH安装 ---
echo -e "${YELLOW}备份当前OpenSSH安装到 $BACKUP_DIR ...${NC}"

# 备份配置文件
echo -e "${YELLOW}备份配置文件...${NC}"
cp -a /etc/ssh $BACKUP_DIR/
[ $? -eq 0 ] && echo -e "${GREEN}配置文件备份完成${NC}" || echo -e "${RED}配置文件备份失败${NC}"

# 获取当前SSH版本信息
CURRENT_SSH_VERSION=$(ssh -V 2>&1)
echo -e "${YELLOW}当前SSH版本: $CURRENT_SSH_VERSION${NC}"
echo "$CURRENT_SSH_VERSION" > $BACKUP_DIR/version_info.txt

# 备份当前安装的openssh包列表
dpkg -l | grep openssh > $BACKUP_DIR/openssh_packages.txt

# 备份SSH服务端和客户端二进制文件
echo -e "${YELLOW}备份SSH服务端和客户端可执行文件...${NC}"
# 服务端
which sshd >/dev/null 2>&1 && cp $(which sshd) $BACKUP_DIR/
# 客户端
which ssh >/dev/null 2>&1 && cp $(which ssh) $BACKUP_DIR/
which ssh-keygen >/dev/null 2>&1 && cp $(which ssh-keygen) $BACKUP_DIR/
which ssh-agent >/dev/null 2>&1 && cp $(which ssh-agent) $BACKUP_DIR/
which ssh-add >/dev/null 2>&1 && cp $(which ssh-add) $BACKUP_DIR/
which ssh-copy-id >/dev/null 2>&1 && cp $(which ssh-copy-id) $BACKUP_DIR/
which sftp >/dev/null 2>&1 && cp $(which sftp) $BACKUP_DIR/
which scp >/dev/null 2>&1 && cp $(which scp) $BACKUP_DIR/

# 备份系统文件
if [ -f /lib/systemd/system/ssh.service ]; then
    mkdir -p $BACKUP_DIR/systemd
    cp /lib/systemd/system/ssh.service $BACKUP_DIR/systemd/
fi

# 添加恢复步骤记录
echo -e "${YELLOW}记录恢复信息...${NC}"
cat > $BACKUP_DIR/restore_info.txt << EOF
备份时间: $(date)
备份目录: $BACKUP_DIR
SSH版本: $CURRENT_SSH_VERSION
EOF

# 复制恢复脚本到备份目录（假设恢复脚本与安装脚本在同一目录）
RESTORE_SCRIPT_NAME="restore_openssh.sh"
if [ -f "$SCRIPT_DIR/$RESTORE_SCRIPT_NAME" ]; then
    cp "$SCRIPT_DIR/$RESTORE_SCRIPT_NAME" "$BACKUP_DIR/"
    echo -e "${GREEN}已将恢复脚本 $RESTORE_SCRIPT_NAME 复制到备份目录${NC}"
else
    echo -e "${YELLOW}警告：未在脚本目录 $SCRIPT_DIR 找到恢复脚本 $RESTORE_SCRIPT_NAME，将无法自动复制到备份目录${NC}"
fi

# --- 5. 安装依赖 ---
echo -e "${YELLOW}安装依赖包...${NC}"
cd "$DEPENDENCIES_DIR" || { echo -e "${RED}错误：无法进入依赖目录 $DEPENDENCIES_DIR ${NC}"; exit 1; }
dpkg -i *.deb 2>/dev/null || {
    echo -e "${YELLOW}某些包安装失败，尝试修复依赖...${NC}"
    # 修改：使用--no-download选项确保apt-get不会尝试从网络下载
    apt-get -f install -y --no-download || {
        echo -e "${RED}警告：自动修复依赖失败，在无网络环境下这是正常的${NC}"
        echo -e "${YELLOW}尝试强制安装所有依赖包...${NC}"
        dpkg --force-all -i *.deb || {
            echo -e "${RED}安装依赖失败，请确保所有必要的依赖包都已包含在离线包中${NC}"
            echo -e "${YELLOW}查看日志文件 $LOG_FILE 了解具体错误${NC}"
            exit 1
        }
    }
    echo -e "${YELLOW}重新尝试安装依赖...${NC}"
    dpkg -i *.deb || {
        echo -e "${RED}安装依赖失败，请手动解决依赖问题${NC}"
        exit 1
    }
}
echo -e "${GREEN}依赖包安装完成${NC}"
cd "$SCRIPT_DIR" # 返回脚本目录

# --- 6. 编译和安装OpenSSH ---
echo -e "${YELLOW}编译并安装OpenSSH 9.8p1...${NC}"
TEMP_BUILD_DIR="/tmp/openssh-build-$$" # 使用临时目录
mkdir -p "$TEMP_BUILD_DIR"
echo -e "${YELLOW}解压源码到临时目录 $TEMP_BUILD_DIR ${NC}"
tar -xzf "$SOURCE_DIR/openssh-9.8p1.tar.gz" -C "$TEMP_BUILD_DIR"
cd "$TEMP_BUILD_DIR/openssh-9.8p1" || { echo -e "${RED}错误：无法进入源码目录 $TEMP_BUILD_DIR/openssh-9.8p1 ${NC}"; rm -rf "$TEMP_BUILD_DIR"; exit 1; }

# 检查系统已有的SSL库版本和位置
SSL_LIB_PATH=$(find /lib /usr/lib -name "libssl.so*" | head -n 1)
SSL_VERSION=""
SSL_INCLUDE_PATH=""
SSL_LIB_DIR=""

if [ -n "$SSL_LIB_PATH" ]; then
    SSL_VERSION=$(strings "$SSL_LIB_PATH" | grep -oE "OpenSSL [0-9]+\.[0-9]+\.[0-9]+[a-z]?" | head -n 1)
    SSL_LIB_DIR=$(dirname "$SSL_LIB_PATH")
    echo -e "${YELLOW}检测到系统SSL库: $SSL_VERSION ($SSL_LIB_PATH)${NC}"
    
    # 查找系统SSL头文件位置
    for dir in "/usr/include/openssl" "/usr/local/include/openssl" "/usr/include/x86_64-linux-gnu/openssl"; do
        if [ -d "$dir" ] && [ -f "$dir/ssl.h" ]; then
            SSL_INCLUDE_PATH=$(dirname "$dir")
            echo -e "${GREEN}找到系统SSL头文件: $SSL_INCLUDE_PATH${NC}"
            break
        fi
    done
    
    echo -e "${GREEN}将使用系统已有的SSL库编译OpenSSH，不会影响系统SSL库${NC}"
else
    echo -e "${YELLOW}无法检测到系统SSL库，将使用系统默认路径${NC}"
fi

# 构建configure命令，明确指定SSL库位置
CONFIGURE_CMD="./configure --prefix=/usr \
            --sysconfdir=/etc/ssh \
            --with-md5-passwords \
            --with-privsep-path=/var/lib/sshd \
            --with-pam \
            --with-selinux \
            --with-kerberos5 \
            --with-ssl-engine \
            --with-systemd \
            --without-openssl-header-check"  # 避免严格检查OpenSSL头文件

# 如果找到了SSL库和头文件，明确指定它们的位置
if [ -n "$SSL_LIB_DIR" ] && [ -n "$SSL_INCLUDE_PATH" ]; then
    CONFIGURE_CMD="$CONFIGURE_CMD --with-ssl-dir=$SSL_INCLUDE_PATH"
    echo -e "${GREEN}明确指定系统SSL库路径: $SSL_INCLUDE_PATH${NC}"
    echo -e "${YELLOW}这将确保OpenSSH使用系统现有SSL库而不尝试升级它${NC}"
fi

echo -e "${YELLOW}执行配置命令: $CONFIGURE_CMD${NC}"
eval "$CONFIGURE_CMD"

# 编译
echo -e "${YELLOW}编译OpenSSH...${NC}"
if ! make -j$(nproc); then
    echo -e "${RED}编译失败，请检查日志 $LOG_FILE ${NC}"
    rm -rf "$TEMP_BUILD_DIR"
    exit 1
fi

# 停止SSH服务
echo -e "${YELLOW}停止SSH服务...${NC}"
systemctl stop ssh || service ssh stop

# 备份旧的二进制文件（以防刚才没有正确备份）
echo -e "${YELLOW}备份现有SSH二进制文件...${NC}"
# 服务端
[ -f /usr/sbin/sshd ] && mv /usr/sbin/sshd /usr/sbin/sshd.bak_$(date +%s)
# 客户端
[ -f /usr/bin/ssh ] && mv /usr/bin/ssh /usr/bin/ssh.bak_$(date +%s)
[ -f /usr/bin/ssh-keygen ] && mv /usr/bin/ssh-keygen /usr/bin/ssh-keygen.bak_$(date +%s)
[ -f /usr/bin/ssh-agent ] && mv /usr/bin/ssh-agent /usr/bin/ssh-agent.bak_$(date +%s)
[ -f /usr/bin/ssh-add ] && mv /usr/bin/ssh-add /usr/bin/ssh-add.bak_$(date +%s)
[ -f /usr/bin/sftp ] && mv /usr/bin/sftp /usr/bin/sftp.bak_$(date +%s)
[ -f /usr/bin/scp ] && mv /usr/bin/scp /usr/bin/scp.bak_$(date +%s)

# 安装
echo -e "${YELLOW}安装OpenSSH（服务端和客户端）...${NC}"
if ! make install; then
    echo -e "${RED}安装失败，请检查日志 $LOG_FILE ${NC}"
    echo -e "${YELLOW}尝试恢复旧的二进制文件...${NC}"
    # 简单的恢复尝试
    ls /usr/sbin/sshd.bak_* | sort -r | head -n 1 | xargs -I {} mv {} /usr/sbin/sshd 2>/dev/null
    ls /usr/bin/ssh.bak_* | sort -r | head -n 1 | xargs -I {} mv {} /usr/bin/ssh 2>/dev/null
    ls /usr/bin/ssh-keygen.bak_* | sort -r | head -n 1 | xargs -I {} mv {} /usr/bin/ssh-keygen 2>/dev/null
    ls /usr/bin/ssh-agent.bak_* | sort -r | head -n 1 | xargs -I {} mv {} /usr/bin/ssh-agent 2>/dev/null
    ls /usr/bin/ssh-add.bak_* | sort -r | head -n 1 | xargs -I {} mv {} /usr/bin/ssh-add 2>/dev/null
    ls /usr/bin/sftp.bak_* | sort -r | head -n 1 | xargs -I {} mv {} /usr/bin/sftp 2>/dev/null
    ls /usr/bin/scp.bak_* | sort -r | head -n 1 | xargs -I {} mv {} /usr/bin/scp 2>/dev/null
    systemctl start ssh || service ssh start
    rm -rf "$TEMP_BUILD_DIR"
    exit 1
fi

# --- 7. 后续配置 ---
echo -e "${YELLOW}处理配置文件...${NC}"
if [ -f /etc/ssh/sshd_config.orig ]; then
    echo -e "${YELLOW}发现已存在的 .orig 配置文件，跳过复制${NC}"
elif [ -f /etc/ssh/sshd_config ]; then
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.orig
    echo -e "${GREEN}已备份原始 sshd_config 为 sshd_config.orig ${NC}"
else
    echo -e "${YELLOW}未找到 sshd_config 文件，跳过备份${NC}"
fi
# 这里保留原配置不变，make install 通常会处理新配置模板

# 确保私有分离目录存在
mkdir -p /var/lib/sshd
chmod 0755 /var/lib/sshd

# 更新systemd服务文件（如果需要）
if [ -f /lib/systemd/system/ssh.service ]; then
    echo -e "${YELLOW}检查并更新 systemd 服务文件...${NC}"
    # 备份原服务文件
    if [ ! -f /lib/systemd/system/ssh.service.bak ]; then
       cp /lib/systemd/system/ssh.service /lib/systemd/system/ssh.service.bak
    fi
    
    # 检查并更新服务文件中的路径（如果需要）
    if ! grep -q "ExecStart=/usr/sbin/sshd" /lib/systemd/system/ssh.service; then
        sed -i 's|^ExecStart=.*|ExecStart=/usr/sbin/sshd -D $SSHD_OPTS|' /lib/systemd/system/ssh.service
        echo -e "${GREEN}已更新 systemd 服务文件中的 ExecStart 路径${NC}"
    fi
    
    # 重新加载systemd配置
    systemctl daemon-reload
fi

# 启动SSH服务
echo -e "${YELLOW}启动SSH服务...${NC}"
systemctl start ssh || service ssh start

# --- 8. 验证安装 ---
echo -e "${YELLOW}验证安装...${NC}"
sleep 2

# 验证服务端
SSHD_STATUS=$(systemctl status ssh 2>&1 || service ssh status 2>&1)
# 验证客户端和服务端版本
SSH_CLIENT_VERSION=$(ssh -V 2>&1)
SSHD_VERSION=$(sshd -V 2>&1 2>/dev/null || echo "无法获取sshd版本，使用客户端版本代替: $SSH_CLIENT_VERSION")

echo -e "${YELLOW}SSH客户端版本: $SSH_CLIENT_VERSION${NC}"
echo -e "${YELLOW}SSH服务端版本: $SSHD_VERSION${NC}"

INSTALL_SUCCESS=false
if [[ "$SSH_CLIENT_VERSION" == *9.8p1* ]] && [[ "$SSHD_STATUS" == *active* || "$SSHD_STATUS" == *running* ]]; then
    echo -e "${GREEN}OpenSSH 9.8p1 服务端和客户端安装成功！${NC}"
    echo -e "${GREEN}SSH服务已启动并运行${NC}"
    INSTALL_SUCCESS=true
else
    echo -e "${RED}安装验证失败或SSH服务未成功运行${NC}"
    echo -e "${YELLOW}服务状态：$SSHD_STATUS${NC}"
fi

# --- 9. 清理 ---
echo -e "${YELLOW}清理临时文件...${NC}"
rm -rf "$TEMP_BUILD_DIR"

echo -e "${GREEN}安装过程完成${NC}"
echo -e "${YELLOW}日志文件已保存到: $LOG_FILE${NC}"

if $INSTALL_SUCCESS; then
    echo -e "${YELLOW}备份目录位于: $BACKUP_DIR${NC}"
    echo -e "${YELLOW}如需恢复，请在脚本目录运行：${NC}"
    echo -e "${GREEN}sudo bash $RESTORE_SCRIPT_NAME $BACKUP_DIR${NC}"
    exit 0
else
    echo -e "${RED}安装似乎未完全成功，请检查日志和系统状态。${NC}"
    # 提供恢复选项
    echo -e "${YELLOW}是否立即尝试恢复到原始版本？(y/n)${NC}"
    read -p "" -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if [ -f "$SCRIPT_DIR/$RESTORE_SCRIPT_NAME" ]; then
            echo -e "${YELLOW}执行恢复操作...${NC}"
            bash "$SCRIPT_DIR/$RESTORE_SCRIPT_NAME" "$BACKUP_DIR"
        else
             echo -e "${RED}错误：未找到恢复脚本 $SCRIPT_DIR/$RESTORE_SCRIPT_NAME ${NC}"
             echo -e "${YELLOW}请手动从备份目录 $BACKUP_DIR 恢复。${NC}"
        fi
    fi
    exit 1
fi 