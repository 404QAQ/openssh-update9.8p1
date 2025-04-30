#!/bin/bash

# 设置颜色输出
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
PACKAGE_EXTRACT_DIR="openssh_9.8p1_package"

# 设置日志文件 (在脚本所在目录下)
LOG_FILE="$SCRIPT_DIR/restore.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# 检查是否为root用户
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}错误：请使用root权限运行此脚本${NC}"
    exit 1
fi

echo -e "${GREEN}开始恢复OpenSSH（服务端和客户端）...${NC}"

# --- 1. 确定备份目录 ---
if [ -z "$1" ]; then
    # 尝试查找脚本同级目录下最新的备份目录
    PACKAGE_DIR="$SCRIPT_DIR/$PACKAGE_EXTRACT_DIR"
    BACKUP_BASE="$PACKAGE_DIR/backup"
    if [ ! -d "$BACKUP_BASE" ]; then
         # 如果 scripts 目录下的 backup 不存在，尝试上一级目录的 backup (兼容旧的复制方式)
         PACKAGE_DIR="$(dirname "$SCRIPT_DIR")"
         BACKUP_BASE="$PACKAGE_DIR/backup"
    fi
    
    if [ -d "$BACKUP_BASE" ]; then
        LATEST_BACKUP=$(find "$BACKUP_BASE" -maxdepth 1 -type d -name "openssh-backup-*" | sort -r | head -1)
    fi

    if [ -z "$LATEST_BACKUP" ]; then
        echo -e "${RED}错误：未提供备份目录参数，且在 $BACKUP_BASE 未找到自动备份目录${NC}"
        echo -e "${YELLOW}用法: sudo bash $0 <备份目录路径>${NC}"
        exit 1
    else
        BACKUP_DIR=$LATEST_BACKUP
        echo -e "${YELLOW}使用找到的最新备份目录: $BACKUP_DIR${NC}"
    fi
else
    BACKUP_DIR=$1
fi

# 验证备份目录是否存在
if [ ! -d "$BACKUP_DIR" ]; then
    echo -e "${RED}错误：备份目录 $BACKUP_DIR 不存在或无法访问${NC}"
    exit 1
fi

# 检查备份目录中是否有必要的文件
if [ ! -d "$BACKUP_DIR/ssh" ]; then
    echo -e "${RED}错误：备份目录 $BACKUP_DIR 中未找到备份的SSH配置文件(/ssh)${NC}"
    exit 1
fi

echo -e "${GREEN}将从备份 $BACKUP_DIR 恢复OpenSSH...${NC}"

# 显示备份信息
if [ -f "$BACKUP_DIR/version_info.txt" ]; then
    echo -e "${YELLOW}备份的SSH版本:${NC}"
    cat "$BACKUP_DIR/version_info.txt"
fi

if [ -f "$BACKUP_DIR/openssh_packages.txt" ]; then
    echo -e "${YELLOW}备份的OpenSSH包:${NC}"
    cat "$BACKUP_DIR/openssh_packages.txt"
fi

# --- 2. 停止当前SSH服务 ---
echo -e "${YELLOW}停止当前SSH服务...${NC}"
systemctl stop ssh || service ssh stop

# --- 3. 备份当前配置（以防万一） ---
echo -e "${YELLOW}备份当前/etc/ssh (以防万一) 到 $SCRIPT_DIR ...${NC}"
CURRENT_ETC_SSH_BACKUP="$SCRIPT_DIR/etc-ssh-pre-restore-$(date +%s)"
[ -d /etc/ssh ] && cp -a /etc/ssh "$CURRENT_ETC_SSH_BACKUP/"

# --- 4. 恢复文件 ---
# 优先尝试通过apt恢复原始包（如果信息可用）
RECOVERY_METHOD="file"
if [ -f "$BACKUP_DIR/openssh_packages.txt" ] && command -v apt-get >/dev/null; then
    echo -e "${YELLOW}尝试通过apt恢复OpenSSH包...${NC}"
    PACKAGE_NAMES=$(cat "$BACKUP_DIR/openssh_packages.txt" | awk '{print $2}' | grep -v "^$" | tr '\n' ' ')
    if [ ! -z "$PACKAGE_NAMES" ]; then
        echo -e "${YELLOW}重新安装以下包: $PACKAGE_NAMES ${NC}"
        if apt-get install --reinstall -y $PACKAGE_NAMES; then
            echo -e "${GREEN}通过apt成功恢复OpenSSH包${NC}"
            RECOVERY_METHOD="apt"
        else
            echo -e "${RED}通过apt恢复失败，将尝试直接恢复文件${NC}"
        fi
    else
         echo -e "${YELLOW}未能从备份中提取有效的包名，将尝试直接恢复文件${NC}"
    fi
