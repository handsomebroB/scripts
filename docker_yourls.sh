#!/bin/bash

# 设置文本颜色
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # 无颜色

YOURLS_DIR="/opt/yourls"
YOURLS_DATA_DIR="/opt/yourls-data"  # 持久化数据目录

echo -e "${BLUE}===== Docker 和 YOURLS 安装脚本 =====${NC}"

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 权限运行此脚本"
  exit 1
fi

# 检查是否以脚本形式运行还是通过管道运行
if [ -t 0 ]; then
  # 终端交互模式
  INTERACTIVE=true
else
  # 非交互模式 (通过管道运行)
  INTERACTIVE=false
  echo -e "${YELLOW}以非交互模式运行，将使用默认选项（全部选择'是'）${NC}"
fi

# 用于获取用户确认的函数
get_user_confirmation() {
  if [ "$INTERACTIVE" = true ]; then
    echo -n "$1 (y/n): "
    read user_choice
    if [[ "$user_choice" =~ ^[Yy]$ ]]; then
      return 0  # 用户选择"是"
    else
      return 1  # 用户选择"否"
    fi
  else
    # 非交互模式下默认选择"是"
    echo -e "${YELLOW}自动选择: 是${NC}"
    return 0
  fi
}

# 检查 Docker 是否已安装
if command -v docker &> /dev/null; then
  echo -e "${GREEN}检测到 Docker 已安装在系统中${NC}"
  if get_user_confirmation "是否继续安装过程？"; then
    echo -e "${GREEN}继续安装过程...${NC}"
    
    # 检查 Docker 是否正在运行
    if systemctl is-active --quiet docker; then
      echo -e "${GREEN}Docker 服务正在运行${NC}"
    else
      echo -e "${GREEN}Docker 服务未运行，正在启动...${NC}"
      systemctl start docker
      systemctl enable docker
    fi
  else
    echo -e "${YELLOW}用户选择终止安装${NC}"
    exit 0
  fi
else
  echo -e "${YELLOW}未检测到 Docker${NC}"
  if get_user_confirmation "是否安装 Docker？"; then
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
  else
    echo -e "${YELLOW}用户选择不安装 Docker，退出安装程序${NC}"
    exit 0
  fi
fi

# 分别检查 Docker Compose 的不同版本
if command -v docker-compose &> /dev/null; then
  echo -e "${GREEN}检测到 Docker Compose (独立版本) 已安装在系统中${NC}"
  if get_user_confirmation "是否继续安装过程？"; then
    echo -e "${GREEN}继续安装过程...${NC}"
    COMPOSE_CMD="docker-compose"
    COMPOSE_INSTALLED=true
  else
    echo -e "${YELLOW}用户选择终止安装${NC}"
    exit 0
  fi
elif docker compose version &> /dev/null; then
  echo -e "${GREEN}检测到 Docker Compose (插件版本) 已安装在系统中${NC}"
  if get_user_confirmation "是否继续安装过程？"; then
    echo -e "${GREEN}继续安装过程...${NC}"
    COMPOSE_CMD="docker compose"
    COMPOSE_INSTALLED=true
  else
    echo -e "${YELLOW}用户选择终止安装${NC}"
    exit 0
  fi
