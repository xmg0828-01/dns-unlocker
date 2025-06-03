#!/bin/bash
# DNS+SS解锁脚本 v2.1
# 支持DNS解锁和SS节点解锁

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

# 解锁Netflix
unlock_netflix() {
  echo -e "${BLUE}Netflix解锁配置${PLAIN}"
  echo -e "------------------------"
  echo -e "1. DNS解锁模式"
  echo -e "2. SS节点解锁模式"
  echo -e "0. 返回主菜单"
  
  read -p "请选择解锁模式: " choice
  case $choice in
    1)
      read -p "请输入Netflix解锁DNS服务器IP: " dns_ip
      if [ -z "$dns_ip" ]; then
        echo -e "${RED}错误: IP不能为空${PLAIN}"
        return
      fi
      
      cat > ${CONFIG_DIR}/netflix.conf << EOF
# Netflix DNS解锁
address=/netflix.com/${dns_ip}
address=/nflximg.com/${dns_ip}
address=/nflxvideo.net/${dns_ip}
address=/nflxso.net/${dns_ip}
address=/nflxext.com/${dns_ip}
EOF
      
      # 设置本地DNS
      echo "nameserver 127.0.0.1" > /etc/resolv.conf
      
      systemctl restart dnsmasq
      echo -e "${GREEN}Netflix DNS解锁配置完成${PLAIN}"
      ;;
      
    2)
      read -p "请输入SS服务器地址: " ss_server
      read -p "请输入SS端口: " ss_port
      read -p "请输入SS密码: " ss_pwd
      read -p "请输入加密方式(默认:aes-256-gcm): " ss_method
      [ -z "$ss_method" ] && ss_method="aes-256-gcm"
      
      # 配置SS
      cat > $SS_CONFIG << EOF
{
    "server":"${ss_server}",
    "server_port":${ss_port},
    "password":"${ss_pwd}",
    "method":"${ss_method}",
    "timeout":300,
    "fast_open":false,
    "local_address":"127.0.0.1",
    "local_port":1080
}
EOF
      
      # 启动SS
      systemctl restart shadowsocks-libev
      
      # 设置DNS为SS服务器
      echo "nameserver ${ss_server}" > /etc/resolv.conf
      
      echo -e "${GREEN}Netflix SS解锁配置完成${PLAIN}"
      ;;
      
    0) return ;;
    *) echo -e "${RED}无效的选择${PLAIN}" ;;
  esac
}

# 检查服务状态
check_status() {
  echo -e "${BLUE}服务状态:${PLAIN}"
  echo -e "------------------------"
  
  # DNS服务状态
  if systemctl is-active dnsmasq >/dev/null 2>&1; then
    echo -e "DNS服务: ${GREEN}运行中${PLAIN}"
    echo -e "DNS配置:"
    cat /etc/resolv.conf
  else
    echo -e "DNS服务: ${RED}未运行${PLAIN}"
  fi
  
  # SS服务状态
  if systemctl is-active shadowsocks-libev >/dev/null 2>&1; then
    echo -e "\nSS服务: ${GREEN}运行中${PLAIN}"
    echo -e "SS配置:"
    cat $SS_CONFIG
  else
    echo -e "\nSS服务: ${RED}未运行${PLAIN}"
  fi
  
  # 已配置的解锁服务
  echo -e "\n已配置的解锁服务:"
  for conf in ${CONFIG_DIR}/*.conf; do
    if [ -f "$conf" ]; then
      echo "- $(basename $conf .conf)"
    fi
  done
  
  echo -e "------------------------"
}

# 主菜单
main_menu() {
  while true; do
    clear
    echo -e "${YELLOW}流媒体解锁脚本 v2.1${PLAIN}"
    echo -e "${BLUE}=============================${PLAIN}"
    echo -e "${GREEN}1.${PLAIN} Netflix解锁"
    echo -e "${GREEN}2.${PLAIN} Disney+解锁"
    echo -e "${GREEN}3.${PLAIN} YouTube解锁"
    echo -e "${GREEN}4.${PLAIN} 自定义域名解锁"
    echo -e "${GREEN}5.${PLAIN} 查看服务状态"
    echo -e "${GREEN}6.${PLAIN} 重置所有配置"
    echo -e "${GREEN}0.${PLAIN} 退出脚本"
    echo -e "${BLUE}=============================${PLAIN}"
    
    read -p "请选择: " choice
    case $choice in
      1) unlock_netflix ;;
      2) unlock_disney ;;
      3) unlock_youtube ;;
      4) unlock_custom ;;
      5) 
         check_status
         read -p "按回车继续..." dummy
         ;;
      6) reset_config ;;
      0) exit 0 ;;
      *) echo -e "${RED}无效的选择${PLAIN}" ;;
    esac
  done
}

# 其他解锁功能类似Netflix,只是域名配置不同
# ...

# 启动脚本
check_root
main_menu
