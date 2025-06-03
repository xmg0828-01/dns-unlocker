#!/bin/bash
# DNS解锁脚本 - 增强版（支持SS节点）v2.0

export TERM=xterm-256color
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

if [ "$(id -u)" != "0" ]; then
   echo -e "${RED}错误: 需要root权限${NC}"
   echo -e "${YELLOW}请使用 sudo bash $0 运行此脚本${NC}"
   exit 1
fi

install_dependencies() {
  echo -e "${BLUE}正在检查并安装必要软件...${NC}"
  apt-get update
  apt-get install -y dnsmasq jq shadowsocks-libev curl redsocks iptables-persistent
  mkdir -p /etc/shadowsocks/ /etc/dnsmasq.d/ /var/log/
  echo -e "${GREEN}依赖软件安装完成${NC}"
}

setup_dnsmasq() {
  echo -e "${BLUE}配置基本dnsmasq设置...${NC}"
  if [ -f "/etc/dnsmasq.conf" ] && [ ! -f "/etc/dnsmasq.conf.bak" ]; then
    cp /etc/dnsmasq.conf /etc/dnsmasq.conf.bak
  fi
  
  cat > /etc/dnsmasq.conf << 'EOFCONF'
cache-size=1024
no-resolv
server=8.8.8.8
server=8.8.4.4
server=1.1.1.1
listen-address=127.0.0.1
conf-dir=/etc/dnsmasq.d/,*.conf
bind-interfaces
EOFCONF
  echo -e "${GREEN}dnsmasq基础配置完成${NC}"
}

get_available_port() {
  local port=10800
  while netstat -ln 2>/dev/null | grep ":$port " > /dev/null; do
    ((port++))
  done
  echo $port
}

add_ss_node_manual() {
  clear
  echo -e "${CYAN}===== 手动添加SS节点 =====${NC}"
  
  read -p "输入节点名称: " node_name
  if [ -z "$node_name" ]; then
    echo -e "${RED}节点名称不能为空${NC}"
    read -p "按回车继续..." dummy
    return
  fi
  
  if [ -f "/etc/shadowsocks/${node_name}.json" ]; then
    echo -e "${RED}节点名称已存在${NC}"
    read -p "按回车继续..." dummy
    return
  fi
  
  read -p "输入服务器地址: " server
  if [ -z "$server" ]; then
    echo -e "${RED}服务器地址不能为空${NC}"
    read -p "按回车继续..." dummy
    return
  fi
  
  read -p "输入端口: " port
  if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
    echo -e "${RED}端口必须是1-65535之间的数字${NC}"
    read -p "按回车继续..." dummy
    return
  fi
  
  read -p "输入密码: " password
  if [ -z "$password" ]; then
    echo -e "${RED}密码不能为空${NC}"
    read -p "按回车继续..." dummy
    return
  fi
  
  echo -e "${YELLOW}选择加密方式:${NC}"
  echo -e "${YELLOW}1. aes-256-gcm (推荐)${NC}"
  echo -e "${YELLOW}2. aes-128-gcm${NC}"
  echo -e "${YELLOW}3. chacha20-ietf-poly1305${NC}"
  echo -e "${YELLOW}4. aes-256-cfb${NC}"
  echo -e "${YELLOW}5. 自定义${NC}"
  read -p "请选择: " method_choice
  
  case $method_choice in
    1) method="aes-256-gcm" ;;
    2) method="aes-128-gcm" ;;
    3) method="chacha20-ietf-poly1305" ;;
    4) method="aes-256-cfb" ;;
    5) 
       read -p "输入自定义加密方式: " method
       if [ -z "$method" ]; then
         echo -e "${RED}加密方式不能为空${NC}"
         read -p "按回车继续..." dummy
         return
       fi
       ;;
    *) method="aes-256-gcm" ;;
  esac
  
  local_port=$(get_available_port)
  
  cat > "/etc/shadowsocks/${node_name}.json" << EOFSS
{
    "server": "$server",
    "server_port": $port,
    "local_address": "127.0.0.1",
    "local_port": $local_port,
    "password": "$password",
    "timeout": 300,
    "method": "$method",
    "fast_open": false
}
EOFSS
  
  echo "${node_name}|手动添加|$server|$port|$method|$local_port|停止" >> /etc/shadowsocks/nodes.list
  
  echo -e "${GREEN}SS节点 $node_name 配置完成${NC}"
  echo -e "${YELLOW}服务器: $server:$port${NC}"
  echo -e "${YELLOW}本地端口: $local_port${NC}"
  echo -e "${YELLOW}加密方式: $method${NC}"
  
  read -p "是否立即启动此节点? (y/n): " start_now
  if [ "$start_now" = "y" ] || [ "$start_now" = "Y" ]; then
    start_ss_node "$node_name"
  fi
  read -p "按回车继续..." dummy
}

