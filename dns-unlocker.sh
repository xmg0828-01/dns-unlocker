#!/bin/bash
# DNS+SS解锁脚本 v2.0
# 支持DNS解锁和Shadowsocks节点解锁
# 作者: Claude

# 颜色定义
RED="\033[31m"
GREEN="\033[32m" 
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN="\033[0m"

# 配置文件路径
CONFIG_DIR="/etc/dnsmasq.d"
DNSMASQ_CONFIG="/etc/dnsmasq.conf"
SS_CONFIG="/etc/shadowsocks-libev/config.json"
SUBSCRIBE_CONFIG="/etc/shadowsocks-libev/subscribe.conf"
DNS_CONFIG="/etc/resolv.conf"

# 检查root权限
check_root() {
  [[ $EUID != 0 ]] && echo -e "${RED}错误: 请使用root权限运行此脚本${PLAIN}" && exit 1
}

# 检查系统
check_system() {
  if [ -f /etc/redhat-release ]; then
    release="centos"
  elif grep -Eqi "debian" /etc/issue; then
    release="debian"
  elif grep -Eqi "ubuntu" /etc/issue; then
    release="ubuntu"
  else
    echo -e "${RED}不支持的操作系统!${PLAIN}" && exit 1
  fi
}

# 安装基础软件包
install_base() {
  if [[ ${release} == "centos" ]]; then
    yum install -y epel-release
    yum install -y wget curl unzip tar crontabs
  else
    apt update
    apt install -y wget curl unzip tar cron
  fi
}

# 安装DNS解锁所需软件
install_dns() {
  echo -e "${BLUE}安装DNS解锁所需软件...${PLAIN}"
  if [[ ${release} == "centos" ]]; then
    yum install -y dnsmasq
  else
    apt install -y dnsmasq
  fi
}

# 安装Shadowsocks
install_ss() {
  echo -e "${BLUE}安装Shadowsocks...${PLAIN}"
  if [[ ${release} == "centos" ]]; then
    yum install -y shadowsocks-libev simple-obfs
  else
    apt install -y shadowsocks-libev simple-obfs
  fi
}

# 配置DNS服务
setup_dns() {
  echo -e "${BLUE}配置DNS服务...${PLAIN}"
  # 备份原配置
  [ -f ${DNSMASQ_CONFIG} ] && cp ${DNSMASQ_CONFIG} ${DNSMASQ_CONFIG}.bak
  
  # 创建新配置
  cat > ${DNSMASQ_CONFIG} << EOF
# DNS配置
no-resolv
no-poll
cache-size=2048
dns-forward-max=2048
server=8.8.8.8
server=8.8.4.4
listen-address=127.0.0.1
conf-dir=/etc/dnsmasq.d
EOF

  # 创建配置目录
  mkdir -p ${CONFIG_DIR}
  
  # 重启服务
  systemctl restart dnsmasq
  systemctl enable dnsmasq
  
  echo -e "${GREEN}DNS服务配置完成${PLAIN}"
}

# 配置Netflix解锁
setup_netflix() {
  echo -e "${BLUE}配置Netflix解锁...${PLAIN}"
  read -p "请输入Netflix解锁IP: " netflix_ip
  if [ -z "$netflix_ip" ]; then
    echo -e "${RED}错误:IP不能为空${PLAIN}"
    return
  fi
  
  cat > ${CONFIG_DIR}/netflix.conf << EOF
# Netflix解锁配置
address=/netflix.com/${netflix_ip}
address=/nflximg.com/${netflix_ip}
address=/nflximg.net/${netflix_ip}
address=/nflxvideo.net/${netflix_ip}
address=/nflxso.net/${netflix_ip}
address=/nflxext.com/${netflix_ip}
EOF

  echo -e "${GREEN}Netflix解锁配置完成${PLAIN}"
  systemctl restart dnsmasq
}

# 配置Disney+解锁  
setup_disney() {
  echo -e "${BLUE}配置Disney+解锁...${PLAIN}"
  read -p "请输入Disney+解锁IP: " disney_ip
  if [ -z "$disney_ip" ]; then
    echo -e "${RED}错误:IP不能为空${PLAIN}"
    return
  fi

  cat > ${CONFIG_DIR}/disney.conf << EOF
# Disney+解锁配置  
address=/disney.com/${disney_ip}
address=/disneyplus.com/${disney_ip}
address=/dssott.com/${disney_ip}
address=/bamgrid.com/${disney_ip}
address=/disney-plus.net/${disney_ip}
EOF

  echo -e "${GREEN}Disney+解锁配置完成${PLAIN}"
  systemctl restart dnsmasq
}

