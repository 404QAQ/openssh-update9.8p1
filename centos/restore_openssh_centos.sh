#!/bin/bash

# 设置颜色输出
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# 设置日志文件
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
LOG_FILE="$SCRIPT_DIR/restore.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# 检查是否为root用户
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}错误：请使用root权限运行此脚本${NC}"
    exit 1
fi

# 确定备份目录
if [ -z "$1" ]; then
    echo -e "${YELLOW}未指定备份目录，尝试查找最新备份...${NC}"
    # 在解压后的包内查找最新的备份
    if [ -d "$SCRIPT_DIR/openssh_9.8p1_package/backup" ]; then
        BACKUP_DIR=$(find "$SCRIPT_DIR/openssh_9.8p1_package/backup" -type d -name "openssh-backup-*" | sort -r | head -n 1)
        if [ -n "$BACKUP_DIR" ]; then
            echo -e "${GREEN}找到最新备份目录: $BACKUP_DIR${NC}"
        else
            echo -e "${RED}错误：无法在 $SCRIPT_DIR/openssh_9.8p1_package/backup 下找到备份目录${NC}"
            echo -e "${YELLOW}请指定正确的备份目录作为参数${NC}"
            exit 1
        fi
    else
        echo -e "${RED}错误：未找到备份目录 $SCRIPT_DIR/openssh_9.8p1_package/backup${NC}"
        echo -e "${YELLOW}请指定正确的备份目录作为参数${NC}"
        exit 1
    fi
else
    BACKUP_DIR="$1"
    if [ ! -d "$BACKUP_DIR" ]; then
        echo -e "${RED}错误：指定的备份目录 $BACKUP_DIR 不存在${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}开始从 $BACKUP_DIR 恢复OpenSSH和OpenSSL...${NC}"

# 停止SSH服务
echo -e "${YELLOW}停止SSH服务...${NC}"
systemctl stop sshd.service || service sshd stop

# 恢复二进制文件
echo -e "${YELLOW}恢复SSH二进制文件...${NC}"

# 检查备份的二进制文件是否存在
ssh_bins=("sshd" "ssh" "ssh-keygen" "ssh-agent" "ssh-add" "sftp" "scp")
for bin in "${ssh_bins[@]}"; do
    if [ -f "$BACKUP_DIR/$bin" ]; then
        if [ "$bin" = "sshd" ]; then
            # 服务端
            cp "$BACKUP_DIR/$bin" /usr/sbin/
            chmod 755 /usr/sbin/$bin
            echo -e "${GREEN}已恢复: /usr/sbin/$bin${NC}"
        else
            # 客户端
            cp "$BACKUP_DIR/$bin" /usr/bin/
            chmod 755 /usr/bin/$bin
            echo -e "${GREEN}已恢复: /usr/bin/$bin${NC}"
        fi
    else
        echo -e "${YELLOW}警告：备份目录中未找到 $bin 二进制文件${NC}"
    fi
done

# 恢复OpenSSL二进制文件
if [ -f "$BACKUP_DIR/openssl" ]; then
    echo -e "${YELLOW}恢复OpenSSL二进制文件...${NC}"
    
    # 移除可能创建的符号链接
    if [ -L /usr/bin/openssl ]; then
        rm -f /usr/bin/openssl
    fi
    
    # 恢复原有的OpenSSL
    cp "$BACKUP_DIR/openssl" /usr/bin/
    chmod 755 /usr/bin/openssl
    echo -e "${GREEN}已恢复: /usr/bin/openssl${NC}"
    
    # 恢复ldconfig配置
    if [ -f /etc/ld.so.conf.d/openssl-1.1.1.conf ]; then
        rm -f /etc/ld.so.conf.d/openssl-1.1.1.conf
        ldconfig
        echo -e "${GREEN}已删除OpenSSL 1.1.1配置文件${NC}"
    fi
else
    echo -e "${YELLOW}警告：备份目录中未找到OpenSSL二进制文件${NC}"
fi

# 恢复配置文件
if [ -d "$BACKUP_DIR/ssh" ]; then
    echo -e "${YELLOW}恢复SSH配置文件...${NC}"
    cp -a "$BACKUP_DIR/ssh" /etc/
    echo -e "${GREEN}已恢复SSH配置目录${NC}"
else
    echo -e "${YELLOW}警告：备份目录中未找到SSH配置目录${NC}"
fi

# 恢复SSL配置文件
if [ -d "$BACKUP_DIR/ssl" ]; then
    echo -e "${YELLOW}恢复SSL配置文件...${NC}"
    cp -a "$BACKUP_DIR/ssl" /etc/
    echo -e "${GREEN}已恢复SSL配置目录${NC}"
else
    echo -e "${YELLOW}警告：备份目录中未找到SSL配置目录${NC}"
fi

# 恢复systemd服务文件
if [ -f "$BACKUP_DIR/systemd/sshd.service" ]; then
    echo -e "${YELLOW}恢复systemd服务文件...${NC}"
    cp "$BACKUP_DIR/systemd/sshd.service" /usr/lib/systemd/system/
    systemctl daemon-reload
    echo -e "${GREEN}已恢复systemd服务文件${NC}"
fi

# 尝试重新安装原始RPM包
echo -e "${YELLOW}尝试恢复原始RPM包...${NC}"
if [ -f "$BACKUP_DIR/openssh_packages.txt" ]; then
    ORIG_PACKAGES=$(cat "$BACKUP_DIR/openssh_packages.txt")
    if [ -n "$ORIG_PACKAGES" ]; then
        echo -e "${YELLOW}尝试重新安装以下包: $ORIG_PACKAGES${NC}"
        yum reinstall -y $ORIG_PACKAGES &>/dev/null || echo -e "${YELLOW}无法自动重新安装原始包，可能需要手动处理${NC}"
    fi
fi

if [ -f "$BACKUP_DIR/openssl_packages.txt" ]; then
    ORIG_SSL_PACKAGES=$(cat "$BACKUP_DIR/openssl_packages.txt")
    if [ -n "$ORIG_SSL_PACKAGES" ]; then
        echo -e "${YELLOW}尝试重新安装以下OpenSSL包: $ORIG_SSL_PACKAGES${NC}"
        yum reinstall -y $ORIG_SSL_PACKAGES &>/dev/null || echo -e "${YELLOW}无法自动重新安装原始OpenSSL包，可能需要手动处理${NC}"
    fi
fi

# 启动SSH服务
echo -e "${YELLOW}启动SSH服务...${NC}"
systemctl start sshd.service || service sshd start

# 验证恢复
echo -e "${YELLOW}验证SSH服务...${NC}"
sleep 2

# 检查SSH服务状态
SSHD_STATUS=$(systemctl status sshd.service 2>&1 || service sshd status 2>&1)
if [[ "$SSHD_STATUS" == *active* || "$SSHD_STATUS" == *running* ]]; then
    echo -e "${GREEN}SSH服务已成功恢复并正在运行${NC}"
    SSH_VERSION=$(ssh -V 2>&1)
    echo -e "${YELLOW}当前SSH版本: $SSH_VERSION${NC}"
    
    # 验证OpenSSL版本
    OPENSSL_VERSION=$(openssl version 2>&1)
    echo -e "${YELLOW}当前OpenSSL版本: $OPENSSL_VERSION${NC}"
    
    exit 0
else
    echo -e "${RED}警告：SSH服务恢复后未能成功启动${NC}"
    echo -e "${YELLOW}服务状态: $SSHD_STATUS${NC}"
    echo -e "${YELLOW}请手动检查SSH服务${NC}"
    exit 1
fi 