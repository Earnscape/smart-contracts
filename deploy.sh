#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

NETWORK="${1:-sepolia}"
ACCOUNT_FILE="$HOME/.starkli-wallets/deployer/account.json"
KEYSTORE_FILE="$HOME/.starkli-wallets/deployer/keystore.json"

if [ "$NETWORK" == "mainnet" ]; then
    RPC_URL="${STARKNET_RPC:-https://starknet-mainnet.public.blastapi.io}"
else
    RPC_URL="${STARKNET_RPC:-https://starknet-sepolia.public.blastapi.io}"
fi

clear
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}  EARNSCAPE DEPLOYMENT (7 Contracts)${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Network:${NC} $NETWORK"
echo -e "${YELLOW}RPC URL:${NC} $RPC_URL"
echo ""

echo -e "${BLUE}[1/3] Checking prerequisites...${NC}"

if ! command -v scarb &> /dev/null; then
    echo -e "${RED}Error: Scarb not installed${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Scarb found${NC}"

if ! command -v starkli &> /dev/null; then
    echo -e "${RED}Error: Starkli not installed${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Starkli found${NC}"

if [ ! -f "$ACCOUNT_FILE" ]; then
    echo -e "${RED}Error: Account file not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Account file found${NC}"

if [ ! -f "$KEYSTORE_FILE" ]; then
    echo -e "${RED}Error: Keystore file not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Keystore file found${NC}"
echo ""

echo -e "${BLUE}[2/3] Building contracts...${NC}"
scarb build
echo -e "${GREEN}✓ Build successful${NC}"
echo ""

echo -e "${BLUE}[3/3] Preparing deployment...${NC}"

# Extract address from account.json file (handle multiline addresses)
if [ -f "$ACCOUNT_FILE" ]; then
    OWNER_ADDRESS=$(cat "$ACCOUNT_FILE" | grep -A 2 '"address"' | grep -oP '0x[a-fA-F0-9]+' | tr -d '\n' | head -1)
fi

if [ -z "$OWNER_ADDRESS" ]; then
    read -p "Enter owner address: " OWNER_ADDRESS
fi

echo -e "${CYAN}Owner: $OWNER_ADDRESS${NC}"

read -p "Enter treasury address (or press Enter to use owner): " TREASURY_ADDRESS
if [ -z "$TREASURY_ADDRESS" ]; then
    TREASURY_ADDRESS=$OWNER_ADDRESS
fi

echo -e "${CYAN}Treasury: $TREASURY_ADDRESS${NC}"
echo ""

DEPLOYMENT_FILE="deployment_${NETWORK}_$(date +%Y%m%d_%H%M%S).log"
echo "EARNSCAPE DEPLOYMENT LOG" > $DEPLOYMENT_FILE
echo "Network: $NETWORK" >> $DEPLOYMENT_FILE
echo "Date: $(date)" >> $DEPLOYMENT_FILE
echo "" >> $DEPLOYMENT_FILE

declare_contract() {
    local name=$1
    local file=$2
    echo -e "${CYAN}  Declaring $name...${NC}"
    
    # Temporarily disable 'exit on error' for declaration
    set +e
    local output=$(starkli declare $file --account $ACCOUNT_FILE --keystore $KEYSTORE_FILE --rpc $RPC_URL 2>&1)
    local exit_code=$?
    set -e
    
    echo "$output"
    
    # Extract class hash (works for both new and already declared)
    local class_hash=$(echo "$output" | grep -oP '0x[a-fA-F0-9]{60,}' | head -1)
    
    if [ -z "$class_hash" ]; then
        echo -e "${RED}  Failed to get class hash${NC}"
        exit 1
    fi
    
    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}  ✓ Class declared: $class_hash${NC}"
    else
        echo -e "${YELLOW}  ✓ Class already declared: $class_hash${NC}"
    fi
    echo ""
    echo "$class_hash"
}

deploy_contract() {
    local name=$1
    local class_hash=$2
    shift 2
    echo -e "${CYAN}  Deploying $name...${NC}"
    
    # Run deployment and capture output
    local output=$(starkli deploy $class_hash "$@" --account $ACCOUNT_FILE --keystore $KEYSTORE_FILE --rpc $RPC_URL 2>&1)
    echo "$output"
    
    # Extract the deployed contract address (look for "Contract deployed:" line)
    local address=$(echo "$output" | grep "Contract deployed:" | grep -oP '0x[a-fA-F0-9]+' | tail -1)
    
    if [ -z "$address" ]; then
        echo -e "${RED}  Deployment failed - no contract address found${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}  ✓ Deployed at: $address${NC}"
    echo ""
    echo "$address"
}

echo -e "${MAGENTA}═══════════════════════════════════════════════${NC}"
echo -e "${MAGENTA}  DEPLOYING CONTRACTS${NC}"
echo -e "${MAGENTA}═══════════════════════════════════════════════${NC}"
echo ""

echo -e "${YELLOW}[1/7] EarnsToken${NC}"
EARNS_CLASS=$(declare_contract "EarnsToken" "target/dev/earnscape_contracts_EarnsToken.contract_class.json")
EARNS_ADDR=$(deploy_contract "EarnsToken" $EARNS_CLASS $OWNER_ADDRESS)
echo "[1] EarnsToken: $EARNS_ADDR" >> $DEPLOYMENT_FILE

echo -e "${YELLOW}[2/7] StEarnToken${NC}"
STEARN_CLASS=$(declare_contract "StEarnToken" "target/dev/earnscape_contracts_StEarnToken.contract_class.json")
STEARN_ADDR=$(deploy_contract "StEarnToken" $STEARN_CLASS $OWNER_ADDRESS)
echo "[2] StEarnToken: $STEARN_ADDR" >> $DEPLOYMENT_FILE

