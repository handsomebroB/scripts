#!/bin/bash

# 设置文本颜色
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # 无颜色

echo -e "${BLUE}===== 开始安装 Docker 和 Docker Compose =====${NC}"

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 权限运行此脚本"
  exit 1
fi

# 检查 Docker 是否已安装
if command -v docker &> /dev/null; then
  echo -e "${GREEN}Docker 已安装在系统中，跳过 Docker 安装步骤${NC}"
  
  # 检查 Docker 是否正在运行
  if systemctl is-active --quiet docker; then
    echo -e "${GREEN}Docker 服务正在运行${NC}"
  else
    echo -e "${GREEN}启动 Docker 服务...${NC}"
    systemctl start docker
    systemctl enable docker
  fi
else
  # 更新软件包列表
  echo -e "${GREEN}更新软件包列表...${NC}"
  apt update -y

  # 安装必要的依赖
  echo -e "${GREEN}安装依赖包...${NC}"
  apt install -y apt-transport-https ca-certificates curl software-properties-common gnupg

  # 添加 Docker 的官方 GPG 密钥
  echo -e "${GREEN}添加 Docker 官方 GPG 密钥...${NC}"

  # 根据 Ubuntu 版本选择适当的安装方法
  UBUNTU_VERSION=$(lsb_release -rs)
  if [[ "$UBUNTU_VERSION" == "20.04" ]]; then
    # Ubuntu 20.04 的安装方法
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
    add-apt-repository "deb [arch=$(dpkg --print-architecture)] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
  else
    # Ubuntu 22.04+ 的安装方法
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    # 设置 Docker 稳定版仓库
    echo -e "${GREEN}设置 Docker 仓库...${NC}"
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  fi

  # 再次更新软件包列表
  echo -e "${GREEN}更新软件包列表...${NC}"
  apt update -y

  # 安装 Docker Engine
  echo -e "${GREEN}安装 Docker Engine...${NC}"
  apt install -y docker-ce docker-ce-cli containerd.io

  # 启动 Docker 服务并设置为开机自启
  echo -e "${GREEN}启动 Docker 服务并设置开机自启...${NC}"
  systemctl start docker
  systemctl enable docker

  # 检查 Docker 是否安装成功
  if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker 安装失败，请检查错误信息${NC}"
    exit 1
  fi
  echo -e "${GREEN}Docker 安装成功！${NC}"
fi

# 分别检查 Docker Compose 的不同版本
if command -v docker-compose &> /dev/null; then
  echo -e "${GREEN}Docker Compose (独立版本) 已安装在系统中${NC}"
  COMPOSE_INSTALLED=true
elif docker compose version &> /dev/null; then
  echo -e "${GREEN}Docker Compose (插件版本) 已安装在系统中${NC}"
  COMPOSE_INSTALLED=true
else
  COMPOSE_INSTALLED=false
  echo -e "${GREEN}安装 Docker Compose...${NC}"
  
  # 根据 Ubuntu 版本选择适当的安装方法
  UBUNTU_VERSION=$(lsb_release -rs)
  if [[ "$UBUNTU_VERSION" == "20.04" ]]; then
    # 在 Ubuntu 20.04 上安装 Docker Compose V2 作为插件
    apt update
    apt install -y docker-compose-plugin
  else
    # 对于更新的 Ubuntu 版本
    apt update
    apt install -y docker-compose-plugin
  fi

  # 检查 Docker Compose 是否安装成功
  if ! docker compose version &> /dev/null; then
    echo -e "${RED}Docker Compose 插件安装失败，尝试安装独立版本...${NC}"
    
    # 安装独立版本的 Docker Compose
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
    curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    if ! command -v docker-compose &> /dev/null; then
      echo -e "${RED}Docker Compose 安装失败，请检查错误信息${NC}"
      exit 1
    fi
  fi
  echo -e "${GREEN}Docker Compose 安装成功！${NC}"
