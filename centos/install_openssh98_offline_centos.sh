#!/bin/bash

# OpenSSH 9.8p1离线安装脚本 (CentOS 7版本)
# 此脚本根据系统OpenSSL版本决定是否编译安装OpenSSL 1.1.1

# 设置颜色输出
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

# 定义原始压缩包和更新的压缩包
ORIGINAL_TARBALL="$SCRIPT_DIR/openssh_9.8p1_source_deps_package.tar.gz"
UPDATED_TARBALL="$SCRIPT_DIR/openssh_9.8p1_source_deps_package_updated.tar.gz"
PACKAGE_DIR_NAME="openssh_9.8p1_package"

# 日志文件
LOG_FILE="$SCRIPT_DIR/install.log"
# 创建日志文件
touch "$LOG_FILE"
echo "$(date) - 开始安装日志" > "$LOG_FILE"

# 检查是否为root用户
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}错误：请使用root权限运行此脚本${NC}"
    echo "$(date) - 错误：非root用户尝试运行脚本" >> "$LOG_FILE"
    exit 1
fi

# 检查OpenSSL配置文件和源码包
check_openssl_config() {
    # 直接设置为需要安装OpenSSL 1.1.1，无需检查现有版本
    NEED_OPENSSL="yes"
    echo -e "${YELLOW}按照要求，将始终安装OpenSSL 1.1.1，无论当前版本如何${NC}"
    echo "$(date) - 按照要求强制安装OpenSSL 1.1.1" >> "$LOG_FILE"
    
    # 还是检查一下现有版本，仅作为信息显示
    check_openssl_version_info
}

# 检查OpenSSL版本函数 - 仅显示信息，不影响安装决策
check_openssl_version_info() {
    echo -e "${YELLOW}检查当前OpenSSL版本(仅供参考)...${NC}"
    
    # 检查是否安装了OpenSSL
    if ! command -v openssl &> /dev/null; then
        echo -e "${YELLOW}系统未安装OpenSSL，将安装OpenSSL 1.1.1${NC}"
        echo "$(date) - 系统未安装OpenSSL，需要安装1.1.1版本" >> "$LOG_FILE"
        return
    fi
    
    # 获取版本信息
    OPENSSL_VERSION=$(openssl version | awk '{print $2}')
    echo -e "${YELLOW}当前系统OpenSSL版本: $OPENSSL_VERSION (将被OpenSSL 1.1.1替换)${NC}"
    echo "$(date) - 检测到OpenSSL版本: $OPENSSL_VERSION (将被替换)" >> "$LOG_FILE"
}

# 检查源码包
check_source_package() {
    # 检查更新的压缩包是否存在
    if [ -f "$UPDATED_TARBALL" ]; then
        SOURCE_TARBALL="$UPDATED_TARBALL"
        echo -e "${GREEN}找到更新的安装包: $SOURCE_TARBALL${NC}"
        echo "$(date) - 使用更新的安装包: $SOURCE_TARBALL" >> "$LOG_FILE"
    # 检查原始压缩包是否存在
    elif [ -f "$ORIGINAL_TARBALL" ]; then
        SOURCE_TARBALL="$ORIGINAL_TARBALL"
        echo -e "${YELLOW}找到原始安装包: $SOURCE_TARBALL${NC}"
        echo "$(date) - 使用原始安装包: $SOURCE_TARBALL" >> "$LOG_FILE"
    else
        echo -e "${RED}错误：未找到安装包，请先准备安装包${NC}"
        echo "$(date) - 错误：未找到安装包" >> "$LOG_FILE"
        exit 1
    fi
}

# 主程序开始
echo -e "${GREEN}======= OpenSSH 9.8p1离线安装脚本 (CentOS 7) =======${NC}"

# 检查源码包
check_source_package

# 提取压缩包
echo -e "${YELLOW}正在解压安装包...${NC}"
echo "$(date) - 开始解压安装包" >> "$LOG_FILE"

