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
    "https://sepolia.drpc.org"
    "https://ethereum-sepolia-rpc.publicnode.com"
    "https://eth-sepolia.public.blastapi.io"
)

# Helper: Get private key from user file
get_private_key() {
  if [ ! -f "$key_file" ]; then
    echo -e "${YELLOW}Miner not installed or key file missing. Run option 1 first.${NC}"
    return 1
  fi
  private_key=$(cat "$key_file")
  if [[ ! $private_key =~ ^0x[0-9a-fA-F]{64}$ ]]; then
    echo -e "${RED}Error: Invalid private key format in $key_file${NC}"
    return 1
  fi
  echo "$private_key"
}

# Find the fastest RPC
find_fastest_rpc() {
    echo -e "${GREEN}[*] Finding the fastest Sepolia RPC...${NC}"
    fastest_rpc=""
    min_latency=999999

    for rpc in "${sepolia_rpcs[@]}"; do
        # Use --max-time to prevent hangs on unresponsive RPCs
        latency=$(curl -o /dev/null --connect-timeout 5 --max-time 10 -s -w "%{time_total}" "$rpc" || echo "999999")
        echo -e "Testing RPC: $rpc | Latency: ${YELLOW}$latency${NC} seconds"
        if (( $(echo "$latency < $min_latency" | bc -l) && $(echo "$latency > 0" | bc -l) )); then
            min_latency=$latency
            fastest_rpc=$rpc
        fi
    done

    if [ -n "$fastest_rpc" ]; then
        echo "$fastest_rpc" > "$fastest_rpc_file"
        echo -e "${GREEN}[+] Fastest RPC set to: $fastest_rpc with latency: $min_latency seconds.${NC}"
    else
        echo -e "${RED}Error: Could not determine the fastest RPC. Please check your network connection.${NC}"
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

  echo -e "${GREEN}---- WORM MINER TOOL ----${NC}"
  echo -e "${BOLD}Select an option:${NC}"
  echo "1. Install Miner & Start Service"
  echo "2. Burn ETH for BETH"
  echo "3. Check Balances"
  echo "4. Update Miner"
  echo "5. Uninstall Miner"
  echo "6. Claim WORM Rewards"
  echo "7. View Miner Logs"
  echo "8. Find & Set Fastest RPC"
  echo "9. Exit"
  echo -e "${GREEN}------------------------${NC}"
  read -p "Enter choice [1-9]: " action

  case $action in
    1)
      echo -e "${GREEN}[*] Installing dependencies...${NC}"
      sudo apt-get update && sudo apt-get install -y \
        build-essential cmake git curl wget unzip bc \
        libgmp-dev libsodium-dev nasm nlohmann-json3-dev

      if ! command -v cargo &>/dev/null; then
        echo -e "${GREEN}[*] Installing Rust toolchain...${NC}"
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
      fi

      echo -e "${GREEN}[*] Cloning miner repository...${NC}"
      cd "$HOME"
      if [ -d "$miner_dir" ]; then
        read -p "Directory $miner_dir exists. Delete and reinstall? [y/N]: " confirm
        if [[ "$confirm" =~ ^[yY]$ ]]; then
          rm -rf "$miner_dir"
        else
          echo -e "${RED}Aborting installation.${NC}"
          exit 1
        fi
      fi
      if ! git clone https://github.com/worm-privacy/miner "$miner_dir"; then
        echo -e "${RED}Error: Failed to clone repository. Check network or permissions.${NC}"
        exit 1
      fi
      cd "$miner_dir"

      echo -e "${GREEN}[*] Downloading parameters...${NC}"
      echo -e "${YELLOW}This is a large download (~8 GB) and may take several minutes. Please wait...${NC}"
      make download_params

      echo -e "${GREEN}[*] Building and installing miner binary...${NC}"
      RUSTFLAGS="-C target-cpu=native" cargo install --path .
      if [ ! -f "$worm_miner_bin" ]; then
        echo -e "${RED}Error: Miner binary not found at $worm_miner_bin. Installation failed.${NC}"
        exit 1
      fi

      echo -e "${GREEN}[*] Creating configuration directory...${NC}"
      mkdir -p "$log_dir"
      touch "$log_file"

      find_fastest_rpc

      private_key=""
      while true; do
        read -sp "Enter your private key (e.g., 0x...): " private_key
        echo ""
        if [[ $private_key =~ ^0x[0-9a-fA-F]{64}$ ]]; then
          break
        else
          echo -e "${YELLOW}Invalid key format. Must be 64 hex characters starting with 0x.${NC}"
        fi
      done

      echo "$private_key" > "$key_file"
      chmod 600 "$key_file"
      echo -e "${GREEN}[*] Warning: Back up $key_file securely, as it contains your private key.${NC}"

      echo -e "${GREEN}[*] Creating miner start script...${NC}"
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

      echo -e "${GREEN}[*] Creating and enabling systemd service...${NC}"
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

      echo -e "${GREEN}[+] Miner installed and service started successfully!${NC}"
      ;;
    2)
      echo -e "${GREEN}[*] Burning ETH for BETH${NC}"
      private_key=$(get_private_key) || exit 1

      if [ ! -f "$fastest_rpc_file" ]; then
        find_fastest_rpc
      fi
      fastest_rpc=$(cat "$fastest_rpc_file")

      read -p "Enter total ETH amount to burn (e.g., 1.0): " amount
      read -p "Enter amount to spend as BETH (e.g., 1.0): " spend

      echo -e "${BOLD}Starting burn process...${NC}"

      cd "$miner_dir"
      "$worm_miner_bin" burn \
        --network sepolia \
        --private-key "$private_key" \
        --custom-rpc "$fastest_rpc" \
        --amount "$amount" \
        --spend "$spend" \
        --fee "0"

      echo -e "${GREEN}[+] Burn process finished.${NC}"
      ;;
    3)
      echo -e "${GREEN}[*] Checking Balances...${NC}"
      private_key=$(get_private_key) || exit 1

      if [ ! -f "$fastest_rpc_file" ]; then
        find_fastest_rpc
      fi
      fastest_rpc=$(cat "$fastest_rpc_file")

      "$worm_miner_bin" info --network sepolia --private-key "$private_key" --custom-rpc "$fastest_rpc"
      ;;
    4)
      echo -e "${GREEN}[*] Updating Miner...${NC}"
      if [ ! -d "$miner_dir" ]; then
        echo -e "${RED}Error: Miner directory $miner_dir not found. Please run option 1 to install first.${NC}"
        exit 1
      fi
      cd "$miner_dir"
      git pull origin main
      echo -e "${GREEN}[*] Building and installing optimized miner binary...${NC}"
      cargo clean
      RUSTFLAGS="-C target-cpu=native" cargo install --path .
      if [ ! -f "$worm_miner_bin" ]; then
        echo -e "${RED}Error: Miner binary not found at $worm_miner_bin. Update failed.${NC}"
        exit 1
      fi

      find_fastest_rpc

      sudo systemctl restart worm-miner
      echo -e "${GREEN}[+] Miner updated and restarted successfully.${NC}"
      ;;
    5)
      echo -e "${GREEN}[*] Uninstalling Miner...${NC}"
      sudo systemctl stop worm-miner || true
      sudo systemctl disable worm-miner || true
      sudo rm -f /etc/systemd/system/worm-miner.service
      sudo systemctl daemon-reload
      rm -rf "$log_dir" "$miner_dir" "$worm_miner_bin"
      echo -e "${GREEN}[+] Miner has been uninstalled.${NC}"
      ;;
    6)
      echo -e "${GREEN}[*] Claiming WORM Rewards...${NC}"
      private_key=$(get_private_key) || exit 1

      if [ ! -f "$fastest_rpc_file" ]; then
        find_fastest_rpc
      fi
      fastest_rpc=$(cat "$fastest_rpc_file")

      read -p "Enter starting epoch (e.g., 0): " from_epoch
      read -p "Enter number of epochs to claim (e.g., 10): " num_epochs
      if [[ ! "$from_epoch" =~ ^[0-9]+$ ]] || [[ ! "$num_epochs" =~ ^[0-9]+$ ]]; then
        echo -e "${YELLOW}Error: Epoch values must be non-negative integers.${NC}"
        continue
      fi
      "$worm_miner_bin" claim --network sepolia --private-key "$private_key" --custom-rpc "$fastest_rpc" --from-epoch "$from_epoch" --num-epochs "$num_epochs"
      echo -e "${GREEN}[+] WORM reward claim process finished.${NC}"
      ;;
    7)
      echo -e "${GREEN}[*] Displaying last 15 lines of Miner Logs...${NC}"
      if [ -f "$log_file" ]; then
        tail -n 15 "$log_file"
      else
        echo -e "${YELLOW}Log file not found. Is the miner installed and running?${NC}"
      fi
      ;;
    8)
      echo -e "${GREEN}[*] Finding and setting the fastest RPC...${NC}"
      find_fastest_rpc
      ;;
    9)
      echo -e "${GREEN}[*] Exiting...${NC}"
      exit 0
      ;;
    *)
      echo -e "${YELLOW}Invalid choice. Please enter a number from 1 to 9.${NC}"
      ;;
    esac

  echo -e "\n${GREEN}Press Enter to return to the menu...${NC}"
  read
done