fi

echo -e "${BLUE}===== 开始配置 YOURLS =====${NC}"

# 创建 YOURLS 工作目录
echo -e "${GREEN}创建 YOURLS 工作目录...${NC}"
mkdir -p /opt/yourls
cd /opt/yourls

# 收集用户输入 - 修复交互问题
echo -e "${BLUE}请提供以下信息以配置 YOURLS:${NC}"
echo -n "网站域名 (例如: yourls.example.com): "
read SITE_URL
echo -n "MySQL 根密码: "
read MYSQL_ROOT_PASSWORD
echo -n "YOURLS 数据库名称 (默认: yourls): "
read YOURLS_DB_NAME
YOURLS_DB_NAME=${YOURLS_DB_NAME:-yourls}
echo -n "YOURLS 数据库用户 (默认: yourls): "
read YOURLS_DB_USER
YOURLS_DB_USER=${YOURLS_DB_USER:-yourls}
echo -n "YOURLS 数据库密码: "
read YOURLS_DB_PASSWORD
echo -n "YOURLS 管理员用户名: "
read YOURLS_ADMIN_USER
echo -n "YOURLS 管理员密码: "
read YOURLS_ADMIN_PASSWORD
echo -n "YOURLS 网站标题 (默认: My URL Shortener): "
read YOURLS_SITE_TITLE
YOURLS_SITE_TITLE=${YOURLS_SITE_TITLE:-"My URL Shortener"}

# 创建 docker-compose.yml 文件
echo -e "${GREEN}创建 Docker Compose 配置文件...${NC}"
cat > docker-compose.yml << EOF
version: '3'

services:
  db:
    image: mysql:5.7
    container_name: yourls-mysql
    restart: always
    volumes:
      - mysql_data:/var/lib/mysql
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      MYSQL_DATABASE: ${YOURLS_DB_NAME}
      MYSQL_USER: ${YOURLS_DB_USER}
      MYSQL_PASSWORD: ${YOURLS_DB_PASSWORD}
    networks:
      - yourls-network

  yourls:
    image: yourls:latest
    container_name: yourls
    restart: always
    depends_on:
      - db
    ports:
      - "80:80"
    environment:
      YOURLS_DB_HOST: db
      YOURLS_DB_NAME: ${YOURLS_DB_NAME}
      YOURLS_DB_USER: ${YOURLS_DB_USER}
      YOURLS_DB_PASS: ${YOURLS_DB_PASSWORD}
      YOURLS_SITE: http://${SITE_URL}
      YOURLS_USER: ${YOURLS_ADMIN_USER}
      YOURLS_PASS: ${YOURLS_ADMIN_PASSWORD}
      YOURLS_PRIVATE: "true"
      YOURLS_SITE_TITLE: "${YOURLS_SITE_TITLE}"
    networks:
      - yourls-network

networks:
  yourls-network:
    driver: bridge

volumes:
  mysql_data:
EOF

# 启动 YOURLS - 根据安装的 Docker Compose 类型选择命令
echo -e "${GREEN}启动 YOURLS 容器...${NC}"
if command -v docker-compose &> /dev/null; then
  docker-compose up -d
else
  docker compose up -d
fi

echo -e "${BLUE}===== 安装完成 =====${NC}"
echo -e "${GREEN}YOURLS 已成功部署！${NC}"
echo -e "请访问 http://${SITE_URL}/admin/ 进入管理界面"
echo -e "管理员用户名: ${YOURLS_ADMIN_USER}"
echo -e "管理员密码: ${YOURLS_ADMIN_PASSWORD}"
echo -e "${BLUE}=================================================================${NC}"
echo -e "${GREEN}注意: 如果您使用的是云服务器，请确保已开放 80 端口的访问权限${NC}"
echo -e "${GREEN}如果您想使用域名访问，请确保已将域名 ${SITE_URL} 解析到此服务器的 IP 地址${NC}"