# 配置自定义域名解锁
setup_custom() {
  echo -e "${BLUE}配置自定义域名解锁...${PLAIN}"
  read -p "请输入域名: " domain
  read -p "请输入解锁IP: " ip
  
  if [ -z "$domain" ] || [ -z "$ip" ]; then
    echo -e "${RED}错误:域名和IP不能为空${PLAIN}"
    return
  fi

  cat > ${CONFIG_DIR}/custom_${domain}.conf << EOF
# 自定义域名解锁配置
address=/${domain}/${ip}
EOF

  echo -e "${GREEN}自定义域名解锁配置完成${PLAIN}"
  systemctl restart dnsmasq
}
# SS节点管理相关函数
# ==================

# SS节点配置结构
SS_NODE_CONFIG="/etc/shadowsocks-libev/nodes/"
mkdir -p $SS_NODE_CONFIG

# 添加SS节点
add_ss_node() {
  echo -e "${BLUE}添加SS节点${PLAIN}"
  echo -e "请选择添加方式:"
  echo -e "${YELLOW}1. 手动添加节点${PLAIN}"
  echo -e "${YELLOW}2. 订阅链接导入${PLAIN}"
  read -p "请选择[1-2]: " choice

  case $choice in
    1) add_ss_manual ;;
    2) add_ss_subscribe ;;
    *) echo -e "${RED}无效的选择${PLAIN}" ;;
  esac
}

# 手动添加SS节点
add_ss_manual() {
  echo -e "${BLUE}手动添加SS节点${PLAIN}"
  read -p "节点名称: " name
  read -p "服务器地址: " server
  read -p "端口: " port
  read -p "密码: " password
  read -p "加密方式(默认:aes-256-gcm): " method
  
  [ -z "$method" ] && method="aes-256-gcm"
  
  # 生成节点配置文件
  cat > ${SS_NODE_CONFIG}${name}.json << EOF
{
    "server":"${server}",
    "server_port":${port},
    "password":"${password}",
    "method":"${method}",
    "timeout":300,
    "fast_open":false
}
EOF

  echo -e "${GREEN}节点 ${name} 添加成功${PLAIN}"
}

