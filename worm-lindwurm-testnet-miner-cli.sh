#!/bin/bash
set -e
set -o pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

# Paths
log_dir="$HOME/.worm-miner"
miner_dir="$HOME/miner"
log_file="$log_dir/miner.log"
key_file="$log_dir/private.key"
worm_miner_bin="$HOME/.cargo/bin/worm-miner"
fastest_rpc_file="$log_dir/fastest_rpc.log"

# A more reliable list of RPCs to test
sepolia_rpcs=(
    "https://lb.drpc.org/sepolia/AkN5KTMwrkQcrhMRTLHEJP0Q5qk2hukR8IfpqhnKxixj"
    "https://lb.drpc.org/sepolia/ArII-5JsVUlwmMr09jfLuE6LLBsohuAR8IffqhnKxixj"
    "https://lb.drpc.org/sepolia/AkhJnvrfNEEXvyMMbSG_oUi9ITlPhuYR8IfjqhnKxixj"
    "https://sepolia.drpc.org"
    "https://ethereum-sepolia-rpc.publicnode.com"
    "https://eth-sepolia.public.blastapi.io"
    "https://sepolia.gateway.tenderly.co"
    "https://rpc.sepolia.org"
)

# Helper: Get private key from user file
get_private_key() {
  if [ ! -f "$key_file" ]; then
    echo -e "${YELLOW}挖矿程序未安装或密钥文件缺失。请先运行选项 1。${NC}"
    return 1
  fi
  private_key=$(cat "$key_file")
  if [[ ! $private_key =~ ^0x[0-9a-fA-F]{64}$ ]]; then
    echo -e "${RED}错误: $key_file 中的私钥格式无效${NC}"
    return 1
  fi
  echo "$private_key"
}

# Test RPC connectivity and latency with rate limit detection
test_rpc() {
    local rpc_url="$1"
    local timeout_seconds=5
    
    # Use curl to test with proper timing
    local start_time=$(perl -MTime::HiRes=time -E 'say time' 2>/dev/null || python3 -c "import time; print(time.time())" 2>/dev/null || echo "$(date +%s)")
    
    local response=$(curl -s --connect-timeout $timeout_seconds --max-time $timeout_seconds \
        -X POST \
        -H "Content-Type: application/json" \
        -d '{"method": "eth_blockNumber","params": [],"id": "1","jsonrpc": "2.0"}' \
        "$rpc_url" 2>/dev/null)
    
    local end_time=$(perl -MTime::HiRes=time -E 'say time' 2>/dev/null || python3 -c "import time; print(time.time())" 2>/dev/null || echo "$(date +%s)")
    
    # Check for rate limit or other errors
    if [[ "$response" == *"rate limit"* ]] || [[ "$response" == *"429"* ]] || [[ "$response" == *"too many requests"* ]]; then
        echo "RATE_LIMITED"
        return 2
    elif [[ $? -eq 0 && ("$response" == *"result"* || "$response" == *"0x"*) ]]; then
        local latency=$(echo "$end_time - $start_time" | awk '{printf "%.3f", $1}')
        echo "$latency"
        return 0
    else
        echo "999999"
        return 1
    fi
}

# Find the fastest available RPC with rate limit handling
find_fastest_rpc() {
    echo -e "${GREEN}[*] 正在查找最快的 Sepolia RPC...${NC}"
    local fastest_rpc=""
    local min_latency=999999
    local available_rpcs=()

    for rpc in "${sepolia_rpcs[@]}"; do
        echo -e "${YELLOW}测试 RPC: $rpc${NC}"
        
        local result=$(test_rpc "$rpc")
        local exit_code=$?
        
        if [[ "$result" == "RATE_LIMITED" ]]; then
            echo -e "  ${YELLOW}速率限制${NC} ⚠"
        elif [[ "$exit_code" -eq 0 && "$result" != "999999" ]]; then
            available_rpcs+=("$rpc")
            if [[ $(echo "$result < $min_latency" | awk '{print ($1 < $2)}') -eq 1 ]]; then
                min_latency=$result
                fastest_rpc=$rpc
            fi
            echo -e "  延迟: ${GREEN}$result${NC} 秒 ✓"
        else
            echo -e "  ${RED}连接失败${NC} ✗"
        fi
    done

    if [ -n "$fastest_rpc" ]; then
        echo "$fastest_rpc" > "$fastest_rpc_file"
        # Save backup RPCs list
        printf '%s\n' "${available_rpcs[@]}" > "$log_dir/available_rpcs.log"
        echo -e "${GREEN}[+] 最快的 RPC 已设置为: $fastest_rpc，延迟: $min_latency 秒。${NC}"
        echo -e "${GREEN}[+] 发现 ${#available_rpcs[@]} 个可用的 RPC 节点。${NC}"
    else
        echo -e "${RED}错误: 无法确定最快的 RPC。请检查您的网络连接。${NC}"
        # Set a default RPC as fallback
        echo "https://sepolia.drpc.org" > "$fastest_rpc_file"
        echo -e "${YELLOW}[!] 使用默认 RPC: https://sepolia.drpc.org${NC}"
    fi
}