echo -e "${YELLOW}[3/7] EarnXDCManager${NC}"
EARNXDC_CLASS=$(declare_contract "EarnXDCManager" "target/dev/earnscape_contracts_EarnXDCManager.contract_class.json")
EARNXDC_ADDR=$(deploy_contract "EarnXDCManager" $EARNXDC_CLASS $OWNER_ADDRESS $EARNS_ADDR)
echo "[3] EarnXDCManager: $EARNXDC_ADDR" >> $DEPLOYMENT_FILE

echo -e "${YELLOW}[4/7] Escrow${NC}"
ESCROW_CLASS=$(declare_contract "Escrow" "target/dev/earnscape_contracts_Escrow.contract_class.json")
ESCROW_ADDR=$(deploy_contract "Escrow" $ESCROW_CLASS $OWNER_ADDRESS $EARNS_ADDR $TREASURY_ADDRESS)
echo "[4] Escrow: $ESCROW_ADDR" >> $DEPLOYMENT_FILE

echo -e "${YELLOW}[5/7] BulkVesting${NC}"
BULK_VESTING_CLASS=$(declare_contract "BulkVesting" "target/dev/earnscape_contracts_EarnscapeBulkVesting.contract_class.json")
BULK_VESTING_ADDR=$(deploy_contract "BulkVesting" $BULK_VESTING_CLASS $EARNXDC_ADDR $ESCROW_ADDR $EARNS_ADDR $OWNER_ADDRESS)
echo "[5] BulkVesting: $BULK_VESTING_ADDR" >> $DEPLOYMENT_FILE

echo -e "${YELLOW}[6/7] Staking${NC}"
STAKING_CLASS=$(declare_contract "Staking" "target/dev/earnscape_contracts_EarnscapeStaking.contract_class.json")
STAKING_ADDR=$(deploy_contract "Staking" $STAKING_CLASS $OWNER_ADDRESS $EARNS_ADDR $STEARN_ADDR $TREASURY_ADDRESS)
echo "[6] Staking: $STAKING_ADDR" >> $DEPLOYMENT_FILE

echo -e "${YELLOW}[7/7] Vesting${NC}"
VESTING_CLASS=$(declare_contract "Vesting" "target/dev/earnscape_contracts_EarnscapeVesting.contract_class.json")
VESTING_ADDR=$(deploy_contract "Vesting" $VESTING_CLASS $OWNER_ADDRESS $EARNS_ADDR $STEARN_ADDR $TREASURY_ADDRESS $STAKING_ADDR $OWNER_ADDRESS)
echo "[7] Vesting: $VESTING_ADDR" >> $DEPLOYMENT_FILE

echo -e "${GREEN}✓ All contracts deployed!${NC}"
echo ""

echo -e "${YELLOW}═══════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  MANUAL CONFIGURATION REQUIRED${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════${NC}"
echo ""
echo -e "${CYAN}Run these commands manually when ready:${NC}"
echo ""
echo -e "${MAGENTA}[1] Configure EarnsToken:${NC}"
echo -e "starkli invoke $EARNS_ADDR set_contract4 $ESCROW_ADDR $BULK_VESTING_ADDR \\"
echo -e "  --account $ACCOUNT_FILE --keystore $KEYSTORE_FILE --rpc $RPC_URL"
echo ""
echo -e "${MAGENTA}[2] Configure Escrow:${NC}"
echo -e "starkli invoke $ESCROW_ADDR set_contract4 $BULK_VESTING_ADDR \\"
echo -e "  --account $ACCOUNT_FILE --keystore $KEYSTORE_FILE --rpc $RPC_URL"
echo ""
echo -e "${MAGENTA}[3] Configure Staking:${NC}"
echo -e "starkli invoke $STAKING_ADDR set_contract3 $VESTING_ADDR \\"
echo -e "  --account $ACCOUNT_FILE --keystore $KEYSTORE_FILE --rpc $RPC_URL"
echo ""
echo -e "${MAGENTA}[4] Transfer StEarnToken Ownership:${NC}"
echo -e "starkli invoke $STEARN_ADDR transfer_ownership $STAKING_ADDR \\"
echo -e "  --account $ACCOUNT_FILE --keystore $KEYSTORE_FILE --rpc $RPC_URL"
echo ""

if [ "$NETWORK" == "mainnet" ]; then
    EXPLORER="https://starkscan.co/contract"
else
    EXPLORER="https://sepolia.starkscan.co/contract"
fi

echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}  DEPLOYMENT COMPLETED${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo ""
echo -e "${CYAN}Deployed Contracts:${NC}"
echo -e "  [1] EarnsToken:     $EARNS_ADDR"
echo -e "  [2] StEarnToken:    $STEARN_ADDR"
echo -e "  [3] EarnXDCManager: $EARNXDC_ADDR"
echo -e "  [4] Escrow:         $ESCROW_ADDR"
echo -e "  [5] BulkVesting:    $BULK_VESTING_ADDR"
echo -e "  [6] Staking:        $STAKING_ADDR"
echo -e "  [7] Vesting:        $VESTING_ADDR"
echo ""
echo -e "${YELLOW}Log saved to: $DEPLOYMENT_FILE${NC}"
echo -e "${BLUE}Explorer: $EXPLORER/$EARNS_ADDR${NC}"
echo ""
echo -e "${GREEN}🎉 All 7 contracts deployed on $NETWORK!${NC}"
echo ""