# 如果目录已存在，先删除
if [ -d "$SCRIPT_DIR/$PACKAGE_DIR_NAME" ]; then
    echo -e "${YELLOW}删除已存在的目录: $SCRIPT_DIR/$PACKAGE_DIR_NAME${NC}"
    rm -rf "$SCRIPT_DIR/$PACKAGE_DIR_NAME"
fi

# 解压
tar -xzf "$SOURCE_TARBALL" -C "$SCRIPT_DIR" || {
    echo -e "${RED}解压失败，请检查安装包完整性${NC}"
    echo "$(date) - 错误：解压安装包失败" >> "$LOG_FILE"
    exit 1
}

# 重命名解压后的目录
if [ -d "$SCRIPT_DIR/tmp_package" ]; then
    mv "$SCRIPT_DIR/tmp_package" "$SCRIPT_DIR/$PACKAGE_DIR_NAME"
fi

echo -e "${GREEN}解压完成${NC}"
echo "$(date) - 解压安装包完成" >> "$LOG_FILE"

# 定义路径
PACKAGE_DIR="$SCRIPT_DIR/$PACKAGE_DIR_NAME"
SOURCE_DIR="$PACKAGE_DIR/source"
DEPS_DIR="$PACKAGE_DIR/dependencies"
BACKUP_DIR="$PACKAGE_DIR/backup"
OPENSSL_SOURCE_DIR="$PACKAGE_DIR/openssl_source"

# 创建备份目录
mkdir -p "$BACKUP_DIR"

# 检查OpenSSH源码包
if [ ! -f "$SOURCE_DIR/openssh-9.8p1.tar.gz" ]; then
    echo -e "${RED}错误：未找到OpenSSH 9.8p1源码包${NC}"
    echo "$(date) - 错误：未找到OpenSSH源码包" >> "$LOG_FILE"
    exit 1
fi

# 检查系统是否为CentOS 7
if [ -f /etc/centos-release ]; then
    VERSION=$(cat /etc/centos-release | tr -dc '0-9.' | cut -d \. -f1)
    if [ "$VERSION" -ne 7 ]; then
        echo -e "${YELLOW}警告：当前系统不是CentOS 7，可能存在兼容性问题${NC}"
        echo "$(date) - 警告：系统不是CentOS 7 ($VERSION)" >> "$LOG_FILE"
        echo -n -e "${YELLOW}是否继续？(y/n): ${NC}"
        read -r answer
        if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
            echo -e "${RED}安装已取消${NC}"
            echo "$(date) - 用户取消安装" >> "$LOG_FILE"
            exit 1
        fi
    else
        echo -e "${GREEN}确认系统为CentOS 7${NC}"
        echo "$(date) - 确认系统为CentOS 7" >> "$LOG_FILE"
    fi
else
    echo -e "${YELLOW}警告：无法确认是否为CentOS系统${NC}"
    echo "$(date) - 警告：无法确认是否为CentOS系统" >> "$LOG_FILE"
    echo -n -e "${YELLOW}是否继续？(y/n): ${NC}"
    read -r answer
    if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
        echo -e "${RED}安装已取消${NC}"
        echo "$(date) - 用户取消安装" >> "$LOG_FILE"
        exit 1
    fi
fi

# 检查OpenSSL配置
check_openssl_config

# 备份现有的OpenSSH配置
echo -e "${YELLOW}备份现有的OpenSSH配置...${NC}"
echo "$(date) - 开始备份OpenSSH配置" >> "$LOG_FILE"

# 备份SSH配置文件
if [ -d /etc/ssh ]; then
    cp -r /etc/ssh "$BACKUP_DIR/ssh_config"
    echo -e "${GREEN}SSH配置文件已备份到 $BACKUP_DIR/ssh_config${NC}"
    echo "$(date) - SSH配置文件已备份" >> "$LOG_FILE"
fi

# 获取当前SSH版本
CURRENT_SSH_VERSION=$(ssh -V 2>&1 | cut -d' ' -f1)
echo "当前SSH版本: $CURRENT_SSH_VERSION" > "$BACKUP_DIR/restore_info.txt"
echo "备份时间: $(date)" >> "$BACKUP_DIR/restore_info.txt"
echo "$(date) - 当前SSH版本: $CURRENT_SSH_VERSION" >> "$LOG_FILE"

