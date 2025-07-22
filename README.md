
-----

# 🪱 WORM Miner Tool

A user-friendly command-line interface for installing, managing, and interacting with the Worm Privacy miner on the Sepolia testnet.

![Worm Miner Tool UI](./worm-miner.png)

-----

## Official Links

  - **GitHub:** [Worm Privacy Organization](https://github.com/worm-privacy)
  - **Discord:** [Join the Community](https://discord.gg/4SYg84pQnw)
  - **X (Twitter):** [@WormPrivacy](https://x.com/WormPrivacy)

-----

## Quick Start

To use the Worm Miner CLI, download the script and run it locally to launch the interactive menu. Follow these steps:

* **Download the script**:

```bash
curl -sSL https://raw.githubusercontent.com/scarletbright/Worm-Lindwurm-Sepolia-testnet-miner-client/main/worm-lindwurm-testnet-miner-cli.sh -o worm-miner.sh
```

*  **Make the script executable**:
```
chmod +x worm-miner.sh
```

*  **Run the script**:
```
./worm-miner.sh
```

-----

## Menu Commands Explained

1.  **Install Miner & Start Service:** Installs all dependencies, compiles the miner, saves your private key, and starts the miner as a background service (systemd).

2.  **Burn ETH for BETH:** Burns testnet ETH to get Burnt ETH (BETH), which is used by the miner to participate in mining epochs.

3.  **Check Balances:** Displays current epoch, your wallet's current BETH, and WORM token balances on the Sepolia testnet and Claimable WORM (10 last epochs).

4.  **Update Miner:** Pulls the latest code from the official repository, rebuilds the miner binary, and restarts the background service.

5.  **Uninstall Miner:** Stops the service and completely removes all related files, including the miner, logs, and your private key.

6.  **Claim WORM Rewards:** Checks for and claims any pending WORM rewards you have earned from mining.

7.  **View Miner Logs:** Shows the last 15 lines from the miner's log file for quick diagnostics and status checks.

8.  **Find & Set Fastest RPC:** Runs a latency test against a list of public RPCs to find and set the fastest one for all commands.

9.  **Exit:** Closes the tool.

-----

## Advanced Configuration

You can customize the miner's behavior by editing the files created by the installer.

### Changing Miner Parameters

To change the core mining parameters, you need to edit the miner's startup script.

1.  Open the script with a text editor like `nano`:

    ```bash
    nano ~/miner/start-miner.sh
    ```

2.  Modify the values for the following flags:

      * `--amount-per-epoch`: Specifies how much BETH you're willing to spend per epoch.
      * `--num-epochs`: Defines how many epochs you'd like to participate in ahead of time.
      * `--claim-interval`: Determines how many epochs to wait between claim operations.

3.  Save the file (`Ctrl+O`, then `Enter`) and exit (`Ctrl+X`).

4.  Restart the miner service for the changes to take effect:

    ```bash
    sudo systemctl restart worm-miner
    ```

### Manually Setting the RPC Endpoint

The script automatically finds the fastest RPC upon installation (or when you select option 8). However, you can manually set a custom Sepolia RPC.

1.  Open the RPC configuration file:

    ```bash
    nano ~/.worm-miner/fastest_rpc.log
    ```

2.  Replace the existing URL with your preferred Sepolia RPC URL.

3.  Save the file and exit. The miner will use this new RPC the next time it's started or a command is run.

-----

## Requirements

**Server:** The machine with 16gb of RAM is only needed for the burn phase. After that you can just run the miner with a very typical VPS server

**OS:** Ubuntu / Debian.

**Disk Space:** around 10 GB of free disk space for the miner, dependencies, and zk-SNARK parameters.

-----

## Security Details

**Private Key:** Your private key is stored locally in `~/.worm-miner/private.key` and only secured with `chmod 600` permissions.

**Always use a fresh wallet created specifically for this testnet.**

### Do Not Reuse Mainnet Keys: Never use a private key from a mainnet wallet that holds real assets.

-----

## Sepolia ETH faucets:

  * [Google Sepolia faucet](https://cloud.google.com/application/web3/faucet/ethereum/sepolia)
  * [Alchemy Sepolia faucet](https://www.alchemy.com/faucets/ethereum-sepolia)
  * [Sepolia PoW Faucet](https://sepolia-faucet.pk910.de)
  * [Getblock Sepolia Faucet](https://getblock.io/faucet/eth-sepolia/)