else
    echo -e "${YELLOW}未找到apt包信息或系统不支持apt，将直接恢复文件${NC}"
fi

# 如果apt恢复失败或未尝试，则直接恢复文件
if [ "$RECOVERY_METHOD" == "file" ]; then
    echo -e "${YELLOW}开始直接从备份目录恢复文件...${NC}"
    
    # 恢复服务端二进制文件
    echo -e "${YELLOW}恢复SSH服务端二进制文件...${NC}"
    if [ -f "$BACKUP_DIR/sshd" ]; then
        cp "$BACKUP_DIR/sshd" /usr/sbin/sshd
        chmod 755 /usr/sbin/sshd
        echo -e "${GREEN}已恢复sshd二进制文件${NC}"
    else
        echo -e "${YELLOW}未在备份中找到sshd文件，跳过恢复${NC}"
    fi

    # 恢复客户端二进制文件
    echo -e "${YELLOW}恢复SSH客户端二进制文件...${NC}"
    CLIENT_BINARIES=("ssh" "ssh-keygen" "ssh-agent" "ssh-add" "ssh-copy-id" "sftp" "scp")
    for bin_file in "${CLIENT_BINARIES[@]}"; do
        if [ -f "$BACKUP_DIR/$bin_file" ]; then
            cp "$BACKUP_DIR/$bin_file" "/usr/bin/$bin_file"
            chmod 755 "/usr/bin/$bin_file"
            echo -e "${GREEN}已恢复 $bin_file 二进制文件${NC}"
        else
             echo -e "${YELLOW}未在备份中找到 $bin_file 文件，跳过恢复${NC}"
        fi
    done

    # 恢复配置文件
    echo -e "${YELLOW}恢复SSH配置文件...${NC}"
    if [ -d "$BACKUP_DIR/ssh" ]; then
        # 先删除现有的，避免合并问题
        rm -rf /etc/ssh
        cp -a "$BACKUP_DIR/ssh" /etc/
        # 恢复权限
        chmod 755 /etc/ssh
        chmod 600 /etc/ssh/ssh_host_*_key 2>/dev/null
        chmod 644 /etc/ssh/ssh_host_*_key.pub 2>/dev/null
        chmod 644 /etc/ssh/moduli 2>/dev/null
        chmod 644 /etc/ssh/ssh_config 2>/dev/null
        chmod 600 /etc/ssh/sshd_config 2>/dev/null # sshd_config 权限应该是 600
        echo -e "${GREEN}已恢复SSH配置文件目录 /etc/ssh ${NC}"
    fi

    # 恢复systemd服务文件
    if [ -f "$BACKUP_DIR/systemd/ssh.service" ]; then
        echo -e "${YELLOW}恢复systemd服务文件...${NC}"
        cp "$BACKUP_DIR/systemd/ssh.service" /lib/systemd/system/
        systemctl daemon-reload
        echo -e "${GREEN}已恢复systemd服务文件${NC}"
    fi
fi

# --- 5. 启动SSH服务 ---
echo -e "${YELLOW}启动SSH服务...${NC}"
systemctl start ssh || service ssh start

# --- 6. 验证恢复 ---
echo -e "${YELLOW}验证恢复...${NC}"
sleep 2
RESTORED_VERSION=$(ssh -V 2>&1)
SSHD_STATUS=$(systemctl status ssh 2>&1 || service ssh status 2>&1)

echo -e "${YELLOW}当前SSH版本: $RESTORED_VERSION${NC}"

if [[ "$SSHD_STATUS" == *active* || "$SSHD_STATUS" == *running* ]]; then
    echo -e "${GREEN}SSH服务已成功启动${NC}"
    echo -e "${GREEN}OpenSSH服务端和客户端恢复成功！${NC}"
else
    echo -e "${RED}SSH服务启动失败${NC}"
    echo -e "${YELLOW}当前状态:${NC}"
    echo "$SSHD_STATUS"
    
    echo -e "${YELLOW}尝试查看错误日志:${NC}"
    journalctl -u ssh -n 20 --no-pager 2>/dev/null || tail -n 20 /var/log/auth.log 2>/dev/null || tail -n 20 /var/log/syslog 2>/dev/null
    
    echo -e "${RED}恢复未完全成功，请手动检查问题${NC}"
    echo -e "${YELLOW}如果需要，可以查看之前的配置备份: $CURRENT_ETC_SSH_BACKUP ${NC}"
fi

echo -e "${GREEN}恢复过程完成${NC}"
echo -e "${YELLOW}日志文件已保存到: $LOG_FILE${NC}"

exit 0 