# 备份已安装的OpenSSH软件包
rpm -qa | grep openssh > "$BACKUP_DIR/installed_openssh_packages.txt"
echo -e "${GREEN}已安装的OpenSSH软件包列表已保存${NC}"
echo "$(date) - 已安装的OpenSSH软件包列表已保存" >> "$LOG_FILE"

# 备份SSH二进制文件
if [ -f /usr/sbin/sshd ]; then
    mkdir -p "$BACKUP_DIR/bin"
    cp /usr/sbin/sshd "$BACKUP_DIR/bin/"
    echo -e "${GREEN}SSH服务端已备份${NC}"
    echo "$(date) - SSH服务端已备份" >> "$LOG_FILE"
fi

for bin in ssh ssh-keygen ssh-agent ssh-add sftp scp; do
    if [ -f "/usr/bin/$bin" ]; then
        mkdir -p "$BACKUP_DIR/bin"
        cp "/usr/bin/$bin" "$BACKUP_DIR/bin/"
        echo -e "${GREEN}SSH客户端 $bin 已备份${NC}"
        echo "$(date) - SSH客户端 $bin 已备份" >> "$LOG_FILE"
    fi
done

# 备份systemd服务文件
if [ -f /usr/lib/systemd/system/sshd.service ]; then
    mkdir -p "$BACKUP_DIR/systemd"
    cp /usr/lib/systemd/system/sshd.service "$BACKUP_DIR/systemd/"
    echo -e "${GREEN}SSH systemd服务文件已安装${NC}"
    echo "$(date) - SSH systemd服务文件已安装" >> "$LOG_FILE"
fi

# 如果存在恢复脚本，复制到备份目录
if [ -f "$PACKAGE_DIR/restore_openssh_centos.sh" ]; then
    cp "$PACKAGE_DIR/restore_openssh_centos.sh" "$BACKUP_DIR/"
    chmod +x "$BACKUP_DIR/restore_openssh_centos.sh"
    echo -e "${GREEN}恢复脚本已复制到备份目录${NC}"
    echo "$(date) - 恢复脚本已复制到备份目录" >> "$LOG_FILE"
fi

# 安装依赖
echo -e "${YELLOW}检查和安装缺失的依赖包...${NC}"
echo "$(date) - 开始检查和安装缺失的依赖包" >> "$LOG_FILE"

# 检查RPM包是否已安装的函数
is_rpm_installed() {
    local package_name="$1"
    # 从RPM文件名中提取包名
    local base_name=$(basename "$package_name" .rpm)
    # 移除版本号和架构信息
    local pkg_name=$(echo "$base_name" | sed 's/\-[0-9].*$//')
    
    # 检查包是否已安装
    if rpm -q "$pkg_name" &>/dev/null; then
        return 0  # 已安装
    else
        return 1  # 未安装
    fi
}

if [ -d "$DEPS_DIR" ] && [ "$(ls -A "$DEPS_DIR" 2>/dev/null)" ]; then
    cd "$DEPS_DIR" || {
        echo -e "${RED}无法进入依赖目录${NC}"
        echo "$(date) - 错误：无法进入依赖目录" >> "$LOG_FILE"
        exit 1
    }
    
    # 统计变量
    TOTAL_PKGS=0
    INSTALLED_PKGS=0
    SKIPPED_PKGS=0
    
    echo -e "${YELLOW}正在检查依赖包...${NC}"
    
    # 遍历所有RPM包
    for pkg in *.rpm; do
        if [ -f "$pkg" ]; then
            TOTAL_PKGS=$((TOTAL_PKGS + 1))
            
            # 检查包是否已安装
            if is_rpm_installed "$pkg"; then
                echo -e "${GREEN}跳过已安装的包: $pkg${NC}"
                echo "$(date) - 跳过已安装的包: $pkg" >> "$LOG_FILE"
                SKIPPED_PKGS=$((SKIPPED_PKGS + 1))
            else
                echo -e "${YELLOW}安装缺失的包: $pkg${NC}"
                # 安装单个包
                if rpm -Uvh --nodeps "$pkg" >> "$LOG_FILE" 2>&1; then
                    echo -e "${GREEN}成功安装: $pkg${NC}"
                    echo "$(date) - 成功安装: $pkg" >> "$LOG_FILE"
                    INSTALLED_PKGS=$((INSTALLED_PKGS + 1))
                else
                    echo -e "${RED}安装失败: $pkg${NC}"
                    echo "$(date) - 安装失败: $pkg" >> "$LOG_FILE"
                fi
            fi
        fi
    done
    
    # 显示安装统计
    echo -e "${GREEN}依赖包安装完成: 共 $TOTAL_PKGS 个包，安装 $INSTALLED_PKGS 个，跳过 $SKIPPED_PKGS 个已安装的包${NC}"
    echo "$(date) - 依赖包安装完成: 共 $TOTAL_PKGS 个包，安装 $INSTALLED_PKGS 个，跳过 $SKIPPED_PKGS 个已安装的包" >> "$LOG_FILE"
