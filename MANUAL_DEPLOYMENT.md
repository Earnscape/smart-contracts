# Manual Deployment Guide for Earnscape Contracts

This guide provides step-by-step manual commands to deploy all 7 Earnscape contracts on Starknet.

**Two deployment methods available:**
1. **Method A:** Using Account File + Keystore (Standard)
2. **Method B:** Using External Wallet Private Key (Simplified)

---

## Prerequisites

1. **Install Starkli and Scarb**
   ```bash
   # Verify installations
   scarb --version
   starkli --version
   ```

2. **Build Contracts**
   ```bash
   cd /home/Earnscape_cairo
   scarb build
   ```

---

## Choose Your Deployment Method

### Jump to:
- [Method A: Standard Deployment (Account + Keystore)](#method-a-standard-deployment-with-account-file--keystore)
- [Method B: External Wallet Private Key Deployment](#method-b-deployment-with-external-wallet-private-key)

---

# Method A: Standard Deployment (Account File + Keystore)

## Set Up Environment Variables
   ```bash
   # Set your network (sepolia or mainnet)
   export NETWORK="sepolia"
   
   # Set RPC URL
   export RPC_URL="https://starknet-sepolia.public.blastapi.io"
   # For mainnet: export RPC_URL="https://starknet-mainnet.public.blastapi.io"
   
   # Set account and keystore paths
   export ACCOUNT_FILE="$HOME/.starkli-wallets/deployer/account.json"
   export KEYSTORE_FILE="$HOME/.starkli-wallets/deployer/keystore.json"
   
   # Set your owner address
   export OWNER_ADDRESS="0x3e4d9d11c7d5a9b3037fbeff83d05f6d2913e4b3f93e5bb07f9696ca9d01771"
   
   # Set treasury address (can be same as owner)
   export TREASURY_ADDRESS="0x3e4d9d11c7d5a9b3037fbeff83d05f6d2913e4b3f93e5bb07f9696ca9d01771"
   ```

---

## Deployment Order

Deploy contracts in this exact order:
1. EarnsToken
2. StEarnToken
3. EarnXDCManager
4. Escrow
5. BulkVesting
6. Staking
7. Vesting

---

## Step 1: Deploy EarnsToken

### Declare the contract
```bash
starkli declare \
  target/dev/earnscape_contracts_EarnsToken.contract_class.json \
  --account $ACCOUNT_FILE \
  --keystore $KEYSTORE_FILE \
  --rpc $RPC_URL
```

**Save the class hash output, e.g.:**
```bash
export EARNS_CLASS="0x012c3535b05b240c1d846d5d24adc3b21c4d91444bac52fc9ab8148aca79e892"
```

### Deploy the contract
```bash
starkli deploy \
  $EARNS_CLASS \
  $OWNER_ADDRESS \
  --account $ACCOUNT_FILE \
  --keystore $KEYSTORE_FILE \
  --rpc $RPC_URL
```

**Save the contract address:**
```bash
export EARNS_ADDR="0x..."  # Replace with actual deployed address
```

---

## Step 2: Deploy StEarnToken

### Declare the contract
```bash
starkli declare \
  target/dev/earnscape_contracts_StEarnToken.contract_class.json \
  --account $ACCOUNT_FILE \
  --keystore $KEYSTORE_FILE \
  --rpc $RPC_URL
```

**Save the class hash:**
```bash
export STEARN_CLASS="0x..."  # Replace with actual class hash
```

### Deploy the contract
```bash
starkli deploy \
  $STEARN_CLASS \
  $OWNER_ADDRESS \
  --account $ACCOUNT_FILE \
  --keystore $KEYSTORE_FILE \
  --rpc $RPC_URL
```

**Save the contract address:**
```bash
export STEARN_ADDR="0x..."  # Replace with actual deployed address
```

---

## Step 3: Deploy EarnXDCManager

### Declare the contract
```bash
starkli declare \
  target/dev/earnscape_contracts_EarnXDCManager.contract_class.json \
  --account $ACCOUNT_FILE \
  --keystore $KEYSTORE_FILE \
  --rpc $RPC_URL
```

**Save the class hash:**
```bash
export EARNXDC_CLASS="0x..."  # Replace with actual class hash
```

### Deploy the contract
**Constructor parameters:** `owner`, `earns_token_address`
```bash
starkli deploy \
  $EARNXDC_CLASS \
  $OWNER_ADDRESS \
  $EARNS_ADDR \
  --account $ACCOUNT_FILE \
  --keystore $KEYSTORE_FILE \
  --rpc $RPC_URL
```

**Save the contract address:**
```bash
export EARNXDC_ADDR="0x..."  # Replace with actual deployed address
```

---

## Step 4: Deploy Escrow

### Declare the contract
```bash
starkli declare \
  target/dev/earnscape_contracts_Escrow.contract_class.json \
  --account $ACCOUNT_FILE \
  --keystore $KEYSTORE_FILE \
  --rpc $RPC_URL
```

**Save the class hash:**
```bash
export ESCROW_CLASS="0x..."  # Replace with actual class hash
```

### Deploy the contract
**Constructor parameters:** `owner`, `earn_token`, `treasury`
```bash
starkli deploy \
  $ESCROW_CLASS \
  $OWNER_ADDRESS \
  $EARNS_ADDR \
  $TREASURY_ADDRESS \
  --account $ACCOUNT_FILE \
  --keystore $KEYSTORE_FILE \
  --rpc $RPC_URL
```

**Save the contract address:**
```bash
export ESCROW_ADDR="0x..."  # Replace with actual deployed address
```

---

## Step 5: Deploy BulkVesting

### Declare the contract
```bash
starkli declare \
  target/dev/earnscape_contracts_EarnscapeBulkVesting.contract_class.json \
  --account $ACCOUNT_FILE \
  --keystore $KEYSTORE_FILE \
  --rpc $RPC_URL
```

**Save the class hash:**
```bash
export BULK_VESTING_CLASS="0x..."  # Replace with actual class hash
```

### Deploy the contract
**Constructor parameters:** `earn_stark_manager`, `contract5_address` (Escrow), `token_address`, `owner`
```bash
starkli deploy \
  $BULK_VESTING_CLASS \
  $EARNXDC_ADDR \
  $ESCROW_ADDR \
  $EARNS_ADDR \
  $OWNER_ADDRESS \
  --account $ACCOUNT_FILE \
  --keystore $KEYSTORE_FILE \
  --rpc $RPC_URL
```

**Save the contract address:**
```bash
export BULK_VESTING_ADDR="0x..."  # Replace with actual deployed address
```

---

## Step 6: Deploy Staking

### Declare the contract
```bash
starkli declare \
  target/dev/earnscape_contracts_EarnscapeStaking.contract_class.json \
  --account $ACCOUNT_FILE \
  --keystore $KEYSTORE_FILE \
  --rpc $RPC_URL
```

**Save the class hash:**
```bash
export STAKING_CLASS="0x..."  # Replace with actual class hash
```

### Deploy the contract
**Constructor parameters:** `owner`, `earn_token`, `stearn_token`, `treasury`
```bash
starkli deploy \
  $STAKING_CLASS \
  $OWNER_ADDRESS \
  $EARNS_ADDR \
  $STEARN_ADDR \
  $TREASURY_ADDRESS \
  --account $ACCOUNT_FILE \
  --keystore $KEYSTORE_FILE \
  --rpc $RPC_URL
```

**Save the contract address:**
```bash
export STAKING_ADDR="0x..."  # Replace with actual deployed address
```

---

## Step 7: Deploy Vesting

### Declare the contract
```bash
starkli declare \
  target/dev/earnscape_contracts_EarnscapeVesting.contract_class.json \
  --account $ACCOUNT_FILE \
  --keystore $KEYSTORE_FILE \
  --rpc $RPC_URL
```

**Save the class hash:**
```bash
export VESTING_CLASS="0x..."  # Replace with actual class hash
```

### Deploy the contract
**Constructor parameters:** `owner`, `earn_token`, `stearn_token`, `treasury`, `staking_contract`, `_platform`
```bash
starkli deploy \
  $VESTING_CLASS \
  $OWNER_ADDRESS \
  $EARNS_ADDR \
  $STEARN_ADDR \
  $TREASURY_ADDRESS \
  $STAKING_ADDR \
  $OWNER_ADDRESS \
  --account $ACCOUNT_FILE \
  --keystore $KEYSTORE_FILE \
  --rpc $RPC_URL
```

**Save the contract address:**
```bash
export VESTING_ADDR="0x..."  # Replace with actual deployed address
```

---

# Method B: Deployment with External Wallet Private Key

This method uses your raw private key and creates temporary account files for deployment.

## Step 0: Set Up Environment Variables

```bash
# Set your network
export NETWORK="sepolia"

# Set RPC URL
export RPC_URL="https://starknet-sepolia.public.blastapi.io/rpc/v0_7"
# For mainnet: export RPC_URL="https://starknet-mainnet.public.blastapi.io/rpc/v0_7"

# Set your deployer address and private key
export DEPLOYER_ADDRESS="0x0565369766d6Ce385D339CaAC890f4e6Fd8d6a62Fe441556ECA83c37ed047028"
export DEPLOYER_PRIVATE_KEY="0x<your_private_key_here>"

# Set owner address (can be same as deployer)
export OWNER_ADDRESS="$DEPLOYER_ADDRESS"

# Set treasury address
export TREASURY_ADDRESS="$DEPLOYER_ADDRESS"
```

## Step 1: Create Temporary Account Files

Starkli requires account and keystore files. Create temporary ones from your private key:

```bash
# Create temporary directory
mkdir -p /tmp/starkli_temp_$$

# Create temporary keystore file
TEMP_KEYSTORE="/tmp/starkli_temp_$$/keystore.json"
cat > "$TEMP_KEYSTORE" << EOF
{
  "crypto": {
    "cipher": "aes-128-ctr",
    "cipherparams": {"iv": "00000000000000000000000000000000"},
    "ciphertext": "$(echo -n $DEPLOYER_PRIVATE_KEY | xxd -p -c 256)",
    "kdf": "scrypt",
    "kdfparams": {
      "dklen": 32,
      "n": 8192,
      "p": 1,
      "r": 8,
      "salt": "0000000000000000000000000000000000000000000000000000000000000000"
    },
    "mac": "0000000000000000000000000000000000000000000000000000000000000000"
  },
  "id": "temp-keystore",
  "version": 3
}
EOF

# Create temporary account descriptor
TEMP_ACCOUNT="/tmp/starkli_temp_$$/account.json"
cat > "$TEMP_ACCOUNT" << EOF
{
  "version": 1,
  "variant": {
    "type": "open_zeppelin",
    "version": 1,
    "public_key": "0x0"
  },
  "deployment": {
    "status": "deployed",
    "class_hash": "0x0",
    "address": "$DEPLOYER_ADDRESS"
  }
}
EOF

echo "✓ Temporary account files created"
echo "  Keystore: $TEMP_KEYSTORE"
echo "  Account:  $TEMP_ACCOUNT"
```

**Note:** For production, it's better to use a simple approach - just export the variables and use our automated script. But for manual step-by-step control, continue below.

## Alternative: Simplified Approach (Recommended)

Instead of creating temporary files manually, use this simpler approach for each command:

```bash
# Add these flags to every starkli command:
--account /tmp/temp_account_$$.json \
--keystore /tmp/temp_keystore_$$.json \
--keystore-password ""
```

## Step 2: Deploy EarnsToken

### Declare EarnsToken

```bash
starkli declare \
  target/dev/earnscape_contracts_EarnsToken.contract_class.json \
  --account "$TEMP_ACCOUNT" \
  --keystore "$TEMP_KEYSTORE" \
  --keystore-password "" \
  --rpc $RPC_URL
```

**Expected output:**
```
Class hash declared: 0x...
```

**Save the class hash:**
```bash
export EARNS_CLASS="0x..."  # Copy from output
```

### Deploy EarnsToken

**Constructor parameter:** `owner`

```bash
starkli deploy \
  $EARNS_CLASS \
  $OWNER_ADDRESS \
  --account "$TEMP_ACCOUNT" \
  --keystore "$TEMP_KEYSTORE" \
  --keystore-password "" \
  --rpc $RPC_URL
```

**Save the contract address:**
```bash
export EARNS_ADDR="0x..."  # Copy from output
echo "EarnsToken deployed: $EARNS_ADDR"
```

## Step 3: Deploy StEarnToken

### Declare StEarnToken

```bash
starkli declare \
  target/dev/earnscape_contracts_StEarnToken.contract_class.json \
  --account "$TEMP_ACCOUNT" \
  --keystore "$TEMP_KEYSTORE" \
  --keystore-password "" \
  --rpc $RPC_URL
```

**Save the class hash:**
```bash
export STEARN_CLASS="0x..."  # Copy from output
```

### Deploy StEarnToken

**Constructor parameter:** `owner`

```bash
starkli deploy \
  $STEARN_CLASS \
  $OWNER_ADDRESS \
  --account "$TEMP_ACCOUNT" \
  --keystore "$TEMP_KEYSTORE" \
  --keystore-password "" \
  --rpc $RPC_URL
```

**Save the contract address:**
```bash
export STEARN_ADDR="0x..."  # Copy from output
echo "StEarnToken deployed: $STEARN_ADDR"
```

## Step 4: Deploy EarnXDCManager

### Declare EarnXDCManager

```bash
starkli declare \
  target/dev/earnscape_contracts_EarnXDCManager.contract_class.json \
  --account "$TEMP_ACCOUNT" \
  --keystore "$TEMP_KEYSTORE" \
  --keystore-password "" \
  --rpc $RPC_URL
```

**Save the class hash:**
```bash
export EARNXDC_CLASS="0x..."  # Copy from output
```

### Deploy EarnXDCManager

**Constructor parameters:** `earns_token_address`, `owner`

```bash
starkli deploy \
  $EARNXDC_CLASS \
  $EARNS_ADDR \
  $OWNER_ADDRESS \
  --account "$TEMP_ACCOUNT" \
  --keystore "$TEMP_KEYSTORE" \
  --keystore-password "" \
  --rpc $RPC_URL
```

**Save the contract address:**
```bash
export EARNXDC_ADDR="0x..."  # Copy from output
echo "EarnXDCManager deployed: $EARNXDC_ADDR"
```

## Step 5: Deploy BulkVesting

### Declare BulkVesting

```bash
starkli declare \
  target/dev/earnscape_contracts_EarnscapeBulkVesting.contract_class.json \
  --account "$TEMP_ACCOUNT" \
  --keystore "$TEMP_KEYSTORE" \
  --keystore-password "" \
  --rpc $RPC_URL
```

**Save the class hash:**
```bash
export BULK_VESTING_CLASS="0x..."  # Copy from output
```

### Deploy BulkVesting

**Constructor parameters:** `owner`, `payment_distributor`, `earn_token`, `escrow_contract`

**Note:** We'll use owner address as placeholder for escrow (will configure later)

```bash
starkli deploy \
  $BULK_VESTING_CLASS \
  $OWNER_ADDRESS \
  $OWNER_ADDRESS \
  $EARNS_ADDR \
  $OWNER_ADDRESS \
  --account "$TEMP_ACCOUNT" \
  --keystore "$TEMP_KEYSTORE" \
  --keystore-password "" \
  --rpc $RPC_URL
```

**Save the contract address:**
```bash
export BULK_VESTING_ADDR="0x..."  # Copy from output
echo "BulkVesting deployed: $BULK_VESTING_ADDR"
```

## Step 6: Deploy Escrow

### Declare Escrow

```bash
starkli declare \
  target/dev/earnscape_contracts_Escrow.contract_class.json \
  --account "$TEMP_ACCOUNT" \
  --keystore "$TEMP_KEYSTORE" \
  --keystore-password "" \
  --rpc $RPC_URL
```

**Save the class hash:**
```bash
export ESCROW_CLASS="0x..."  # Copy from output
```

### Deploy Escrow

**Constructor parameters:** `owner`, `earn_token`, `treasury`

```bash
starkli deploy \
  $ESCROW_CLASS \
  $OWNER_ADDRESS \
  $EARNS_ADDR \
  $TREASURY_ADDRESS \
  --account "$TEMP_ACCOUNT" \
  --keystore "$TEMP_KEYSTORE" \
  --keystore-password "" \
  --rpc $RPC_URL
```

**Save the contract address:**
```bash
export ESCROW_ADDR="0x..."  # Copy from output
echo "Escrow deployed: $ESCROW_ADDR"
```

## Step 7: Deploy Staking

### Declare Staking

```bash
starkli declare \
  target/dev/earnscape_contracts_EarnscapeStaking.contract_class.json \
  --account "$TEMP_ACCOUNT" \
  --keystore "$TEMP_KEYSTORE" \
  --keystore-password "" \
  --rpc $RPC_URL
```

**Save the class hash:**
```bash
export STAKING_CLASS="0x..."  # Copy from output
```

### Deploy Staking

**Constructor parameters:** `owner`, `earn_token`, `stearn_token`, `treasury`

```bash
starkli deploy \
  $STAKING_CLASS \
  $OWNER_ADDRESS \
  $EARNS_ADDR \
  $STEARN_ADDR \
  $TREASURY_ADDRESS \
  --account "$TEMP_ACCOUNT" \
  --keystore "$TEMP_KEYSTORE" \
  --keystore-password "" \
  --rpc $RPC_URL
```

**Save the contract address:**
```bash
export STAKING_ADDR="0x..."  # Copy from output
echo "Staking deployed: $STAKING_ADDR"
```

## Step 8: Deploy Vesting

### Declare Vesting

```bash
starkli declare \
  target/dev/earnscape_contracts_EarnscapeVesting.contract_class.json \
  --account "$TEMP_ACCOUNT" \
  --keystore "$TEMP_KEYSTORE" \
  --keystore-password "" \
  --rpc $RPC_URL
```

**Save the class hash:**
```bash
export VESTING_CLASS="0x..."  # Copy from output
```

### Deploy Vesting

**Constructor parameters:** `owner`, `earn_token`, `stearn_token`, `treasury`, `staking_contract`, `_platform`

```bash
starkli deploy \
  $VESTING_CLASS \
  $OWNER_ADDRESS \
  $EARNS_ADDR \
  $STEARN_ADDR \
  $TREASURY_ADDRESS \
  $STAKING_ADDR \
  $OWNER_ADDRESS \
  --account "$TEMP_ACCOUNT" \
  --keystore "$TEMP_KEYSTORE" \
  --keystore-password "" \
  --rpc $RPC_URL
```

**Save the contract address:**
```bash
export VESTING_ADDR="0x..."  # Copy from output
echo "Vesting deployed: $VESTING_ADDR"
```

## Step 9: Save All Deployment Addresses

Create a deployment record:

```bash
cat > deployed_addresses.env << EOF
# Earnscape Contracts Deployment
# Network: $NETWORK
# Date: $(date)
# Deployer: $DEPLOYER_ADDRESS

export EARNS_TOKEN_ADDRESS="$EARNS_ADDR"
export STEARN_TOKEN_ADDRESS="$STEARN_ADDR"
export EARNXDC_MANAGER_ADDRESS="$EARNXDC_ADDR"
export BULK_VESTING_ADDRESS="$BULK_VESTING_ADDR"
export ESCROW_ADDRESS="$ESCROW_ADDR"
export STAKING_ADDRESS="$STAKING_ADDR"
export VESTING_ADDRESS="$VESTING_ADDR"
EOF

echo "✓ Deployment addresses saved to deployed_addresses.env"
cat deployed_addresses.env
```

## Step 10: Configure Contracts (Post-Deployment)

Now configure the deployed contracts to work together:

### 1. Configure EarnsToken

Set contract4 (BulkVesting) and contract5 (Escrow):

```bash
starkli invoke \
  $EARNS_ADDR \
  set_contract4 \
  $BULK_VESTING_ADDR \
  $ESCROW_ADDR \
  --account "$TEMP_ACCOUNT" \
  --keystore "$TEMP_KEYSTORE" \
  --keystore-password "" \
  --rpc $RPC_URL

echo "✓ EarnsToken configured"
```

### 2. Configure StEarnToken - Set Vesting Address

```bash
starkli invoke \
  $STEARN_ADDR \
  set_vesting_address \
  $VESTING_ADDR \
  --account "$TEMP_ACCOUNT" \
  --keystore "$TEMP_KEYSTORE" \
  --keystore-password "" \
  --rpc $RPC_URL

echo "✓ StEarnToken vesting address set"
```

### 3. Configure StEarnToken - Set Staking Address

```bash
starkli invoke \
  $STEARN_ADDR \
  set_staking_contract_address \
  $STAKING_ADDR \
  --account "$TEMP_ACCOUNT" \
  --keystore "$TEMP_KEYSTORE" \
  --keystore-password "" \
  --rpc $RPC_URL

echo "✓ StEarnToken staking address set"
```

### 4. Transfer StEarnToken Ownership to Staking

```bash
starkli invoke \
  $STEARN_ADDR \
  transfer_ownership \
  $STAKING_ADDR \
  --account "$TEMP_ACCOUNT" \
  --keystore "$TEMP_KEYSTORE" \
  --keystore-password "" \
  --rpc $RPC_URL

echo "✓ StEarnToken ownership transferred to Staking"
```

### 5. Configure EarnXDCManager - Set Vesting Address

```bash
starkli invoke \
  $EARNXDC_ADDR \
  set_vesting_address \
  $VESTING_ADDR \
  --account "$TEMP_ACCOUNT" \
  --keystore "$TEMP_KEYSTORE" \
  --keystore-password "" \
  --rpc $RPC_URL

echo "✓ EarnXDCManager vesting address set"
```

## Step 11: Verify Configuration

### Verify EarnsToken

```bash
# Check contract4 (BulkVesting)
starkli call $EARNS_ADDR contract4 --rpc $RPC_URL

# Check contract5 (Escrow)
starkli call $EARNS_ADDR contract5 --rpc $RPC_URL
```

### Verify StEarnToken

```bash
# Check vesting_contract
starkli call $STEARN_ADDR vesting_contract --rpc $RPC_URL

# Check staking_contract
starkli call $STEARN_ADDR staking_contract --rpc $RPC_URL

# Check owner (should be Staking address)
starkli call $STEARN_ADDR owner --rpc $RPC_URL
```

### Verify EarnXDCManager

```bash
# Check vesting address
starkli call $EARNXDC_ADDR vesting --rpc $RPC_URL
```

## Step 12: Cleanup Temporary Files

```bash
# Remove temporary files
rm -f "$TEMP_KEYSTORE" "$TEMP_ACCOUNT"
rmdir /tmp/starkli_temp_$$ 2>/dev/null

echo "✓ Temporary files cleaned up"
```

## Quick Reference: Method B Complete Script

Here's a complete script that does all the above:

```bash
#!/bin/bash

# Set variables
export NETWORK="sepolia"
export RPC_URL="https://starknet-sepolia.public.blastapi.io/rpc/v0_7"
export DEPLOYER_ADDRESS="0x0565369766d6Ce385D339CaAC890f4e6Fd8d6a62Fe441556ECA83c37ed047028"
export DEPLOYER_PRIVATE_KEY="0x<your_private_key>"
export OWNER_ADDRESS="$DEPLOYER_ADDRESS"
export TREASURY_ADDRESS="$DEPLOYER_ADDRESS"

# Create temp files
export TEMP_KEYSTORE="/tmp/starkli_keystore_$$.json"
export TEMP_ACCOUNT="/tmp/starkli_account_$$.json"

# Create keystore (simplified - just for reference, use the automated script instead)
cat > "$TEMP_KEYSTORE" << 'EOF'
{"version":3,"id":"temp","crypto":{"cipher":"aes-128-ctr","cipherparams":{"iv":"00000000000000000000000000000000"},"ciphertext":"","kdf":"scrypt","kdfparams":{"dklen":32,"n":8192,"p":1,"r":8,"salt":"0000000000000000000000000000000000000000000000000000000000000000"},"mac":"0000000000000000000000000000000000000000000000000000000000000000"}}
EOF

# Create account descriptor
cat > "$TEMP_ACCOUNT" << EOF
{"version":1,"variant":{"type":"open_zeppelin","version":1,"public_key":"0x0"},"deployment":{"status":"deployed","class_hash":"0x0","address":"$DEPLOYER_ADDRESS"}}
EOF

# Now follow steps 2-11 above...
# Or better yet, just use: ./deploy_with_private_key.sh

# Cleanup
trap 'rm -f "$TEMP_KEYSTORE" "$TEMP_ACCOUNT"' EXIT
```

**IMPORTANT:** For actual deployment, it's recommended to use the automated script:

```bash
export DEPLOYER_ADDRESS="0x0565369766d6Ce385D339CaAC890f4e6Fd8d6a62Fe441556ECA83c37ed047028"
export DEPLOYER_PRIVATE_KEY="0x<your_private_key>"
./deploy_with_private_key.sh
```

The automated script handles all temporary files, error checking, and configuration automatically!

---

## Post-Deployment Configuration

After deployment (whichever method you used), configure the contracts:

### 1. Configure EarnsToken
Set authorized contracts (Escrow and BulkVesting):
```bash
starkli invoke \
  $EARNS_ADDR \
  set_contract4 \
  $ESCROW_ADDR \
  $BULK_VESTING_ADDR \
  --account $ACCOUNT_FILE \
  --keystore $KEYSTORE_FILE \
  --rpc $RPC_URL
```

### 2. Configure Escrow
Link to BulkVesting:
```bash
starkli invoke \
  $ESCROW_ADDR \
  set_contract4 \
  $BULK_VESTING_ADDR \
  --account $ACCOUNT_FILE \
  --keystore $KEYSTORE_FILE \
  --rpc $RPC_URL
```

### 3. Configure Staking
Link to Vesting contract:
```bash
starkli invoke \
  $STAKING_ADDR \
  set_contract3 \
  $VESTING_ADDR \
  --account $ACCOUNT_FILE \
  --keystore $KEYSTORE_FILE \
  --rpc $RPC_URL
```

### 4. Transfer StEarnToken Ownership
Transfer ownership to Staking contract (so only Staking can mint/burn stEARN):
```bash
starkli invoke \
  $STEARN_ADDR \
  transfer_ownership \
  $STAKING_ADDR \
  --account $ACCOUNT_FILE \
  --keystore $KEYSTORE_FILE \
  --rpc $RPC_URL
```

---

## Verification Commands

### Verify EarnsToken Configuration
```bash
# Check contract4 (should return Escrow address)
starkli call $EARNS_ADDR contract4 --rpc $RPC_URL

# Check contract5 (should return BulkVesting address)
starkli call $EARNS_ADDR contract5 --rpc $RPC_URL
```

### Verify Escrow Configuration
```bash
# Check contract4 (should return BulkVesting address)
starkli call $ESCROW_ADDR contract4 --rpc $RPC_URL
```

### Verify Staking Configuration
```bash
# Check contract3 (should return Vesting address)
starkli call $STAKING_ADDR contract3 --rpc $RPC_URL
```

### Verify StEarnToken Ownership
```bash
# Check owner (should return Staking address)
starkli call $STEARN_ADDR owner --rpc $RPC_URL
```

---

## Quick Reference: All Deployed Addresses

Save all your deployed addresses for easy reference:

```bash
echo "EARNSCAPE DEPLOYMENT ADDRESSES" > deployed_addresses.txt
echo "Network: $NETWORK" >> deployed_addresses.txt
echo "Date: $(date)" >> deployed_addresses.txt
echo "" >> deployed_addresses.txt
echo "[1] EarnsToken:     $EARNS_ADDR" >> deployed_addresses.txt
echo "[2] StEarnToken:    $STEARN_ADDR" >> deployed_addresses.txt
echo "[3] EarnXDCManager: $EARNXDC_ADDR" >> deployed_addresses.txt
echo "[4] Escrow:         $ESCROW_ADDR" >> deployed_addresses.txt
echo "[5] BulkVesting:    $BULK_VESTING_ADDR" >> deployed_addresses.txt
echo "[6] Staking:        $STAKING_ADDR" >> deployed_addresses.txt
echo "[7] Vesting:        $VESTING_ADDR" >> deployed_addresses.txt

cat deployed_addresses.txt
```

---

## Explorer Links

### Sepolia Testnet
- Explorer: https://sepolia.starkscan.co/
- Your contracts: `https://sepolia.starkscan.co/contract/{CONTRACT_ADDRESS}`

### Mainnet
- Explorer: https://starkscan.co/
- Your contracts: `https://starkscan.co/contract/{CONTRACT_ADDRESS}`

---

## Troubleshooting

### Issue: "Class already declared"
**Solution:** This is normal. Just use the existing class hash shown in the output.

### Issue: "Failed to create Felt from string"
**Solution:** Check that your address is properly formatted (starts with 0x, valid hex).

### Issue: "Account not found"
**Solution:** Verify your account file exists at the specified path and has funds.

### Issue: "Insufficient balance"
**Solution:** Fund your account with ETH on the network you're deploying to.

### Issue: "Invalid constructor calldata"
**Solution:** Verify you're passing the correct number and order of constructor parameters.

---

## Notes

1. **Network Fees:** Ensure your deployer account has sufficient ETH for transaction fees
2. **Gas Estimation:** Each contract deployment may require different gas amounts
3. **Confirmation Time:** Wait for transaction confirmation before proceeding to next step
4. **Save Addresses:** Always save contract addresses and class hashes immediately
5. **Configuration Order:** Post-deployment configuration must be done in the specified order

---

## Contract Constructor Parameters Reference

| Contract | Parameters |
|----------|-----------|
| EarnsToken | `owner` |
| StEarnToken | `owner` |
| EarnXDCManager | `owner`, `earns_token_address` |
| BulkVesting | `owner`, `payment_distributor`, `earn_token`, `escrow_contract` |
| Escrow | `owner`, `earn_token`, `treasury` |
| Staking | `owner`, `earn_token`, `stearn_token`, `treasury` |
| Vesting | `owner`, `earn_token`, `stearn_token`, `treasury`, `staking_contract`, `_platform` |

---

**Last Updated:** October 17, 2025  
**Version:** 1.0  
**Network Support:** Starknet Sepolia & Mainnet
