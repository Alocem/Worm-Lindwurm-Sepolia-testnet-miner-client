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

# Find the fastest RPC
find_fastest_rpc() {
    echo -e "${GREEN}[*] 正在查找最快的 Sepolia RPC...${NC}"
    fastest_rpc=""
    min_latency=999999

    for rpc in "${sepolia_rpcs[@]}"; do
        # Use --max-time to prevent hangs on unresponsive RPCs
        latency=$(curl -o /dev/null --connect-timeout 5 --max-time 10 -s -w "%{time_total}" "$rpc" || echo "999999")
        echo -e "测试 RPC: $rpc | 延迟: ${YELLOW}$latency${NC} 秒"
        # Convert to milliseconds for integer comparison
        latency_ms=$(echo "$latency * 1000" | awk '{printf "%.0f", $1}')
        min_latency_ms=$(echo "$min_latency * 1000" | awk '{printf "%.0f", $1}')
        if [[ "$latency_ms" -lt "$min_latency_ms" && "$latency_ms" -gt 0 ]]; then
            min_latency=$latency
            fastest_rpc=$rpc
        fi
    done

    if [ -n "$fastest_rpc" ]; then
        echo "$fastest_rpc" > "$fastest_rpc_file"
        echo -e "${GREEN}[+] 最快的 RPC 已设置为: $fastest_rpc，延迟: $min_latency 秒。${NC}"
    else
        echo -e "${RED}错误: 无法确定最快的 RPC。请检查您的网络连接。${NC}"
        exit 1
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
  echo "9. 退出"
  echo -e "${GREEN}------------------------${NC}"
  read -p "请输入选择 [1-9]: " action

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

      if [ ! -f "$fastest_rpc_file" ]; then
        find_fastest_rpc
      fi
      fastest_rpc=$(cat "$fastest_rpc_file")

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
      ;;
    3)
      echo -e "${GREEN}[*] 正在检查余额...${NC}"
      private_key=$(get_private_key) || exit 1

      if [ ! -f "$fastest_rpc_file" ]; then
        find_fastest_rpc
      fi
      fastest_rpc=$(cat "$fastest_rpc_file")

      "$worm_miner_bin" info --network sepolia --private-key "$private_key" --custom-rpc "$fastest_rpc"
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

      if [ ! -f "$fastest_rpc_file" ]; then
        find_fastest_rpc
      fi
      fastest_rpc=$(cat "$fastest_rpc_file")

      read -p "请输入起始纪元 (例如: 0): " from_epoch
      read -p "请输入要领取的纪元数量 (例如: 10): " num_epochs
      if [[ ! "$from_epoch" =~ ^[0-9]+$ ]] || [[ ! "$num_epochs" =~ ^[0-9]+$ ]]; then
        echo -e "${YELLOW}错误: 纪元值必须是非负整数。${NC}"
        continue
      fi
      "$worm_miner_bin" claim --network sepolia --private-key "$private_key" --custom-rpc "$fastest_rpc" --from-epoch "$from_epoch" --num-epochs "$num_epochs"
      echo -e "${GREEN}[+] WORM 奖励领取过程已完成。${NC}"
      ;;
    7)
      echo -e "${GREEN}[*] 正在显示挖矿日志的最后15行...${NC}"
      if [ -f "$log_file" ]; then
        tail -n 15 "$log_file"
      else
        echo -e "${YELLOW}未找到日志文件。挖矿程序是否已安装并正在运行？${NC}"
      fi
      ;;
    8)
      echo -e "${GREEN}[*] 正在查找并设置最快的 RPC...${NC}"
      find_fastest_rpc
      ;;
    9)
      echo -e "${GREEN}[*] 正在退出...${NC}"
      exit 0
      ;;
    *)
      echo -e "${YELLOW}无效选择。请输入 1 到 9 之间的数字。${NC}"
      ;;
    esac

  echo -e "\n${GREEN}按回车键返回菜单...${NC}"
  read
done