else
    echo -e "${YELLOW}未找到依赖包，跳过安装依赖${NC}"
    echo "$(date) - 未找到依赖包，跳过安装" >> "$LOG_FILE"
fi

# 如果需要安装OpenSSL 1.1.1
if [ "$NEED_OPENSSL" = "yes" ]; then
    echo -e "${YELLOW}开始编译和安装OpenSSL 1.1.1...${NC}"
    echo "$(date) - 开始编译和安装OpenSSL 1.1.1" >> "$LOG_FILE"
    
    # 检查OpenSSL源码包
    if [ -d "$OPENSSL_SOURCE_DIR" ] && [ -f "$OPENSSL_SOURCE_DIR/openssl-1.1.1w.tar.gz" ]; then
        OPENSSL_INSTALL_DIR="/usr/local/openssl-1.1.1"
        
        # 解压OpenSSL源码
        cd "$SCRIPT_DIR" || {
            echo -e "${RED}无法更改到脚本目录${NC}"
            echo "$(date) - 错误：无法更改到脚本目录" >> "$LOG_FILE"
            exit 1
        }
        
        # 检查并备份当前OpenSSL
        if [ -f /usr/bin/openssl ]; then
            mkdir -p "$BACKUP_DIR/openssl"
            cp /usr/bin/openssl "$BACKUP_DIR/openssl/"
            echo -e "${GREEN}当前OpenSSL已备份到 $BACKUP_DIR/openssl/${NC}"
            echo "$(date) - 当前OpenSSL已备份" >> "$LOG_FILE"
        fi
        
        # 创建临时编译目录
        COMPILE_DIR="$SCRIPT_DIR/compile_tmp"
        mkdir -p "$COMPILE_DIR"
        
        echo -e "${YELLOW}解压OpenSSL源码...${NC}"
        tar -xzf "$OPENSSL_SOURCE_DIR/openssl-1.1.1w.tar.gz" -C "$COMPILE_DIR" || {
            echo -e "${RED}解压OpenSSL源码失败${NC}"
            echo "$(date) - 错误：解压OpenSSL源码失败" >> "$LOG_FILE"
            exit 1
        }
        
        # 编译与安装OpenSSL
        cd "$COMPILE_DIR/openssl-1.1.1w" || {
            echo -e "${RED}无法进入OpenSSL源码目录${NC}"
            echo "$(date) - 错误：无法进入OpenSSL源码目录" >> "$LOG_FILE"
            exit 1
        }
        
        echo -e "${YELLOW}配置OpenSSL...${NC}"
        ./config --prefix="$OPENSSL_INSTALL_DIR" --openssldir="$OPENSSL_INSTALL_DIR" shared zlib-dynamic >> "$LOG_FILE" 2>&1
        
        echo -e "${YELLOW}编译OpenSSL...${NC}"
        make -j$(nproc) >> "$LOG_FILE" 2>&1
        
        echo -e "${YELLOW}安装OpenSSL...${NC}"
        make install >> "$LOG_FILE" 2>&1
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}OpenSSL 1.1.1安装成功${NC}"
            echo "$(date) - OpenSSL 1.1.1安装成功" >> "$LOG_FILE"
            
            # 创建符号链接，替换系统的OpenSSL
            ln -sf "$OPENSSL_INSTALL_DIR/bin/openssl" /usr/bin/openssl
            
            # 保留一个带版本的链接以备查询
            ln -sf "$OPENSSL_INSTALL_DIR/bin/openssl" /usr/bin/openssl1.1
            
            # 配置库路径
            echo "$OPENSSL_INSTALL_DIR/lib" > /etc/ld.so.conf.d/openssl-1.1.1.conf
            ldconfig
            
            # 测试新安装的OpenSSL
            if [ -f /usr/bin/openssl ]; then
                NEW_OPENSSL_VERSION=$(/usr/bin/openssl version)
                echo -e "${GREEN}安装的OpenSSL版本: $NEW_OPENSSL_VERSION${NC}"
                echo "$(date) - 新安装的OpenSSL版本: $NEW_OPENSSL_VERSION" >> "$LOG_FILE"
            else
                echo -e "${RED}警告：无法验证新安装的OpenSSL版本${NC}"
                echo "$(date) - 警告：无法验证新安装的OpenSSL版本" >> "$LOG_FILE"
            fi
        else
            echo -e "${RED}OpenSSL安装失败，中止安装${NC}"
            echo "$(date) - 错误：OpenSSL安装失败" >> "$LOG_FILE"
            exit 1
        fi
        
        # 清理编译目录
        rm -rf "$COMPILE_DIR"
    else
        echo -e "${RED}错误：未找到OpenSSL源码包${NC}"
        echo "$(date) - 错误：未找到OpenSSL源码包" >> "$LOG_FILE"
        exit 1
    fi