# 通过订阅链接添加节点
add_ss_subscribe() {
  echo -e "${BLUE}添加SS订阅${PLAIN}"
  read -p "请输入订阅链接: " url
  
  if [ -z "$url" ]; then
    echo -e "${RED}订阅链接不能为空${PLAIN}"
    return
  fi

  # 下载并解析订阅内容
  echo -e "${YELLOW}正在获取订阅内容...${PLAIN}"
  subscribe_content=$(curl -sL "$url")
  
  if [ -z "$subscribe_content" ]; then
    echo -e "${RED}获取订阅内容失败${PLAIN}"
    return
  }

  # 解码Base64内容
  nodes_config=$(echo $subscribe_content | base64 -d)
  
  # 解析并保存每个节点
  echo "$nodes_config" | while IFS= read -r line; do
    if [[ $line =~ ^ss:// ]]; then
      node_info=$(echo ${line#ss://} | base64 -d)
      method=$(echo $node_info | cut -d: -f1)
      password=$(echo $node_info | cut -d: -f2 | cut -d@ -f1)
      server=$(echo $node_info | cut -d@ -f2 | cut -d: -f1)
      port=$(echo $node_info | cut -d: -f3)
      name=$(echo $node_info | cut -d# -f2)
      
      # 保存节点配置
      cat > ${SS_NODE_CONFIG}${name}.json << EOF
{
    "server":"${server}",
    "server_port":${port},
    "password":"${password}",
    "method":"${method}",
    "timeout":300,
    "fast_open":false
}
EOF
      echo -e "${GREEN}已添加节点: ${name}${PLAIN}"
    fi
  done
}

# 列出所有节点
list_ss_nodes() {
  echo -e "${BLUE}SS节点列表:${PLAIN}"
  echo -e "------------------------"
  
  i=1
  for node in ${SS_NODE_CONFIG}*.json; do
    if [ -f "$node" ]; then
      name=$(basename "$node" .json)
      server=$(grep "server" "$node" | cut -d'"' -f4)
      port=$(grep "server_port" "$node" | cut -d':' -f2 | tr -d ' ,')
      echo -e "${GREEN}$i. $name${PLAIN}"
      echo -e "   服务器: ${YELLOW}$server:$port${PLAIN}"
      ((i++))
    fi
  done
  
  echo -e "------------------------"
}

# 切换SS节点
switch_ss_node() {
  list_ss_nodes
  
  read -p "请选择要使用的节点编号: " number
  
  i=1
  for node in ${SS_NODE_CONFIG}*.json; do
    if [ "$i" = "$number" ]; then
      cp "$node" $SS_CONFIG
      systemctl restart shadowsocks-libev
      echo -e "${GREEN}已切换到节点: $(basename "$node" .json)${PLAIN}"
      return
    fi
    ((i++))
  done
  
  echo -e "${RED}无效的节点编号${PLAIN}"
}

# 删除SS节点
delete_ss_node() {
  list_ss_nodes
  
  read -p "请选择要删除的节点编号: " number
  
  i=1
  for node in ${SS_NODE_CONFIG}*.json; do
    if [ "$i" = "$number" ]; then
      rm -f "$node"
      echo -e "${GREEN}已删除节点: $(basename "$node" .json)${PLAIN}"
      return
    fi
    ((i++))
  done
  
  echo -e "${RED}无效的节点编号${PLAIN}"
}

# 测试节点延迟
test_ss_nodes() {
  echo -e "${BLUE}测试节点延迟...${PLAIN}"
  
  for node in ${SS_NODE_CONFIG}*.json; do
    if [ -f "$node" ]; then
      name=$(basename "$node" .json)
      server=$(grep "server" "$node" | cut -d'"' -f4)
      
      echo -n -e "节点 ${YELLOW}$name${PLAIN} 延迟: "
      delay=$(ping -c 3 $server | grep 'avg' | cut -d'/' -f4)
      
      if [ -n "$delay" ]; then
        echo -e "${GREEN}${delay}ms${PLAIN}"
      else
        echo -e "${RED}超时${PLAIN}"
      fi
    fi
  done
}

# SS节点管理菜单
ss_menu() {
  while true; do
    echo -e "\n${YELLOW}SS节点管理${PLAIN}"
    echo -e "${BLUE}------------------------${PLAIN}"
    echo -e "${GREEN}1.${PLAIN} 添加SS节点"
    echo -e "${GREEN}2.${PLAIN} 查看节点列表"
    echo -e "${GREEN}3.${PLAIN} 切换使用节点"
    echo -e "${GREEN}4.${PLAIN} 删除SS节点"
    echo -e "${GREEN}5.${PLAIN} 测试节点延迟"
    echo -e "${GREEN}0.${PLAIN} 返回主菜单"
    echo -e "${BLUE}------------------------${PLAIN}"
    
    read -p "请选择: " choice
    
    case $choice in
      1) add_ss_node ;;
      2) list_ss_nodes ;;
      3) switch_ss_node ;;
      4) delete_ss_node ;;
      5) test_ss_nodes ;;
      0) break ;;
      *) echo -e "${RED}无效的选择${PLAIN}" ;;
    esac
  done
}
# 解锁模式切换
# ===========

# 切换到DNS解锁模式
switch_to_dns() {
  echo -e "${BLUE}切换到DNS解锁模式...${PLAIN}"
  
  # 停止SS服务
  systemctl stop shadowsocks-libev
  
  # 配置系统DNS为本地DNS服务器
  cat > $DNS_CONFIG << EOF
nameserver 127.0.0.1
EOF

  echo -e "${GREEN}已切换到DNS解锁模式${PLAIN}"
}

# 切换到SS代理模式
switch_to_ss() {
  echo -e "${BLUE}切换到SS代理模式...${PLAIN}"
  
  # 检查是否有可用节点
  if [ ! -f $SS_CONFIG ]; then
    echo -e "${RED}错误: 未配置SS节点${PLAIN}"
    return
  fi
  
  # 启动SS服务
  systemctl start shadowsocks-libev
  
  # 配置系统DNS为SS节点的DNS
  server=$(grep "server" $SS_CONFIG | cut -d'"' -f4)
  cat > $DNS_CONFIG << EOF
nameserver $server
EOF

  echo -e "${GREEN}已切换到SS代理模式${PLAIN}"
}

