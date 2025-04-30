# OpenSSH 9.8p1 离线升级工具

## 项目概述

本项目提供了一套完整的工具，用于在离线环境中安装或升级OpenSSH到9.8p1版本。根据系统OpenSSL版本，工具会自动决定是否同时升级OpenSSL到1.1.1版本。整个过程分为两步：在有网络环境准备安装包，然后在离线环境完成安装。

## 系统要求

支持以下系统：

- **Ubuntu/Debian**：Ubuntu 18.04/20.04/22.04，Debian 9/10/11
- **CentOS**：CentOS 7.x 及其他基于RHEL的发行版

其他要求：
- Root权限
- 对于在线环境：稳定的网络连接
- 对于离线环境：约100MB的可用磁盘空间

## 目录结构

根据您的操作系统，请进入相应的目录：

- `ubuntu/` - 包含适用于Ubuntu/Debian系统的工具
- `centos/` - 包含适用于CentOS 7系统的工具

## Ubuntu/Debian版本工具

Ubuntu/Debian目录下包含以下工具：

1. `download_openssh98.sh` - 在有网络环境下载OpenSSH源码和依赖
2. `check_openssh_deps.sh` - 检查依赖并准备安装包
3. `install_openssh98_offline.sh` - 离线安装OpenSSH 9.8p1
4. `restore_openssh_backup.sh` - 恢复到原始安装（如果安装失败）

## CentOS 7版本工具

CentOS目录下包含以下工具：

1. `download_openssh98_centos.sh` - 在有网络环境下载OpenSSH和OpenSSL源码及依赖（兼容旧系统）
2. `check_openssh_deps_centos.sh` - 检查依赖并准备安装包
3. `install_openssh98_offline_centos.sh` - 离线安装OpenSSH 9.8p1和OpenSSL 1.1.1(如需)
4. `restore_openssh_centos.sh` - 恢复到原始安装（如果安装失败）

## 使用流程

### 1. 在有网络环境准备安装包

**Ubuntu/Debian系统：**
```bash
cd ubuntu
sudo ./download_openssh98.sh
sudo ./check_openssh_deps.sh
# 选择菜单选项5: 集成依赖和源码
```

**CentOS 7系统：**
```bash
cd centos
sudo ./download_openssh98_centos.sh
# 或者使用依赖检查工具
sudo ./check_openssh_deps_centos.sh
# 选择菜单选项5: 集成依赖和源码
```

以上命令将创建`openssh_9.8p1_source_deps_package.tar.gz`或`openssh_9.8p1_source_deps_package_updated.tar.gz`安装包。

### 2. 在离线环境安装

将生成的安装包传输到离线环境，然后执行以下操作：

**Ubuntu/Debian系统：**
```bash
cd ubuntu
sudo ./install_openssh98_offline.sh
```

**CentOS 7系统：**
```bash
cd centos
sudo ./install_openssh98_offline_centos.sh
```

## 重要特性

- **智能依赖检测**：自动检测系统上缺失的依赖
- **OpenSSL兼容性**：根据系统OpenSSL版本智能决定是否升级
- **自动备份**：安装前自动备份原有配置和二进制文件
- **恢复机制**：提供恢复脚本，在安装失败时恢复到原始状态
- **日志记录**：详细记录安装过程，便于故障排查
- **系统兼容性**：增强的下载脚本支持旧版系统和工具

## 注意事项

1. 安装前会自动备份现有的SSH配置和二进制文件，但仍建议手动备份重要数据
2. CentOS 7版本支持根据需要升级OpenSSL到1.1.1版本
3. 如果安装过程中断或失败，请使用相应的恢复脚本
4. 安装完成后，建议在新终端窗口测试SSH连接，确保功能正常
5. 针对旧版系统，下载脚本已做兼容性处理，能适应不同版本的wget和包管理器

## 故障排除

1. **安装包损坏或不完整**：
   - 检查安装包大小（应约为100MB）
   - 重新在联网环境下载和准备安装包
   - 确保文件传输使用二进制模式

2. **依赖问题**：
   - 运行依赖检查工具确认所有依赖已包含
   - 检查相关的日志文件（install.log）获取详细错误信息

3. **安装失败**：
   - 使用恢复脚本回滚变更：`./restore_openssh_backup.sh`或`./restore_openssh_centos.sh`
   - 检查安装日志获取错误详情

4. **下载工具兼容性问题**：
   - 如遇到wget参数不兼容问题，已优化脚本自动适应
   - 如果yumdownloader不可用，脚本会自动切换到yum模式下载

## 技术支持

如有任何问题或建议，请联系项目维护者或提交问题报告。

---

*最后更新: 2024年* 