else
    # 这个分支在逻辑上不会被执行，因为我们已设置NEED_OPENSSL="yes"
    echo -e "${GREEN}系统OpenSSL版本已满足要求，跳过OpenSSL安装${NC}"
    echo "$(date) - 跳过OpenSSL安装" >> "$LOG_FILE"
fi

# 安装OpenSSH
echo -e "${YELLOW}开始编译和安装OpenSSH 9.8p1...${NC}"
echo "$(date) - 开始编译和安装OpenSSH 9.8p1" >> "$LOG_FILE"

# 解压OpenSSH源码
cd "$SCRIPT_DIR" || {
    echo -e "${RED}无法更改到脚本目录${NC}"
    echo "$(date) - 错误：无法更改到脚本目录" >> "$LOG_FILE"
    exit 1
}

# 创建临时编译目录
COMPILE_DIR="$SCRIPT_DIR/compile_tmp"
mkdir -p "$COMPILE_DIR"

echo -e "${YELLOW}解压OpenSSH源码...${NC}"
tar -xzf "$SOURCE_DIR/openssh-9.8p1.tar.gz" -C "$COMPILE_DIR" || {
    echo -e "${RED}解压OpenSSH源码失败${NC}"
    echo "$(date) - 错误：解压OpenSSH源码失败" >> "$LOG_FILE"
    exit 1
}

# 停止SSH服务
echo -e "${YELLOW}停止SSH服务...${NC}"
systemctl stop sshd
echo "$(date) - 停止SSH服务" >> "$LOG_FILE"

# 编译与安装OpenSSH
cd "$COMPILE_DIR/openssh-9.8p1" || {
    echo -e "${RED}无法进入OpenSSH源码目录${NC}"
    echo "$(date) - 错误：无法进入OpenSSH源码目录" >> "$LOG_FILE"
    exit 1
}

echo -e "${YELLOW}配置OpenSSH...${NC}"

# 配置选项，根据是否安装了OpenSSL 1.1.1来决定
if [ "$NEED_OPENSSL" = "yes" ]; then
    echo -e "${YELLOW}使用新安装的OpenSSL 1.1.1进行配置...${NC}"
    echo "$(date) - 使用OpenSSL 1.1.1配置OpenSSH" >> "$LOG_FILE"
    
    ./configure \
        --prefix=/usr \
        --sysconfdir=/etc/ssh \
        --with-md5-passwords \
        --with-ssl-dir="$OPENSSL_INSTALL_DIR" \
        --with-privsep-path=/var/lib/sshd \
        --with-pam \
        --with-selinux \
        --with-kerberos5 \
        >> "$LOG_FILE" 2>&1