else
  echo -e "${YELLOW}未检测到 Docker Compose${NC}"
  if get_user_confirmation "是否安装 Docker Compose？"; then
    COMPOSE_INSTALLED=false
    echo -e "${GREEN}安装 Docker Compose...${NC}"
    
    # 根据 Ubuntu 版本选择适当的安装方法
    UBUNTU_VERSION=$(lsb_release -rs)
    if [[ "$UBUNTU_VERSION" == "20.04" ]]; then
      # 在 Ubuntu 20.04 上安装 Docker Compose V2 作为插件
      apt update
      apt install -y docker-compose-plugin
      if docker compose version &> /dev/null; then
        COMPOSE_CMD="docker compose"
        COMPOSE_INSTALLED=true
      fi
    else
      # 对于更新的 Ubuntu 版本
      apt update
      apt install -y docker-compose-plugin
      if docker compose version &> /dev/null; then
        COMPOSE_CMD="docker compose"
        COMPOSE_INSTALLED=true
      fi
    fi

    # 如果插件安装失败，尝试安装独立版本
    if [ "$COMPOSE_INSTALLED" = false ]; then
      echo -e "${YELLOW}Docker Compose 插件安装失败，尝试安装独立版本...${NC}"
      
      # 安装独立版本的 Docker Compose
      COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
      curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
      chmod +x /usr/local/bin/docker-compose
      
      if command -v docker-compose &> /dev/null; then
        COMPOSE_CMD="docker-compose"
        COMPOSE_INSTALLED=true
      else
        echo -e "${RED}Docker Compose 安装失败，请检查错误信息${NC}"
        exit 1
      fi
    fi
    echo -e "${GREEN}Docker Compose 安装成功！${NC}"
  else
    echo -e "${YELLOW}用户选择不安装 Docker Compose，退出安装程序${NC}"
    exit 0
  fi
fi

echo -e "${BLUE}===== 检查 YOURLS 配置 =====${NC}"

# 检查是否已存在 YOURLS 安装
if [ -f "${YOURLS_DIR}/docker-compose.yml" ]; then
  echo -e "${YELLOW}检测到已存在的 YOURLS 安装${NC}"
  if get_user_confirmation "是否卸载并重新安装 YOURLS？这不会删除持久化的数据"; then
    echo -e "${GREEN}停止并移除现有的 YOURLS 容器...${NC}"
    cd ${YOURLS_DIR}
    ${COMPOSE_CMD} down
    
    echo -e "${GREEN}保留持久化数据，仅删除配置文件...${NC}"
    rm -f ${YOURLS_DIR}/docker-compose.yml
  else
    echo -e "${YELLOW}用户选择保留现有的 YOURLS 安装，退出脚本${NC}"
    exit 0
  fi
else
  echo -e "${GREEN}未检测到现有的 YOURLS 安装${NC}"
  if get_user_confirmation "是否安装 YOURLS？"; then
    echo -e "${GREEN}准备安装 YOURLS...${NC}"
  else
    echo -e "${YELLOW}用户选择不安装 YOURLS，退出脚本${NC}"
    exit 0
  fi
fi

# 创建 YOURLS 工作目录和持久化数据目录
echo -e "${GREEN}创建 YOURLS 工作目录...${NC}"
mkdir -p ${YOURLS_DIR}
mkdir -p ${YOURLS_DATA_DIR}/mysql
mkdir -p ${YOURLS_DATA_DIR}/yourls-data
cd ${YOURLS_DIR}

# 预定义默认值，避免交互式输入问题
SITE_URL=${SITE_URL:-"yourls.example.com"}
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-"yourls_root_password"}
YOURLS_DB_NAME=${YOURLS_DB_NAME:-"yourls"}
YOURLS_DB_USER=${YOURLS_DB_USER:-"yourls"}
YOURLS_DB_PASSWORD=${YOURLS_DB_PASSWORD:-"yourls_password"}
YOURLS_ADMIN_USER=${YOURLS_ADMIN_USER:-"admin"}
YOURLS_ADMIN_PASSWORD=${YOURLS_ADMIN_PASSWORD:-"admin_password"}
YOURLS_SITE_TITLE=${YOURLS_SITE_TITLE:-"My URL Shortener"}

# 检查是否以脚本形式运行还是通过管道运行
if [ "$INTERACTIVE" = true ]; then
  # 终端交互模式
  echo -e "${BLUE}请提供以下信息以配置 YOURLS:${NC}"
  echo -n "网站域名 (例如: yourls.example.com): "
  read SITE_URL
  echo -n "MySQL 根密码: "
  read -s MYSQL_ROOT_PASSWORD
  echo
  echo -n "YOURLS 数据库名称 (默认: yourls): "
  read temp_db_name
  YOURLS_DB_NAME=${temp_db_name:-$YOURLS_DB_NAME}
  echo -n "YOURLS 数据库用户 (默认: yourls): "
  read temp_db_user
  YOURLS_DB_USER=${temp_db_user:-$YOURLS_DB_USER}
  echo -n "YOURLS 数据库密码: "
  read -s YOURLS_DB_PASSWORD
  echo
  echo -n "YOURLS 管理员用户名: "
  read YOURLS_ADMIN_USER
  echo -n "YOURLS 管理员密码: "
  read -s YOURLS_ADMIN_PASSWORD
  echo
  echo -n "YOURLS 网站标题 (默认: My URL Shortener): "
  read temp_title
  YOURLS_SITE_TITLE=${temp_title:-$YOURLS_SITE_TITLE}