# 检查服务状态
check_status() {
  echo -e "${BLUE}服务状态:${PLAIN}"
  echo -e "------------------------"
  
  # 检查DNS服务
  if systemctl is-active dnsmasq >/dev/null 2>&1; then
    echo -e "DNS服务: ${GREEN}运行中${PLAIN}"
  else
    echo -e "DNS服务: ${RED}未运行${PLAIN}"
  fi
  
  # 检查SS服务
  if systemctl is-active shadowsocks-libev >/dev/null 2>&1; then
    echo -e "SS服务: ${GREEN}运行中${PLAIN}"
    current_node=$(basename $(readlink -f $SS_CONFIG) .json 2>/dev/null)
    [ -n "$current_node" ] && echo -e "当前节点: ${GREEN}$current_node${PLAIN}"
  else
    echo -e "SS服务: ${RED}未运行${PLAIN}"
  fi
  
  # 显示当前DNS配置
  echo -e "\n当前DNS配置:"
  cat $DNS_CONFIG
  
  echo -e "------------------------"
}

# 重置所有配置
reset_all() {
  echo -e "${YELLOW}警告: 该操作将重置所有配置!${PLAIN}"
  read -p "确定要继续吗? (y/n): " confirm
  
  if [ "$confirm" != "y" ]; then
    return
  fi
  
  echo -e "${BLUE}重置所有配置...${PLAIN}"
  
  # 停止服务
  systemctl stop dnsmasq shadowsocks-libev
  
  # 删除配置文件
  rm -rf $CONFIG_DIR/*
  rm -rf $SS_NODE_CONFIG/*
  rm -f $SS_CONFIG
  
  # 恢复默认DNS配置
  cat > $DNS_CONFIG << EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF

  echo -e "${GREEN}所有配置已重置${PLAIN}"
}

# 解锁模式菜单
mode_menu() {
  while true; do
    echo -e "\n${YELLOW}解锁模式切换${PLAIN}"
    echo -e "${BLUE}------------------------${PLAIN}"
    echo -e "${GREEN}1.${PLAIN} 切换到DNS解锁模式"
    echo -e "${GREEN}2.${PLAIN} 切换到SS代理模式"
    echo -e "${GREEN}0.${PLAIN} 返回主菜单"
    echo -e "${BLUE}------------------------${PLAIN}"
    
    read -p "请选择: " choice
    
    case $choice in
      1) switch_to_dns ;;
      2) switch_to_ss ;;
      0) break ;;
      *) echo -e "${RED}无效的选择${PLAIN}" ;;
    esac
  done
}

# DNS解锁菜单
dns_menu() {
  while true; do
    echo -e "\n${YELLOW}DNS解锁管理${PLAIN}"
    echo -e "${BLUE}------------------------${PLAIN}"
    echo -e "${GREEN}1.${PLAIN} 配置Netflix解锁"
    echo -e "${GREEN}2.${PLAIN} 配置Disney+解锁"
    echo -e "${GREEN}3.${PLAIN} 配置自定义域名解锁"
    echo -e "${GREEN}0.${PLAIN} 返回主菜单"
    echo -e "${BLUE}------------------------${PLAIN}"
    
    read -p "请选择: " choice
    
    case $choice in
      1) setup_netflix ;;
      2) setup_disney ;;
      3) setup_custom ;;
      0) break ;;
      *) echo -e "${RED}无效的选择${PLAIN}" ;;
    esac
  done
}

# 主菜单
main_menu() {
  while true; do
    clear
    echo -e "${YELLOW}DNS+SS解锁脚本 v2.0${PLAIN}"
    echo -e "${BLUE}=============================${PLAIN}"
    echo -e "${GREEN}1.${PLAIN} DNS解锁管理"
    echo -e "${GREEN}2.${PLAIN} SS节点管理"
    echo -e "${GREEN}3.${PLAIN} 解锁模式切换"
    echo -e "${GREEN}4.${PLAIN} 查看服务状态"
    echo -e "${GREEN}5.${PLAIN} 重置所有配置"
    echo -e "${GREEN}0.${PLAIN} 退出脚本"
    echo -e "${BLUE}=============================${PLAIN}"
    
    read -p "请选择: " choice
    
    case $choice in
      1) dns_menu ;;
      2) ss_menu ;;
      3) mode_menu ;;
      4) check_status ;;
      5) reset_all ;;
      0) 
        echo -e "${GREEN}感谢使用!${PLAIN}"
        exit 0
        ;;
      *) echo -e "${RED}无效的选择${PLAIN}" ;;
    esac
  done
}

# 程序入口
main() {
  check_root
  check_system
  
  # 首次运行时安装必要组件
  if [ ! -f "/etc/dns-ss-unlock.installed" ]; then
    echo -e "${BLUE}首次运行,开始安装必要组件...${PLAIN}"
    install_base
    install_dns
    install_ss
    setup_dns
    touch /etc/dns-ss-unlock.installed
  fi
  
  main_menu
}

# 启动脚本
main "$@"
