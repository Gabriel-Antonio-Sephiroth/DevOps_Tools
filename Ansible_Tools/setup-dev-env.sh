#!/bin/bash
set -e

echo "=== Rocky Linux 10 开发环境配置脚本 ==="

# 0. 系统配置
echo ">>> 系统配置..."
# 卸载防火墙、图形界面，切换字符界面，关闭selinux
systemctl disable firewalld --now
dnf remove -y firewalld
systemctl set-default multi-user.target
systemctl isolate multi-user.target
# 删除 X Window System（通用图形底层）
sudo dnf remove -y xorg-x11-\*
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
# 设置DNS解析
echo "nameserver 223.5.5.5" >> /etc/resolv.conf
echo "nameserver 119.29.29.29" >> /etc/resolv.conf

# 1. 包管理器更新与清理
echo ">>> 更新yum源..."
# 配置阿里云源
sed -e 's|^mirrorlist=|#mirrorlist=|g' \
  -e 's|^#baseurl=http://dl.rockylinux.org/$contentdir|baseurl=https://mirrors.aliyun.com/rockylinux|g' \
  -i.bak \
  /etc/yum.repos.d/rocky*.repo
echo ">>> 配置扩展仓库..."
# 安装EPEL并替换为阿里云镜像
dnf install -y epel-release
dnf config-manager --add-repo http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
sed -i 's/$releasever/9/g' /etc/yum.repos.d/docker-ce.repo
# 启用CRB仓库（CodeReady Builder，之前叫PowerTools）
dnf config-manager --set-enabled crb
# 更新系统
dnf update -y
# 删除孤立的依赖包
dnf autoremove -y
# 清理缓存
dnf clean all

# 2. 安装开发工具
echo ">>> 安装开发工具..."
# 开发工具组（包含gcc、g++、make等）
dnf groupinstall -y "Development Tools"
# 安装依赖
dnf install -y dnf-utils device-mapper-persistent-data lvm2
# 安装java环境
dnf install -y java-21-openjdk-devel
# 安装 pip,rocky自带python
dnf install -y python3-pip
# 安装常用工具
dnf install -y createrepo_c vim-enhanced bash-completion wget curl git tree htop ncdu net-tools bind-utils telnet lsof unzip zip sshpass
# 安装Docker
dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
dnf install -y docker-ce --allowerasing
# 安装MySQL
dnf install -y mysql8.4-server.x86_64
# 安装 Ansible
pip install ansible

# 清理临时文件
dnf makecache
dnf clean all

# 3. 配置环境变量
echo ">>> 配置环境变量..."
# 设置Docker镜像源
mkdir -p /etc/docker
tee /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": [
    "https://docker.xuanyuan.me",
    "https://docker.m.daocloud.io",
    "https://hub-mirror.c.163.com",
    "https://docker.mirrors.ustc.edu.cn",
    "https://mirror.baidubce.com",
    "https://docker.1ms.run",
    "https://registry-1.docker.io"
  ],
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF
# 设置环境变量并重载配置
cat >> ~/.vimrc << 'EOF'
" Tab 设置为 2 个空格
set tabstop=2      " Tab 显示的宽度为 2 个空格
set shiftwidth=2   " 缩进宽度为 2 个空格
set expandtab      " 将 Tab 键转换为空格
EOF
sed -i '2i # 历史命令增强\nexport HISTSIZE=10000\nexport HISTFILESIZE=20000\nexport HISTTIMEFORMAT="%Y-%m-%d %H:%M:%S "' ~/.bashrc
echo 'export JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))' >> ~/.bashrc
echo 'export PATH=$JAVA_HOME/bin:$PATH' >> ~/.bashrc
source /etc/profile.d/bash_completion.sh
source ~/.bashrc
echo 1 > /proc/sys/net/ipv4/ip_forward

# 4. 设置启动服务与自启
echo ">>> 设置服务自启..."
# 启动MySQL
systemctl enable mysqld --now
# 启动Docker
systemctl enable docker --now

# 验证各组件版本
echo "=== 配置完成！验证各组件版本 ==="
echo "=== Java ===" && java --version
echo "=== Python ===" && python3 --version
echo "=== Pip ===" && pip3 --version
echo "=== Ansible ===" && ansible --version
echo "=== Ansible-doc ===" && ansible-doc -l | wc -l
echo "=== MySQL ===" && mysql --version
echo "=== Docker ===" && docker --version
echo "=== Docker Compose ===" && docker compose version
echo "=== 验证完成正在重启, 15秒后生效 ==="
sleep 15
reboot