else
  # 非交互模式 (通过管道运行)
  echo -e "${YELLOW}以非交互模式运行，使用默认配置或环境变量值${NC}"
  echo -e "${YELLOW}可以通过在命令前设置环境变量来自定义配置，例如:${NC}"
  echo -e "${YELLOW}SITE_URL=example.com MYSQL_ROOT_PASSWORD=secure curl -sL URL | bash${NC}"
  echo -e "${YELLOW}使用以下默认配置:${NC}"
  echo -e "网站域名: ${SITE_URL}"
  echo -e "YOURLS 数据库名称: ${YOURLS_DB_NAME}"
  echo -e "YOURLS 数据库用户: ${YOURLS_DB_USER}"
  echo -e "YOURLS 管理员用户名: ${YOURLS_ADMIN_USER}"
  echo -e "YOURLS 网站标题: ${YOURLS_SITE_TITLE}"
  echo -e "${YELLOW}注意: 密码未显示但已设置${NC}"
  echo -e "${YELLOW}如需自定义配置，请直接下载脚本并运行，而不是通过管道执行${NC}"
  echo -e "${YELLOW}将在 5 秒后继续...${NC}"
  sleep 5
fi

# 创建 docker-compose.yml 文件，使用持久化数据目录
echo -e "${GREEN}创建 Docker Compose 配置文件...${NC}"
cat > docker-compose.yml << EOF
version: '3'

services:
  db:
    image: mysql:5.7
    container_name: yourls-mysql
    restart: always
    volumes:
      - ${YOURLS_DATA_DIR}/mysql:/var/lib/mysql
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
    volumes:
      - ${YOURLS_DATA_DIR}/yourls-data:/var/www/html/user
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
EOF

# 保存配置信息到文件，方便用户查看
echo -e "${GREEN}保存配置信息...${NC}"
cat > ${YOURLS_DIR}/config_info.txt << EOF
YOURLS 配置信息:
=====================================
网站域名: ${SITE_URL}
数据库名称: ${YOURLS_DB_NAME}
数据库用户: ${YOURLS_DB_USER}
管理员用户名: ${YOURLS_ADMIN_USER}
网站标题: ${YOURLS_SITE_TITLE}
数据目录: ${YOURLS_DATA_DIR}
=====================================
EOF

# 启动 YOURLS
echo -e "${GREEN}启动 YOURLS 容器...${NC}"
${COMPOSE_CMD} up -d

echo -e "${BLUE}===== 安装完成 =====${NC}"
echo -e "${GREEN}YOURLS 已成功部署！${NC}"
echo -e "请访问 http://${SITE_URL}/admin/ 进入管理界面"
echo -e "管理员用户名: ${YOURLS_ADMIN_USER}"
echo -e "管理员密码: (已设置，请参见配置记录)"
echo -e "${BLUE}=================================================================${NC}"
echo -e "${GREEN}注意事项:${NC}"
echo -e "1. 如果您使用的是云服务器，请确保已开放 80 端口的访问权限"
echo -e "2. 如果您想使用域名访问，请确保已将域名 ${SITE_URL} 解析到此服务器的 IP 地址"
echo -e "3. YOURLS 数据已持久化到 ${YOURLS_DATA_DIR} 目录，重新安装不会丢失数据"
echo -e "4. 如需备份数据，请备份 ${YOURLS_DATA_DIR} 目录"
echo -e "5. 配置信息已保存到 ${YOURLS_DIR}/config_info.txt 文件中"
echo -e "${BLUE}=================================================================${NC}"