# Get next available RPC from backup list
get_next_rpc() {
    if [ -f "$log_dir/available_rpcs.log" ]; then
        local current_rpc=$(cat "$fastest_rpc_file" 2>/dev/null)
        local found_current=false
        local next_rpc=""
        
        while IFS= read -r rpc; do
            if [ "$found_current" = true ]; then
                next_rpc="$rpc"
                break
            elif [ "$rpc" = "$current_rpc" ]; then
                found_current=true
            fi
        done < "$log_dir/available_rpcs.log"
        
        # If no next RPC found, use the first one
        if [ -z "$next_rpc" ]; then
            next_rpc=$(head -n 1 "$log_dir/available_rpcs.log" 2>/dev/null)
        fi
        
        if [ -n "$next_rpc" ]; then
            echo "$next_rpc" > "$fastest_rpc_file"
            echo -e "${YELLOW}[!] 切换到备用 RPC: $next_rpc${NC}"
            echo "$next_rpc"
            return 0
        fi
    fi
    
    # Fallback: find new fastest RPC
    find_fastest_rpc
    cat "$fastest_rpc_file"
    return 0
}

# Get current RPC with health check and auto-switching
get_current_rpc() {
    if [ -f "$fastest_rpc_file" ]; then
        local current_rpc=$(cat "$fastest_rpc_file")
        # Test if current RPC is still working
        local result=$(test_rpc "$current_rpc")
        local exit_code=$?
        
        if [[ "$result" == "RATE_LIMITED" ]]; then
            echo -e "${YELLOW}[!] 当前 RPC 速率限制，正在切换到备用节点...${NC}"
            get_next_rpc
            return 0
        elif [[ "$exit_code" -eq 0 && "$result" != "999999" ]]; then
            echo "$current_rpc"
            return 0
        else
            echo -e "${YELLOW}[!] 当前 RPC 不可用，正在查找新的 RPC...${NC}"
            find_fastest_rpc
            cat "$fastest_rpc_file"
            return 0
        fi
    else
        find_fastest_rpc
        cat "$fastest_rpc_file"
        return 0
    fi
}

# Main Menu Loop
while true; do
  clear
  echo -e "${GREEN}"
  cat << "EOL"
    ╦ ╦╔═╗╦═╗╔╦╗
    ║║║║ ║╠╦╝║║║
    ╚╩╝╚═╝╩╚═╩ ╩
    powered by EIP-7503