else
    echo -e "${YELLOW}使用系统OpenSSL进行配置...${NC}"
    echo "$(date) - 使用系统OpenSSL配置OpenSSH" >> "$LOG_FILE"
    
    ./configure \
        --prefix=/usr \
        --sysconfdir=/etc/ssh \
        --with-md5-passwords \
        --with-privsep-path=/var/lib/sshd \
        --with-pam \
        --with-selinux \
        --with-kerberos5 \
        >> "$LOG_FILE" 2>&1
fi

if [ $? -ne 0 ]; then
    echo -e "${RED}OpenSSH配置失败，请查看日志文件 $LOG_FILE${NC}"
    echo "$(date) - 错误：OpenSSH配置失败" >> "$LOG_FILE"
    exit 1
fi

echo -e "${YELLOW}编译OpenSSH...${NC}"
make -j$(nproc) >> "$LOG_FILE" 2>&1

if [ $? -ne 0 ]; then
    echo -e "${RED}OpenSSH编译失败，请查看日志文件 $LOG_FILE${NC}"
    echo "$(date) - 错误：OpenSSH编译失败" >> "$LOG_FILE"
    exit 1
fi

echo -e "${YELLOW}安装OpenSSH...${NC}"
make install >> "$LOG_FILE" 2>&1

if [ $? -ne 0 ]; then
    echo -e "${RED}OpenSSH安装失败，请查看日志文件 $LOG_FILE${NC}"
    echo "$(date) - 错误：OpenSSH安装失败" >> "$LOG_FILE"
    exit 1
fi

# 复制systemd服务文件
if [ -f contrib/redhat/sshd.init ]; then
    cp contrib/redhat/sshd.init /etc/init.d/sshd
    chmod +x /etc/init.d/sshd
    echo -e "${GREEN}SSH服务初始化脚本已安装${NC}"
    echo "$(date) - SSH服务初始化脚本已安装" >> "$LOG_FILE"
fi

if [ -f contrib/redhat/sshd.service ]; then
    cp contrib/redhat/sshd.service /usr/lib/systemd/system/
    systemctl daemon-reload
    echo -e "${GREEN}SSH systemd服务文件已安装${NC}"
    echo "$(date) - SSH systemd服务文件已安装" >> "$LOG_FILE"
fi

# 重启SSH服务
echo -e "${YELLOW}启动SSH服务...${NC}"
systemctl start sshd
echo "$(date) - 启动SSH服务" >> "$LOG_FILE"

# 检查服务状态
if systemctl is-active sshd >/dev/null 2>&1; then
    echo -e "${GREEN}SSH服务已成功启动${NC}"
    echo "$(date) - SSH服务已成功启动" >> "$LOG_FILE"
    
    # 获取新安装的SSH版本
    NEW_SSH_VERSION=$(ssh -V 2>&1)
    echo -e "${GREEN}成功安装的SSH版本: $NEW_SSH_VERSION${NC}"
    echo "$(date) - 成功安装的SSH版本: $NEW_SSH_VERSION" >> "$LOG_FILE"
else
    echo -e "${RED}警告：SSH服务启动失败，请手动检查${NC}"
    echo "$(date) - 警告：SSH服务启动失败" >> "$LOG_FILE"
fi

# 清理编译目录
rm -rf "$COMPILE_DIR"

echo -e "${GREEN}OpenSSH 9.8p1安装完成！${NC}"
echo -e "${YELLOW}备份文件已保存在: $BACKUP_DIR${NC}"
echo -e "${YELLOW}如需恢复旧版本，请使用: $BACKUP_DIR/restore_openssh_centos.sh${NC}"
echo "$(date) - OpenSSH 9.8p1安装完成" >> "$LOG_FILE"

exit 0