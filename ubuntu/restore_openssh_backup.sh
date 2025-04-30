#!/bin/bash

# 设置颜色输出
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# 设置日志文件
LOG_FILE="openssh_restore.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# 检查是否为root用户
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}错误：请使用root权限运行此脚本${NC}"
    exit 1
fi

# 检查是否提供了备份目录参数
if [ -z "$1" ]; then
    # 尝试查找最新的备份目录
    LATEST_BACKUP=$(find /var/backups -maxdepth 1 -type d -name "openssh-backup-*" | sort -r | head -1)
    
    if [ -z "$LATEST_BACKUP" ]; then
        echo -e "${RED}错误：未提供备份目录，且未找到自动备份目录${NC}"
        echo -e "${YELLOW}用法: $0 <备份目录路径>${NC}"
        exit 1
    else
        BACKUP_DIR=$LATEST_BACKUP
        echo -e "${YELLOW}使用最新的备份目录: $BACKUP_DIR${NC}"
    fi
else
    BACKUP_DIR=$1
fi

# 验证备份目录是否存在
if [ ! -d "$BACKUP_DIR" ]; then
    echo -e "${RED}错误：备份目录 $BACKUP_DIR 不存在${NC}"
    exit 1
fi

# 检查备份目录中是否有必要的文件
if [ ! -d "$BACKUP_DIR/ssh" ]; then
    echo -e "${RED}错误：备份目录中未找到SSH配置文件${NC}"
    exit 1
fi

echo -e "${GREEN}开始从备份 $BACKUP_DIR 恢复OpenSSH...${NC}"

# 显示备份信息
if [ -f "$BACKUP_DIR/version_info.txt" ]; then
    echo -e "${YELLOW}备份的SSH版本:${NC}"
    cat "$BACKUP_DIR/version_info.txt"
fi

# 显示备份的包信息
if [ -f "$BACKUP_DIR/openssh_packages.txt" ]; then
    echo -e "${YELLOW}备份的OpenSSH包:${NC}"
    cat "$BACKUP_DIR/openssh_packages.txt"
fi

# 停止当前SSH服务
echo -e "${YELLOW}停止当前SSH服务...${NC}"
systemctl stop ssh || service ssh stop

# 备份当前配置（作为额外的保障措施）
echo -e "${YELLOW}备份当前配置...${NC}"
CURRENT_BACKUP="/tmp/openssh-current-$(date +%s)"
mkdir -p $CURRENT_BACKUP
[ -d /etc/ssh ] && cp -a /etc/ssh $CURRENT_BACKUP/

# 检查是否存在apt包信息，如果有则尝试通过apt恢复
if [ -f "$BACKUP_DIR/openssh_packages.txt" ] && command -v apt-get >/dev/null; then
    echo -e "${YELLOW}尝试通过apt恢复OpenSSH包...${NC}"
    
    # 提取包名
    PACKAGE_NAMES=$(cat "$BACKUP_DIR/openssh_packages.txt" | awk '{print $2}' | grep -v "^$")
    
    # 尝试重新安装包
    if [ ! -z "$PACKAGE_NAMES" ]; then
        echo -e "${YELLOW}重新安装以下包: $PACKAGE_NAMES${NC}"
        apt-get install --reinstall -y $PACKAGE_NAMES || {
            echo -e "${RED}通过apt恢复失败，将尝试直接恢复文件${NC}"
        }
    fi
else
    echo -e "${YELLOW}未找到apt包信息或系统不支持apt，将直接恢复文件${NC}"
fi

# 恢复二进制文件
echo -e "${YELLOW}恢复SSH二进制文件...${NC}"
if [ -f "$BACKUP_DIR/sshd" ]; then
    cp "$BACKUP_DIR/sshd" /usr/sbin/sshd
    chmod 755 /usr/sbin/sshd
    echo -e "${GREEN}已恢复sshd二进制文件${NC}"
fi

if [ -f "$BACKUP_DIR/ssh" ]; then
    cp "$BACKUP_DIR/ssh" /usr/bin/ssh
    chmod 755 /usr/bin/ssh
    echo -e "${GREEN}已恢复ssh客户端二进制文件${NC}"
fi

if [ -f "$BACKUP_DIR/ssh-keygen" ]; then
    cp "$BACKUP_DIR/ssh-keygen" /usr/bin/ssh-keygen
    chmod 755 /usr/bin/ssh-keygen
    echo -e "${GREEN}已恢复ssh-keygen二进制文件${NC}"
fi

# 恢复配置文件
echo -e "${YELLOW}恢复SSH配置文件...${NC}"
if [ -d "$BACKUP_DIR/ssh" ]; then
    cp -a "$BACKUP_DIR/ssh" /etc/
    chmod 755 /etc/ssh
    chmod 600 /etc/ssh/ssh_host_*_key
    chmod 644 /etc/ssh/ssh_host_*_key.pub
    echo -e "${GREEN}已恢复SSH配置文件${NC}"
fi

# 恢复systemd服务文件
if [ -f "$BACKUP_DIR/systemd/ssh.service" ]; then
    echo -e "${YELLOW}恢复systemd服务文件...${NC}"
    cp "$BACKUP_DIR/systemd/ssh.service" /lib/systemd/system/
    systemctl daemon-reload
    echo -e "${GREEN}已恢复systemd服务文件${NC}"
fi

# 启动SSH服务
echo -e "${YELLOW}启动SSH服务...${NC}"
systemctl start ssh || service ssh start

# 验证恢复
echo -e "${YELLOW}验证恢复...${NC}"
sleep 2
RESTORED_VERSION=$(ssh -V 2>&1)
SSHD_STATUS=$(systemctl status ssh 2>&1 || service ssh status 2>&1)

echo -e "${YELLOW}当前SSH版本: $RESTORED_VERSION${NC}"

if [[ "$SSHD_STATUS" == *"active"* || "$SSHD_STATUS" == *"running"* ]]; then
    echo -e "${GREEN}SSH服务已成功启动${NC}"
    echo -e "${GREEN}OpenSSH恢复成功！${NC}"
else
    echo -e "${RED}SSH服务启动失败${NC}"
    echo -e "${YELLOW}当前状态:${NC}"
    echo "$SSHD_STATUS"
    
    echo -e "${YELLOW}尝试查看错误日志:${NC}"
    journalctl -u ssh -n 20 --no-pager 2>/dev/null || tail -n 20 /var/log/syslog 2>/dev/null
    
    echo -e "${RED}恢复未完全成功，请手动检查问题${NC}"
    echo -e "${YELLOW}如果需要，可以尝试使用当前备份: $CURRENT_BACKUP${NC}"
fi

echo -e "${GREEN}恢复过程完成${NC}"
echo -e "${YELLOW}日志文件已保存到: $(pwd)/$LOG_FILE${NC}"

exit 0 