EOL
  echo -e "${NC}"

  echo -e "${GREEN}---- WORM 挖矿工具 ----${NC}"
  echo -e "${BOLD}请选择操作:${NC}"
  echo "1. 安装挖矿程序并启动服务"
  echo "2. 燃烧 ETH 获取 BETH"
  echo "3. 查看余额"
  echo "4. 更新挖矿程序"
  echo "5. 卸载挖矿程序"
  echo "6. 领取 WORM 奖励"
  echo "7. 查看挖矿日志"
  echo "8. 查找并设置最快的 RPC"
  echo "9. 设置钱包私钥"
  echo "10. 设置挖矿参数"
  echo "11. 退出"
  echo -e "${GREEN}------------------------${NC}"
  read -p "请输入选择 [1-11]: " action

  case $action in
    1)
      echo -e "${GREEN}[*] 正在安装依赖项...${NC}"
      sudo apt-get update && sudo apt-get install -y \
        build-essential cmake git curl wget unzip bc \
        libgmp-dev libsodium-dev nasm nlohmann-json3-dev

      if ! command -v cargo &>/dev/null; then
        echo -e "${GREEN}[*] 正在安装 Rust 工具链...${NC}"
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
      fi

      echo -e "${GREEN}[*] 正在克隆挖矿程序仓库...${NC}"
      cd "$HOME"
      if [ -d "$miner_dir" ]; then
        read -p "目录 $miner_dir 已存在。是否删除并重新安装？ [y/N]: " confirm
        if [[ "$confirm" =~ ^[yY]$ ]]; then
          rm -rf "$miner_dir"
        else
          echo -e "${RED}取消安装。${NC}"
          exit 1
        fi
      fi
      if ! git clone https://github.com/worm-privacy/miner "$miner_dir"; then
        echo -e "${RED}错误: 克隆仓库失败。请检查网络连接或权限。${NC}"
        exit 1
      fi
      cd "$miner_dir"

      echo -e "${GREEN}[*] 正在下载参数文件...${NC}"
      echo -e "${YELLOW}这是一个大文件下载（约8GB），可能需要几分钟时间。请耐心等待...${NC}"
      make download_params

      echo -e "${GREEN}[*] 正在构建并安装挖矿程序...${NC}"
      RUSTFLAGS="-C target-cpu=native" cargo install --path .
      if [ ! -f "$worm_miner_bin" ]; then
        echo -e "${RED}错误: 在 $worm_miner_bin 未找到挖矿程序。安装失败。${NC}"
        exit 1
      fi

      echo -e "${GREEN}[*] 正在创建配置目录...${NC}"
      mkdir -p "$log_dir"
      touch "$log_file"

      find_fastest_rpc

      private_key=""
      while true; do
        read -sp "请输入您的私钥 (例如: 0x...): " private_key
        echo ""
        if [[ $private_key =~ ^0x[0-9a-fA-F]{64}$ ]]; then
          break
        else
          echo -e "${YELLOW}私钥格式无效。必须是以0x开头的64位十六进制字符。${NC}"
        fi
      done

      echo "$private_key" > "$key_file"
      chmod 600 "$key_file"
      echo -e "${GREEN}[*] 警告: 请安全备份 $key_file，因为它包含您的私钥。${NC}"

      echo -e "${GREEN}[*] 正在创建挖矿启动脚本...${NC}"
      tee "$miner_dir/start-miner.sh" > /dev/null <<EOL
#!/bin/bash
PRIVATE_KEY=\$(cat "$key_file")
FASTEST_RPC=\$(cat "$fastest_rpc_file")
exec "$worm_miner_bin" mine \\
  --network sepolia \\
  --private-key "\$PRIVATE_KEY" \\
  --custom-rpc "\$FASTEST_RPC" \\
  --amount-per-epoch "0.0001" \\
  --num-epochs "3" \\
  --claim-interval "10"
EOL
      chmod +x "$miner_dir/start-miner.sh"

      echo -e "${GREEN}[*] 正在创建并启用系统服务...${NC}"
      sudo tee /etc/systemd/system/worm-miner.service > /dev/null <<EOL
[Unit]
Description=Worm Miner (Sepolia Testnet)
After=network.target

[Service]
User=$(whoami)
WorkingDirectory=$miner_dir
ExecStart=$miner_dir/start-miner.sh
Restart=always
RestartSec=10
Environment="RUST_LOG=info"
StandardOutput=append:$log_file
StandardError=append:$log_file