add_ss_node_subscription() {
  clear
  echo -e "${CYAN}===== 从订阅链接导入SS节点 =====${NC}"
  
  read -p "输入订阅链接: " sub_url
  if [ -z "$sub_url" ]; then
    echo -e "${RED}订阅链接不能为空${NC}"
    read -p "按回车继续..." dummy
    return
  fi
  
  echo -e "${BLUE}正在下载订阅内容...${NC}"
  sub_content=$(curl -s --max-time 30 "$sub_url")
  if [ -z "$sub_content" ]; then
    echo -e "${RED}无法获取订阅内容${NC}"
    read -p "按回车继续..." dummy
    return
  fi
  
  decoded_content=$(echo "$sub_content" | base64 -d 2>/dev/null)
  if [ -z "$decoded_content" ]; then
    echo -e "${RED}订阅内容解码失败${NC}"
    read -p "按回车继续..." dummy
    return
  fi
  
  echo -e "${BLUE}正在解析SS节点...${NC}"
  local node_count=0
  local success_count=0
  
  while IFS= read -r line; do
    if [[ $line == ss://* ]]; then
      ((node_count++))
      if parse_ss_url "$line" "$node_count"; then
        ((success_count++))
      fi
    fi
  done <<< "$decoded_content"
  
  if [ $success_count -eq 0 ]; then
    echo -e "${RED}未找到有效的SS节点${NC}"
  else
    echo -e "${GREEN}成功导入 $success_count/$node_count 个SS节点${NC}"
  fi
  read -p "按回车继续..." dummy
}

parse_ss_url() {
  local ss_url="$1"
  local index="$2"
  
  local encoded_part="${ss_url#ss://}"
  local config_part="${encoded_part%%#*}"
  local name_part="${encoded_part#*#}"
  
  local decoded_config
  if [[ $config_part == *"@"* ]]; then
    local auth_part="${config_part%%@*}"
    local server_part="${config_part#*@}"
    local decoded_auth=$(echo "$auth_part" | base64 -d 2>/dev/null)
    if [ -n "$decoded_auth" ]; then
      decoded_config="${decoded_auth}@${server_part}"
    else
      decoded_config="$config_part"
    fi
  else
    decoded_config=$(echo "$config_part" | base64 -d 2>/dev/null)
  fi
  
  if [ -z "$decoded_config" ]; then
    echo -e "${RED}跳过无效节点 $index${NC}"
    return 1
  fi
  
  local auth_info="${decoded_config%%@*}"
  local server_info="${decoded_config#*@}"
  local method="${auth_info%:*}"
  local password="${auth_info#*:}"
  local server="${server_info%:*}"
  local port="${server_info#*:}"
  
  if [ -z "$method" ] || [ -z "$password" ] || [ -z "$server" ] || [ -z "$port" ]; then
    echo -e "${RED}跳过解析失败的节点 $index${NC}"
    return 1
  fi
  
  local node_name=$(echo "$name_part" | sed 's/%20/ /g' | sed 's/%2B/+/g' | sed 's/%2F/\//g')
  if [ -z "$node_name" ]; then
    node_name="订阅节点_$index"
  fi
  
  local config_name="sub_node_$index"
  local local_port=$(get_available_port)
  
  cat > "/etc/shadowsocks/${config_name}.json" << EOFSS
{
    "server": "$server",
    "server_port": $port,
    "local_address": "127.0.0.1",
    "local_port": $local_port,
    "password": "$password",
    "timeout": 300,
    "method": "$method",
    "fast_open": false
}
EOFSS
  
  echo "${config_name}|${node_name}|$server|$port|$method|$local_port|停止" >> /etc/shadowsocks/nodes.list
  echo -e "${GREEN}导入节点: $node_name (本地端口: $local_port)${NC}"
  return 0
}
list_ss_nodes() {
  clear
  echo -e "${CYAN}===== 已配置的SS节点 =====${NC}"
  echo ""
  
  local found_nodes=false
  local index=1
  
  for config_file in /etc/shadowsocks/*.json; do
    if [ -f "$config_file" ]; then
      found_nodes=true
      local config_name=$(basename "$config_file" .json)
      local server=$(jq -r '.server' "$config_file" 2>/dev/null)
      local port=$(jq -r '.server_port' "$config_file" 2>/dev/null)
      local local_port=$(jq -r '.local_port' "$config_file" 2>/dev/null)
      local method=$(jq -r '.method' "$config_file" 2>/dev/null)
      
      local status="${RED}停止${NC}"
      if pgrep -f "ss-local.*$config_file" > /dev/null 2>&1; then
        status="${GREEN}运行中${NC}"
      fi
      
      local display_name="$config_name"
      if [ -f "/etc/shadowsocks/nodes.list" ]; then
        local node_info=$(grep "^${config_name}|" /etc/shadowsocks/nodes.list 2>/dev/null | head -1)
        if [ -n "$node_info" ]; then
          display_name=$(echo "$node_info" | cut -d'|' -f2)
        fi
      fi
      
      echo -e "${YELLOW}$index. $display_name${NC}"
      echo -e "   配置名: $config_name"
      echo -e "   服务器: $server:$port"
      echo -e "   本地端口: $local_port"
      echo -e "   加密方式: $method"
      echo -e "   状态: $status"
      echo "   ---"
      ((index++))
    fi
  done
  
  if [ "$found_nodes" = false ]; then
    echo -e "${YELLOW}暂无配置的SS节点${NC}"
  fi
  read -p "按回车继续..." dummy
}

start_ss_node() {
  local node_name="$1"
  local config_file="/etc/shadowsocks/${node_name}.json"
  
  if [ ! -f "$config_file" ]; then
    echo -e "${RED}配置文件不存在${NC}"
    return 1
  fi
  
  if pgrep -f "ss-local.*$config_file" > /dev/null 2>&1; then
    echo -e "${YELLOW}节点 $node_name 已在运行${NC}"
    return 0
  fi
  
  nohup ss-local -c "$config_file" > "/var/log/ss-${node_name}.log" 2>&1 &
  sleep 2
  
  if pgrep -f "ss-local.*$config_file" > /dev/null 2>&1; then
    echo -e "${GREEN}节点 $node_name 启动成功${NC}"
    return 0
  else
    echo -e "${RED}节点 $node_name 启动失败${NC}"
    return 1
  fi
}

stop_ss_node() {
  local node_name="$1"
  local config_file="/etc/shadowsocks/${node_name}.json"
  
  local pids=$(pgrep -f "ss-local.*$config_file" 2>/dev/null)
  if [ -n "$pids" ]; then
    echo "$pids" | xargs kill
    sleep 1
    echo -e "${GREEN}节点 $node_name 已停止${NC}"
  else
    echo -e "${YELLOW}节点 $node_name 未在运行${NC}"
  fi
}

toggle_ss_node() {
  clear
  echo -e "${CYAN}===== 启动/停止SS节点 =====${NC}"
  
  local nodes=()
  local i=1
  
  for config_file in /etc/shadowsocks/*.json; do
    if [ -f "$config_file" ]; then
      local config_name=$(basename "$config_file" .json)
      local status="${RED}停止${NC}"
      if pgrep -f "ss-local.*$config_file" > /dev/null 2>&1; then
        status="${GREEN}运行中${NC}"
      fi
      
      local display_name="$config_name"
      if [ -f "/etc/shadowsocks/nodes.list" ]; then
        local node_info=$(grep "^${config_name}|" /etc/shadowsocks/nodes.list 2>/dev/null | head -1)
        if [ -n "$node_info" ]; then
          display_name=$(echo "$node_info" | cut -d'|' -f2)
        fi
      fi
      
      echo -e "${YELLOW}$i. $display_name ($status)${NC}"
      nodes[$i]="$config_name"
      ((i++))
    fi
  done
  
  if [ ${#nodes[@]} -eq 0 ]; then
    echo -e "${YELLOW}暂无配置的SS节点${NC}"
    read -p "按回车继续..." dummy
    return
  fi
  
  read -p "请选择要操作的节点编号: " node_num
  
  if [[ "$node_num" =~ ^[0-9]+$ ]] && [ "$node_num" -ge 1 ] && [ "$node_num" -lt "$i" ]; then
    local node_name="${nodes[$node_num]}"
    local config_file="/etc/shadowsocks/${node_name}.json"
    
    if pgrep -f "ss-local.*$config_file" > /dev/null 2>&1; then
      stop_ss_node "$node_name"
    else
      start_ss_node "$node_name"
    fi
  else
    echo -e "${RED}无效的选择${NC}"
  fi
  read -p "按回车继续..." dummy
}

delete_ss_node() {
  clear
  echo -e "${CYAN}===== 删除SS节点 =====${NC}"
  
  local nodes=()
  local i=1
  
  for config_file in /etc/shadowsocks/*.json; do
    if [ -f "$config_file" ]; then
      local config_name=$(basename "$config_file" .json)
      local display_name="$config_name"
      if [ -f "/etc/shadowsocks/nodes.list" ]; then
        local node_info=$(grep "^${config_name}|" /etc/shadowsocks/nodes.list 2>/dev/null | head -1)
        if [ -n "$node_info" ]; then
          display_name=$(echo "$node_info" | cut -d'|' -f2)
        fi
      fi
      
      echo -e "${YELLOW}$i. $display_name${NC}"
      nodes[$i]="$config_name"
      ((i++))
    fi
  done
  
  if [ ${#nodes[@]} -eq 0 ]; then
    echo -e "${YELLOW}暂无配置的SS节点${NC}"
    read -p "按回车继续..." dummy
    return
  fi
  
  read -p "请选择要删除的节点编号: " node_num
  
  if [[ "$node_num" =~ ^[0-9]+$ ]] && [ "$node_num" -ge 1 ] && [ "$node_num" -lt "$i" ]; then
    local node_name="${nodes[$node_num]}"
    read -p "确定要删除节点 $node_name 吗? (y/n): " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
      stop_ss_node "$node_name"
      rm -f "/etc/shadowsocks/${node_name}.json"
      if [ -f "/etc/shadowsocks/nodes.list" ]; then
        sed -i "/^${node_name}|/d" /etc/shadowsocks/nodes.list
      fi
      echo -e "${GREEN}节点 $node_name 已删除${NC}"
    fi
  else
    echo -e "${RED}无效的选择${NC}"
  fi
  read -p "按回车继续..." dummy
}

test_ss_nodes() {
  clear
  echo -e "${CYAN}===== 测试SS节点连通性 =====${NC}"
  echo ""
  
  local tested_count=0
  local success_count=0
  
  for config_file in /etc/shadowsocks/*.json; do
    if [ -f "$config_file" ]; then
      local config_name=$(basename "$config_file" .json)
      local local_port=$(jq -r '.local_port' "$config_file" 2>/dev/null)
      
      local display_name="$config_name"
      if [ -f "/etc/shadowsocks/nodes.list" ]; then
        local node_info=$(grep "^${config_name}|" /etc/shadowsocks/nodes.list 2>/dev/null | head -1)
        if [ -n "$node_info" ]; then
          display_name=$(echo "$node_info" | cut -d'|' -f2)
        fi
      fi
      
      echo -e "${YELLOW}测试节点: $display_name${NC}"
      ((tested_count++))
      
      local was_running=false
      if pgrep -f "ss-local.*$config_file" > /dev/null 2>&1; then
        was_running=true
      else
        echo "  启动节点..."
        start_ss_node "$config_name"
        sleep 3
      fi
      
      echo "  测试连接..."
      local test_result=$(timeout 15 curl -s --socks5 "127.0.0.1:$local_port" "http://httpbin.org/ip" 2>/dev/null)
      
      if [ -n "$test_result" ]; then
        local ip=$(echo "$test_result" | jq -r '.origin' 2>/dev/null)
        if [ -n "$ip" ] && [ "$ip" != "null" ]; then
          echo -e "  ${GREEN}✓ 连接成功，出口IP: $ip${NC}"
          ((success_count++))
        else
          echo -e "  ${RED}✗ 连接失败${NC}"
        fi
      else
        echo -e "  ${RED}✗ 连接失败${NC}"
      fi
      
      if [ "$was_running" = false ]; then
        stop_ss_node "$config_name"
      fi
      echo "---"
    fi
  done
  
  echo -e "${CYAN}测试完成: $success_count/$tested_count 个节点可用${NC}"
  read -p "按回车继续..." dummy
}

manage_ss_nodes() {
  while true; do
    clear
    echo -e "${CYAN}===== SS节点配置管理 =====${NC}"
    echo -e "${YELLOW}1. 手动添加SS节点${NC}"
    echo -e "${YELLOW}2. 从订阅链接导入${NC}"
    echo -e "${YELLOW}3. 查看已配置节点${NC}"
    echo -e "${YELLOW}4. 启动/停止节点${NC}"
    echo -e "${YELLOW}5. 删除节点${NC}"
    echo -e "${YELLOW}6. 测试节点连通性${NC}"
    echo -e "${YELLOW}0. 返回主菜单${NC}"
    echo -e "${CYAN}=======================${NC}"
    read -p "请选择操作: " ss_choice
    
    case $ss_choice in
      1) add_ss_node_manual ;;
      2) add_ss_node_subscription ;;
      3) list_ss_nodes ;;
      4) toggle_ss_node ;;
      5) delete_ss_node ;;
      6) test_ss_nodes ;;
      0) return ;;
      *) 
         echo -e "${RED}无效的选择${NC}"
         sleep 2
         ;;
    esac
  done
}

setup_service_with_ss() {
  local service_name="$1"
  local service_display="$2"
  
  clear
  echo -e "${CYAN}===== 使用SS节点解锁 $service_display =====${NC}"
  
  local available_nodes=()
  local i=1
  
  echo -e "${YELLOW}可用的SS节点:${NC}"
  for config_file in /etc/shadowsocks/*.json; do
    if [ -f "$config_file" ]; then
      local config_name=$(basename "$config_file" .json)
      local local_port=$(jq -r '.local_port' "$config_file" 2>/dev/null)
      
      local display_name="$config_name"
      if [ -f "/etc/shadowsocks/nodes.list" ]; then
        local node_info=$(grep "^${config_name}|" /etc/shadowsocks/nodes.list 2>/dev/null | head -1)
        if [ -n "$node_info" ]; then
          display_name=$(echo "$node_info" | cut -d'|' -f2)
        fi
      fi
      
      local status="${RED}停止${NC}"
      if pgrep -f "ss-local.*$config_file" > /dev/null 2>&1; then
        status="${GREEN}运行中${NC}"
      fi
      
      echo -e "${YELLOW}$i. $display_name (端口: $local_port, 状态: $status)${NC}"
      available_nodes[$i]="$config_name:$local_port"
      ((i++))
    fi
  done
  
  if [ ${#available_nodes[@]} -eq 0 ]; then
    echo -e "${RED}没有可用的SS节点，请先配置SS节点${NC}"
    read -p "按回车继续..." dummy
    return
  fi
  
  read -p "请选择SS节点编号: " node_num
  
  if [[ "$node_num" =~ ^[0-9]+$ ]] && [ "$node_num" -ge 1 ] && [ "$node_num" -lt "$i" ]; then
    local node_info="${available_nodes[$node_num]}"
    local node_name="${node_info%:*}"
    local local_port="${node_info#*:}"
    
    echo -e "${BLUE}启动SS节点...${NC}"
    start_ss_node "$node_name"
    
    echo -e "${BLUE}配置透明代理...${NC}"
    setup_transparent_proxy "$service_name" "$local_port"
    
    echo -e "${GREEN}$service_display 已配置使用SS节点 $node_name 进行解锁${NC}"
  else
    echo -e "${RED}无效的选择${NC}"
  fi
  read -p "按回车继续..." dummy
}

setup_transparent_proxy() {
  local service="$1"
  local socks_port="$2"
  local redsocks_port=$((8080 + $(echo "$service" | wc -c | tr -d ' ')))
  
  cat > "/etc/redsocks-${service}.conf" << EOFRED
base {
    log_debug = off;
    log_info = on;
    log = "file:/var/log/redsocks-${service}.log";
    daemon = on;
    redirector = iptables;
}

redsocks {
    local_ip = 127.0.0.1;
    local_port = $redsocks_port;
    ip = 127.0.0.1;
    port = $socks_port;
    type = socks5;
}
EOFRED
  
  pkill -f "redsocks.*${service}" 2>/dev/null
  redsocks -c "/etc/redsocks-${service}.conf"
  
  iptables -t nat -D OUTPUT -p tcp --dport 443 -j REDIRECT --to-ports $redsocks_port 2>/dev/null
  iptables -t nat -A OUTPUT -p tcp --dport 443 -j REDIRECT --to-ports $redsocks_port
  
  echo -e "${GREEN}透明代理配置完成，端口: $redsocks_port${NC}"
}
setup_netflix() {
  echo -e "${CYAN}===== 解锁Netflix =====${NC}"
  echo -e "${YELLOW}请选择解锁方式:${NC}"
  echo -e "${YELLOW}1. 使用指定IP地址${NC}"
  echo -e "${YELLOW}2. 使用SS节点${NC}"
  read -p "请选择: " unlock_method
  
  case $unlock_method in
    1)
      read -p "输入用于解锁Netflix的IP: " ip
      if [ -z "$ip" ]; then
        echo -e "${RED}IP地址不能为空${NC}"
        return
      fi
      
      cat > /etc/dnsmasq.d/netflix.conf << EOFSTREAM
address=/netflix.com/$ip
address=/nflxext.com/$ip
address=/nflximg.com/$ip
address=/nflximg.net/$ip
address=/nflxvideo.net/$ip
address=/nflxso.net/$ip
address=/netflix.net/$ip
EOFSTREAM
      echo -e "${GREEN}Netflix解锁已配置（IP方式）${NC}"
      ;;
    2) setup_service_with_ss "netflix" "Netflix" ;;
    *) echo -e "${RED}无效的选择${NC}" ;;
  esac
}

setup_disney() {
  echo -e "${CYAN}===== 解锁Disney+ =====${NC}"
  echo -e "${YELLOW}请选择解锁方式:${NC}"
  echo -e "${YELLOW}1. 使用指定IP地址${NC}"
  echo -e "${YELLOW}2. 使用SS节点${NC}"
  read -p "请选择: " unlock_method
  
  case $unlock_method in
    1)
      read -p "输入用于解锁Disney+的IP: " ip
      if [ -z "$ip" ]; then
        echo -e "${RED}IP地址不能为空${NC}"
        return
      fi
      
      cat > /etc/dnsmasq.d/disney.conf << EOFSTREAM
address=/disney.com/$ip
address=/disney-plus.net/$ip
address=/dssott.com/$ip
address=/disneyplus.com/$ip
address=/bamgrid.com/$ip
address=/disney-portal.my.onetrust.com/$ip
address=/disneystreaming.com/$ip
address=/disney.demdex.net/$ip
address=/disney.my.sentry.io/$ip
address=/cdn.registerdisney.go.com/$ip
address=/global.edge.bamgrid.com/$ip
address=/dssott.com.akamaized.net/$ip
address=/d9.flashtalking.com/$ip
address=/cdn.cdn.unid.go.com/$ip
address=/cws.conviva.com/$ip
EOFSTREAM
      echo -e "${GREEN}Disney+解锁已配置（IP方式）${NC}"
      ;;
    2) setup_service_with_ss "disney" "Disney+" ;;
    *) echo -e "${RED}无效的选择${NC}" ;;
  esac
}

setup_tiktok() {
  echo -e "${CYAN}===== 解锁TikTok =====${NC}"
  echo -e "${YELLOW}请选择解锁方式:${NC}"
  echo -e "${YELLOW}1. 使用指定IP地址${NC}"
  echo -e "${YELLOW}2. 使用SS节点${NC}"
  read -p "请选择: " unlock_method
  
  case $unlock_method in
    1)
      read -p "输入用于解锁TikTok的IP: " ip
      if [ -z "$ip" ]; then
        echo -e "${RED}IP地址不能为空${NC}"
        return
      fi
      
      cat > /etc/dnsmasq.d/tiktok.conf << EOFSTREAM
address=/tiktok.com/$ip
address=/tiktokv.com/$ip
address=/tiktokcdn.com/$ip
address=/tiktokcdn-us.com/$ip
address=/tik-tokapi.com/$ip
address=/muscdn.com/$ip
EOFSTREAM
      echo -e "${GREEN}TikTok解锁已配置（IP方式）${NC}"
      ;;
    2) setup_service_with_ss "tiktok" "TikTok" ;;
    *) echo -e "${RED}无效的选择${NC}" ;;
  esac
}

setup_ai() {
  echo -e "${CYAN}===== 解锁AI服务 =====${NC}"
  echo -e "${YELLOW}请选择解锁方式:${NC}"
  echo -e "${YELLOW}1. 使用指定IP地址${NC}"
  echo -e "${YELLOW}2. 使用SS节点${NC}"
  read -p "请选择: " unlock_method
  
  case $unlock_method in
    1)
      read -p "输入用于解锁AI服务的IP: " ip
      if [ -z "$ip" ]; then
        echo -e "${RED}IP地址不能为空${NC}"
        return
      fi
      
      cat > /etc/dnsmasq.d/ai.conf << EOFAI
address=/openai.com/$ip
address=/ai.com/$ip
address=/chat.openai.com/$ip
address=/api.openai.com/$ip
address=/platform.openai.com/$ip
address=/anthropic.com/$ip
address=/claude.ai/$ip
address=/api.anthropic.com/$ip
address=/gemini.google.com/$ip
address=/bard.google.com/$ip
address=/generativelanguage.googleapis.com/$ip
EOFAI
      echo -e "${GREEN}AI服务解锁已配置（IP方式）${NC}"
      ;;
    2) setup_service_with_ss "ai" "AI服务" ;;
    *) echo -e "${RED}无效的选择${NC}" ;;
  esac
}

setup_custom() {
  echo -e "${CYAN}===== 添加自定义域名解锁 =====${NC}"
  read -p "输入要解锁的自定义域名: " domain
  if [ -z "$domain" ]; then
    echo -e "${RED}域名不能为空${NC}"
    return
  fi
  
  echo -e "${YELLOW}请选择解锁方式:${NC}"
  echo -e "${YELLOW}1. 使用指定IP地址${NC}"
  echo -e "${YELLOW}2. 使用SS节点${NC}"
  read -p "请选择: " unlock_method
  
  domain=$(echo $domain | sed -e 's|^https\?://||')
  domain=${domain%/}
  
  case $unlock_method in
    1)
      read -p "输入用于解锁 $domain 的IP: " ip
      if [ -z "$ip" ]; then
        echo -e "${RED}IP地址不能为空${NC}"
        return
      fi
      
      cat > "/etc/dnsmasq.d/custom_${domain//./\_}.conf" << EOFCUSTOM
address=/$domain/$ip
EOFCUSTOM
      echo -e "${GREEN}自定义域名 $domain 解锁已配置（IP方式）${NC}"
      ;;
    2) setup_service_with_ss "custom_${domain//./\_}" "自定义域名 $domain" ;;
    *) echo -e "${RED}无效的选择${NC}" ;;
  esac
}

apply_config() {
  echo -e "${BLUE}应用配置并重启服务...${NC}"
  
  cat > /etc/resolv.conf << EOFDNS
nameserver 127.0.0.1
EOFDNS

  systemctl restart dnsmasq
  if systemctl is-active --quiet dnsmasq; then
    echo -e "${GREEN}DNS解锁设置完成，dnsmasq服务已成功启动${NC}"
  else
    echo -e "${RED}警告: dnsmasq服务启动失败，请检查配置${NC}"
    journalctl -u dnsmasq -n 10
  fi
}

show_status() {
  echo -e "${BLUE}当前DNS解锁状态:${NC}"
  echo -e "${CYAN}-------------------------${NC}"
  
  if systemctl is-active --quiet dnsmasq; then
    echo -e "${GREEN}dnsmasq 服务状态: 运行中${NC}"
  else
    echo -e "${RED}dnsmasq 服务状态: 未运行${NC}"
  fi
  
  echo -e "${YELLOW}已配置的解锁服务:${NC}"
  for conf in /etc/dnsmasq.d/*.conf; do
    if [ -f "$conf" ]; then
      service=$(basename "$conf" .conf)
      echo "- $service"
    fi
  done
  
  echo -e "${CYAN}-------------------------${NC}"
  read -p "按回车键继续..." dummy
}

reset_config() {
  echo -e "${CYAN}===== 重置所有配置 =====${NC}"
  read -p "确定要重置所有配置吗? (y/n): " confirm
  if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
    if [ -f "/etc/dnsmasq.conf.bak" ]; then
      cp /etc/dnsmasq.conf.bak /etc/dnsmasq.conf
    fi
    
    rm -f /etc/dnsmasq.d/*.conf
    rm -f /etc/redsocks-*.conf
    rm -f /etc/shadowsocks/*.json
    rm -f /etc/shadowsocks/nodes.list
    
    pkill -f redsocks 2>/dev/null
    pkill -f ss-local 2>/dev/null
    
    iptables -t nat -F OUTPUT 2>/dev/null
    
    systemctl restart dnsmasq
    
    echo -e "${GREEN}已重置所有DNS解锁配置${NC}"
  fi
}

main_menu() {
  while true; do
    clear
    echo -e "${CYAN}==== DNS解锁脚本 v2.0 ====${NC}"
    echo -e "${YELLOW}1. 解锁Netflix${NC}"
    echo -e "${YELLOW}2. 解锁Disney+${NC}"
    echo -e "${YELLOW}3. 解锁TikTok${NC}"
    echo -e "${YELLOW}4. 解锁AI服务 (OpenAI/Claude/Gemini)${NC}"
    echo -e "${YELLOW}5. 添加自定义域名解锁${NC}"
    echo -e "${YELLOW}6. SS节点配置管理${NC}"
    echo -e "${YELLOW}7. 应用配置并重启服务${NC}"
    echo -e "${YELLOW}8. 显示当前解锁状态${NC}"
    echo -e "${YELLOW}9. 重置所有配置${NC}"
    echo -e "${YELLOW}0. 退出${NC}"
    echo -e "${CYAN}=======================${NC}"
    read -p "请选择操作: " choice
    
    case $choice in
      1) setup_netflix ;;
      2) setup_disney ;;
      3) setup_tiktok ;;
      4) setup_ai ;;
      5) setup_custom ;;
      6) manage_ss_nodes ;;
      7) apply_config ;;
      8) 
         show_status
         ;;
      9) reset_config ;;
      0) 
         echo -e "${GREEN}感谢使用DNS解锁脚本!${NC}"
         exit 0
         ;;
      *) 
         echo -e "${RED}无效的选择${NC}"
         sleep 2
         ;;
    esac
  done
}

# 主程序
echo -e "${CYAN}======================================${NC}"
echo -e "${CYAN}        DNS解锁脚本安装向导         ${NC}"
echo -e "${CYAN}======================================${NC}"

install_dependencies
setup_dnsmasq
main_menu