[Install]
WantedBy=multi-user.target
EOL

      sudo systemctl daemon-reload
      sudo systemctl enable --now worm-miner

      echo -e "${GREEN}[+] 挖矿程序安装成功并已启动服务！${NC}"
      ;;
    2)
      echo -e "${GREEN}[*] 正在燃烧 ETH 获取 BETH${NC}"
      private_key=$(get_private_key) || exit 1

      fastest_rpc=$(get_current_rpc)

      read -p "请输入要燃烧的 ETH 总量 (例如: 1.0): " amount
      read -p "请输入要作为 BETH 花费的数量 (例如: 1.0): " spend

      echo -e "${BOLD}正在开始燃烧过程...${NC}"

      cd "$miner_dir"
      "$worm_miner_bin" burn \
        --network sepolia \
        --private-key "$private_key" \
        --custom-rpc "$fastest_rpc" \
        --amount "$amount" \
        --spend "$spend" \
        --fee "0"

      echo -e "${GREEN}[+] 燃烧过程已完成。${NC}"
      read -p "按 Enter 键继续..."
      ;;
    3)
      echo -e "${GREEN}[*] 正在检查余额...${NC}"
      private_key=$(get_private_key) || exit 1

      # Retry mechanism for balance check
      local max_retries=3
      local retry_count=0
      local success=false
      
      while [ $retry_count -lt $max_retries ] && [ "$success" = false ]; do
        fastest_rpc=$(get_current_rpc)
        
        if [ $retry_count -gt 0 ]; then
          echo -e "${YELLOW}[!] 重试第 $retry_count 次...${NC}"
          sleep 2
        fi
        
        if "$worm_miner_bin" info --network sepolia --private-key "$private_key" --custom-rpc "$fastest_rpc"; then
          success=true
        else
          retry_count=$((retry_count + 1))
          if [ $retry_count -lt $max_retries ]; then
            echo -e "${YELLOW}[!] 操作失败，将在2秒后重试...${NC}"
          else
            echo -e "${RED}[!] 操作失败，已达到最大重试次数。请检查网络连接或稍后再试。${NC}"
          fi
        fi
      done
      
      read -p "按 Enter 键继续..."
      ;;
    4)
      echo -e "${GREEN}[*] 正在更新挖矿程序...${NC}"
      if [ ! -d "$miner_dir" ]; then
        echo -e "${RED}错误: 未找到挖矿程序目录 $miner_dir。请先运行选项 1 进行安装。${NC}"
        exit 1
      fi
      cd "$miner_dir"
      git pull origin main
      echo -e "${GREEN}[*] 正在构建并安装优化的挖矿程序...${NC}"
      cargo clean
      RUSTFLAGS="-C target-cpu=native" cargo install --path .
      if [ ! -f "$worm_miner_bin" ]; then
        echo -e "${RED}错误: 在 $worm_miner_bin 未找到挖矿程序。更新失败。${NC}"
        exit 1
      fi

      find_fastest_rpc

      sudo systemctl restart worm-miner
      echo -e "${GREEN}[+] 挖矿程序更新成功并已重启。${NC}"
      ;;
    5)
      echo -e "${GREEN}[*] 正在卸载挖矿程序...${NC}"
      sudo systemctl stop worm-miner || true
      sudo systemctl disable worm-miner || true
      sudo rm -f /etc/systemd/system/worm-miner.service
      sudo systemctl daemon-reload
      rm -rf "$log_dir" "$miner_dir" "$worm_miner_bin"
      echo -e "${GREEN}[+] 挖矿程序已卸载。${NC}"
      ;;
    6)
      echo -e "${GREEN}[*] 正在领取 WORM 奖励...${NC}"
      private_key=$(get_private_key) || exit 1

      fastest_rpc=$(get_current_rpc)

      read -p "请输入起始纪元 (例如: 0): " from_epoch
      read -p "请输入要领取的纪元数量 (例如: 10): " num_epochs
      if [[ ! "$from_epoch" =~ ^[0-9]+$ ]] || [[ ! "$num_epochs" =~ ^[0-9]+$ ]]; then
        echo -e "${YELLOW}错误: 纪元值必须是非负整数。${NC}"
        continue
      fi
      if [ "$from_epoch" -lt 0 ] || [ "$num_epochs" -le 0 ]; then
        echo -e "${YELLOW}错误: 纪元值必须是非负整数，领取数量必须大于 0。${NC}"
        continue
      fi
      "$worm_miner_bin" claim --network sepolia --private-key "$private_key" --custom-rpc "$fastest_rpc" --from-epoch "$from_epoch" --num-epochs "$num_epochs"
      echo -e "${GREEN}[+] WORM 奖励领取过程已完成。${NC}"
      read -p "按 Enter 键继续..."
      ;;
    7)
      echo -e "${GREEN}[*] 正在显示挖矿日志的最后15行...${NC}"
      if [ -f "$log_file" ]; then
        tail -n 15 "$log_file"
      else
        echo -e "${YELLOW}未找到日志文件。挖矿程序是否已安装并正在运行？${NC}"
      fi
      read -p "按 Enter 键继续..."
      ;;
    8)
      echo -e "${GREEN}[*] 正在查找并设置最快的 RPC...${NC}"
      find_fastest_rpc
      read -p "按 Enter 键继续..."
      ;;
    9)
      echo -e "${GREEN}[*] 设置钱包私钥${NC}"
      
      # Show current private key (masked)
      if [ -f "$key_file" ]; then
        current_key=$(cat "$key_file")
        masked_key="${current_key:0:6}...${current_key: -4}"
        echo -e "${YELLOW}当前私钥: $masked_key${NC}"
      else
        echo -e "${YELLOW}当前没有设置私钥${NC}"
      fi
      
      echo -e "${YELLOW}警告: 请确保使用专门为测试网创建的钱包，不要使用主网钱包！${NC}"
      
      private_key=""
      while true; do
        read -sp "请输入新的私钥 (例如: 0x...): " private_key
        echo ""
        if [[ $private_key =~ ^0x[0-9a-fA-F]{64}$ ]]; then
          break
        else
          echo -e "${YELLOW}私钥格式无效。必须是以0x开头的64位十六进制字符。${NC}"
        fi
      done
      
      mkdir -p "$log_dir"
      echo "$private_key" > "$key_file"
      chmod 600 "$key_file"
      echo -e "${GREEN}[+] 私钥已更新并保存到 $key_file${NC}"
      echo -e "${GREEN}[*] 警告: 请安全备份此文件！${NC}"
      ;;
    10)
      echo -e "${GREEN}[*] 设置挖矿参数${NC}"
      
      # Check if miner directory exists
      if [ ! -d "$miner_dir" ]; then
        echo -e "${RED}错误: 挖矿程序未安装。请先运行选项 1 安装挖矿程序。${NC}"
        continue
      fi
      
      # Show current parameters
      if [ -f "$miner_dir/start-miner.sh" ]; then
        echo -e "${YELLOW}当前挖矿参数:${NC}"
        grep -E "(amount-per-epoch|num-epochs|claim-interval)" "$miner_dir/start-miner.sh" | sed 's/^/  /'
        echo ""
      fi
      
      echo -e "${BOLD}请设置新的挖矿参数:${NC}"
      
      read -p "每个纪元花费的 BETH 数量 (例如: 0.0001): " amount_per_epoch
      read -p "提前参与的纪元数量 (例如: 3): " num_epochs
      read -p "领取操作间隔纪元数 (例如: 10): " claim_interval
      
      # Validate inputs
      if ! [[ "$amount_per_epoch" =~ ^[0-9]+\.?[0-9]*$ ]] || ! [[ "$num_epochs" =~ ^[0-9]+$ ]] || ! [[ "$claim_interval" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}错误: 参数格式无效。请输入有效的数字。${NC}"
        continue
      fi
      
      # Update start-miner.sh
      echo -e "${GREEN}[*] 正在更新挖矿启动脚本...${NC}"
      tee "$miner_dir/start-miner.sh" > /dev/null <<EOL
#!/bin/bash
PRIVATE_KEY=\$(cat "$key_file")
FASTEST_RPC=\$(cat "$fastest_rpc_file")
exec "$worm_miner_bin" mine \\
  --network sepolia \\
  --private-key "\$PRIVATE_KEY" \\
  --custom-rpc "\$FASTEST_RPC" \\
  --amount-per-epoch "$amount_per_epoch" \\
  --num-epochs "$num_epochs" \\
  --claim-interval "$claim_interval"
EOL
      chmod +x "$miner_dir/start-miner.sh"
      
      echo -e "${GREEN}[+] 挖矿参数已更新:${NC}"
      echo -e "  每个纪元花费: $amount_per_epoch BETH"
      echo -e "  参与纪元数量: $num_epochs"
      echo -e "  领取间隔: $claim_interval 纪元"
      
      # Ask if user wants to restart the service
      if systemctl is-active --quiet worm-miner; then
        read -p "挖矿服务正在运行，是否重启以应用新参数？ [y/N]: " restart_confirm
        if [[ "$restart_confirm" =~ ^[yY]$ ]]; then
          sudo systemctl restart worm-miner
          echo -e "${GREEN}[+] 挖矿服务已重启${NC}"
        fi
      fi
      ;;
    11)
      echo -e "${GREEN}[*] 正在退出...${NC}"
      exit 0
      ;;
    *)
      echo -e "${YELLOW}无效选择。请输入 1 到 11 之间的数字。${NC}"
      ;;
    esac

  echo -e "\n${GREEN}按回车键返回菜单...${NC}"
  read
done