# 🚀 EARNSCAPE - QUICK DEPLOYMENT GUIDE

## Complete Starknet Deployment Guide

Deploy 7 Earnscape contracts to Starknet in under 25 minutes.

**Contracts**: EarnsToken, StEarnToken, Escrow, EarnXDCManager, EarnscapeBulkVesting, EarnscapeVesting, EarnscapeStaking

**Note**: USDCBNBManager and USDCMATICManager are excluded (not needed for Starknet deployment).

---

## ⚡ Prerequisites (5 minutes)

### 1. Install Starkli

```bash
# Install Starkli
curl https://get.starkli.sh | sh
source ~/.bashrc
starkliup

# Verify
starkli --version
```

### 2. Create/Import Wallet

**Option A - Create New Wallet:**
```bash
mkdir -p ~/.starkli-wallets/deployer

# Create keystore
starkli signer keystore new ~/.starkli-wallets/deployer/keystore.json

# Create account
starkli account oz init ~/.starkli-wallets/deployer/account.json

# Deploy account (needs testnet ETH)
starkli account deploy ~/.starkli-wallets/deployer/account.json
```

**Option B - Import Existing:**
```bash
mkdir -p ~/.starkli-wallets/deployer
starkli signer keystore from-key ~/.starkli-wallets/deployer/keystore.json
# Enter your private key when prompted
```

### 3. Get Testnet ETH

- Sepolia Faucet: <https://faucet.goerli.starknet.io/>
- Blast Faucet: <https://blastapi.io/faucets/starknet-sepolia-eth>

---

## 📦 Deploy All 9 Contracts (20 minutes)

### Environment Setup

```bash
cd /home/Earnscape_cairo

export STARKNET_ACCOUNT=~/.starkli-wallets/deployer/account.json
export STARKNET_KEYSTORE=~/.starkli-wallets/deployer/keystore.json
export STARKNET_RPC="https://starknet-sepolia.public.blastapi.io"

# Get your wallet address
export OWNER=$(starkli account fetch $STARKNET_ACCOUNT --rpc $STARKNET_RPC | grep -oP '0x[a-fA-F0-9]+' | head -1)
echo "Owner address: $OWNER"
```

### Build First

```bash
scarb build
# Should see: Finished `dev` profile target(s) in ~30 seconds
```

---

## 🎯 Deploy Contracts (In Order)

### 1. EarnsToken (Main Token)

```bash
# Declare
EARNS_CLASS=$(starkli declare \
  target/dev/earnscape_contracts_EarnsToken.contract_class.json \
  --account $STARKNET_ACCOUNT \
  --keystore $STARKNET_KEYSTORE \
  --rpc $STARKNET_RPC 2>&1 | grep -oP '0x[a-fA-F0-9]+' | tail -1)

echo "EarnsToken class hash: $EARNS_CLASS"

# Deploy
EARNS_ADDR=$(starkli deploy \
  $EARNS_CLASS \
  $OWNER \
  --account $STARKNET_ACCOUNT \
  --keystore $STARKNET_KEYSTORE \
  --rpc $STARKNET_RPC 2>&1 | grep -oP '0x[a-fA-F0-9]+' | tail -1)

echo "✅ EarnsToken deployed: $EARNS_ADDR"
```

### 2. StEarnToken (Staked Token)

```bash
# Declare
STEARN_CLASS=$(starkli declare \
  target/dev/earnscape_contracts_StEarnToken.contract_class.json \
  --account $STARKNET_ACCOUNT \
  --keystore $STARKNET_KEYSTORE \
  --rpc $STARKNET_RPC 2>&1 | grep -oP '0x[a-fA-F0-9]+' | tail -1)

echo "StEarnToken class hash: $STEARN_CLASS"

# Deploy
STEARN_ADDR=$(starkli deploy \
  $STEARN_CLASS \
  $OWNER \
  --account $STARKNET_ACCOUNT \
  --keystore $STARKNET_KEYSTORE \
  --rpc $STARKNET_RPC 2>&1 | grep -oP '0x[a-fA-F0-9]+' | tail -1)

echo "✅ StEarnToken deployed: $STEARN_ADDR"
```

### 3. Escrow

```bash
# Set treasury address (can be same as owner for testing)
TREASURY=$OWNER

# Declare
ESCROW_CLASS=$(starkli declare \
  target/dev/earnscape_contracts_Escrow.contract_class.json \
  --account $STARKNET_ACCOUNT \
  --keystore $STARKNET_KEYSTORE \
  --rpc $STARKNET_RPC 2>&1 | grep -oP '0x[a-fA-F0-9]+' | tail -1)

echo "Escrow class hash: $ESCROW_CLASS"

# Deploy
ESCROW_ADDR=$(starkli deploy \
  $ESCROW_CLASS \
  $OWNER \
  $EARNS_ADDR \
  $TREASURY \
  --account $STARKNET_ACCOUNT \
  --keystore $STARKNET_KEYSTORE \
  --rpc $STARKNET_RPC 2>&1 | grep -oP '0x[a-fA-F0-9]+' | tail -1)

echo "✅ Escrow deployed: $ESCROW_ADDR"
```

### 4. USDCBNBManager

```bash
# Declare
USDC_BNB_CLASS=$(starkli declare \
  target/dev/earnscape_contracts_USDCBNBManager.contract_class.json \
  --account $STARKNET_ACCOUNT \
  --keystore $STARKNET_KEYSTORE \
  --rpc $STARKNET_RPC 2>&1 | grep -oP '0x[a-fA-F0-9]+' | tail -1)

# Deploy
USDC_BNB_ADDR=$(starkli deploy \
  $USDC_BNB_CLASS \
  $OWNER \
  --account $STARKNET_ACCOUNT \
  --keystore $STARKNET_KEYSTORE \
  --rpc $STARKNET_RPC 2>&1 | grep -oP '0x[a-fA-F0-9]+' | tail -1)

echo "✅ USDCBNBManager deployed: $USDC_BNB_ADDR"
```

### 5. USDCMATICManager

```bash
# Declare
USDC_MATIC_CLASS=$(starkli declare \
  target/dev/earnscape_contracts_USDCMATICManager.contract_class.json \
  --account $STARKNET_ACCOUNT \
  --keystore $STARKNET_KEYSTORE \
  --rpc $STARKNET_RPC 2>&1 | grep -oP '0x[a-fA-F0-9]+' | tail -1)

# Deploy
USDC_MATIC_ADDR=$(starkli deploy \
  $USDC_MATIC_CLASS \
  $OWNER \
  --account $STARKNET_ACCOUNT \
  --keystore $STARKNET_KEYSTORE \
  --rpc $STARKNET_RPC 2>&1 | grep -oP '0x[a-fA-F0-9]+' | tail -1)

echo "✅ USDCMATICManager deployed: $USDC_MATIC_ADDR"
```

### 6. EarnXDCManager

```bash
# Declare
EARNXDC_CLASS=$(starkli declare \
  target/dev/earnscape_contracts_EarnXDCManager.contract_class.json \
  --account $STARKNET_ACCOUNT \
  --keystore $STARKNET_KEYSTORE \
  --rpc $STARKNET_RPC 2>&1 | grep -oP '0x[a-fA-F0-9]+' | tail -1)

# Deploy
EARNXDC_ADDR=$(starkli deploy \
  $EARNXDC_CLASS \
  $OWNER \
  $EARNS_ADDR \
  --account $STARKNET_ACCOUNT \
  --keystore $STARKNET_KEYSTORE \
  --rpc $STARKNET_RPC 2>&1 | grep -oP '0x[a-fA-F0-9]+' | tail -1)

echo "✅ EarnXDCManager deployed: $EARNXDC_ADDR"
```

### 7. EarnscapeBulkVesting

```bash
# Declare
BULK_VESTING_CLASS=$(starkli declare \
  target/dev/earnscape_contracts_EarnscapeBulkVesting.contract_class.json \
  --account $STARKNET_ACCOUNT \
  --keystore $STARKNET_KEYSTORE \
  --rpc $STARKNET_RPC 2>&1 | grep -oP '0x[a-fA-F0-9]+' | tail -1)

echo "EarnscapeBulkVesting class hash: $BULK_VESTING_CLASS"

# Deploy (needs contract3, contract5/escrow, token, owner)
# Set contract3 same as owner for now
BULK_VESTING_ADDR=$(starkli deploy \
  $BULK_VESTING_CLASS \
  $OWNER \
  $ESCROW_ADDR \
  $EARNS_ADDR \
  $OWNER \
  --account $STARKNET_ACCOUNT \
  --keystore $STARKNET_KEYSTORE \
  --rpc $STARKNET_RPC 2>&1 | grep -oP '0x[a-fA-F0-9]+' | tail -1)

echo "✅ EarnscapeBulkVesting deployed: $BULK_VESTING_ADDR"
```

### 8. EarnscapeStaking

```bash
# Declare
STAKING_CLASS=$(starkli declare \
  target/dev/earnscape_contracts_EarnscapeStaking.contract_class.json \
  --account $STARKNET_ACCOUNT \
  --keystore $STARKNET_KEYSTORE \
  --rpc $STARKNET_RPC 2>&1 | grep -oP '0x[a-fA-F0-9]+' | tail -1)

echo "EarnscapeStaking class hash: $STAKING_CLASS"

# Deploy (needs owner, earn_token, stearn_token, vesting_contract)
# We'll deploy vesting first, then update staking
STAKING_ADDR=$(starkli deploy \
  $STAKING_CLASS \
  $OWNER \
  $EARNS_ADDR \
  $STEARN_ADDR \
  0x0 \
  --account $STARKNET_ACCOUNT \
  --keystore $STARKNET_KEYSTORE \
  --rpc $STARKNET_RPC 2>&1 | grep -oP '0x[a-fA-F0-9]+' | tail -1)

echo "✅ EarnscapeStaking deployed: $STAKING_ADDR"
```

### 9. EarnscapeVesting

```bash
# Declare
VESTING_CLASS=$(starkli declare \
  target/dev/earnscape_contracts_EarnscapeVesting.contract_class.json \
  --account $STARKNET_ACCOUNT \
  --keystore $STARKNET_KEYSTORE \
  --rpc $STARKNET_RPC 2>&1 | grep -oP '0x[a-fA-F0-9]+' | tail -1)

echo "EarnscapeVesting class hash: $VESTING_CLASS"

# Deploy (needs owner, token, stearn, staking, contract3, fee_recipient, merch_admin)
VESTING_ADDR=$(starkli deploy \
  $VESTING_CLASS \
  $OWNER \
  $EARNS_ADDR \
  $STEARN_ADDR \
  $STAKING_ADDR \
  $OWNER \
  $OWNER \
  $OWNER \
  --account $STARKNET_ACCOUNT \
  --keystore $STARKNET_KEYSTORE \
  --rpc $STARKNET_RPC 2>&1 | grep -oP '0x[a-fA-F0-9]+' | tail -1)

echo "✅ EarnscapeVesting deployed: $VESTING_ADDR"
```

---

## 📋 Summary & Save Addresses

```bash
cat > deployed_contracts.txt << EOF
===========================================
EARNSCAPE COMPLETE DEPLOYMENT - $(date)
===========================================
Network: Starknet Sepolia
Owner: $OWNER

CONTRACT ADDRESSES:
-------------------------------------------
1. EarnsToken:              $EARNS_ADDR
2. StEarnToken:             $STEARN_ADDR
3. Escrow:                  $ESCROW_ADDR
4. USDCBNBManager:          $USDC_BNB_ADDR
5. USDCMATICManager:        $USDC_MATIC_ADDR
6. EarnXDCManager:          $EARNXDC_ADDR
7. EarnscapeBulkVesting:    $BULK_VESTING_ADDR
8. EarnscapeStaking:        $STAKING_ADDR
9. EarnscapeVesting:        $VESTING_ADDR

CLASS HASHES:
-------------------------------------------
EarnsToken:              $EARNS_CLASS
StEarnToken:             $STEARN_CLASS
Escrow:                  $ESCROW_CLASS
USDCBNBManager:          $USDC_BNB_CLASS
USDCMATICManager:        $USDC_MATIC_CLASS
EarnXDCManager:          $EARNXDC_CLASS
EarnscapeBulkVesting:    $BULK_VESTING_CLASS
EarnscapeStaking:        $STAKING_CLASS
EarnscapeVesting:        $VESTING_CLASS

VIEW ON EXPLORER:
-------------------------------------------
https://sepolia.starkscan.co/contract/$EARNS_ADDR
https://sepolia.starkscan.co/contract/$STAKING_ADDR
https://sepolia.starkscan.co/contract/$VESTING_ADDR

EOF

cat deployed_contracts.txt
echo ""
echo "✅ All 9 contracts deployed! Deployment info saved to deployed_contracts.txt"
```

---

## ⚙️ Post-Deployment Configuration

### Step 1: Configure EarnsToken Distribution

```bash
# Set contract4 (escrow) and contract5 (treasury)
starkli invoke \
  $EARNS_ADDR \
  set_contract4 \
  $ESCROW_ADDR \
  $OWNER \
  --account $STARKNET_ACCOUNT \
  --keystore $STARKNET_KEYSTORE \
  --rpc $STARKNET_RPC

echo "✅ EarnsToken configured with Escrow"
```

### Step 2: Configure Escrow

```bash
# Set contract4 to vesting contract
starkli invoke \
  $ESCROW_ADDR \
  set_contract4 \
  $BULK_VESTING_ADDR \
  --account $STARKNET_ACCOUNT \
  --keystore $STARKNET_KEYSTORE \
  --rpc $STARKNET_RPC

echo "✅ Escrow configured with BulkVesting"
```

### Step 3: Update Staking with Vesting Address

```bash
starkli invoke \
  $STAKING_ADDR \
  update_vesting_contract \
  $VESTING_ADDR \
  --account $STARKNET_ACCOUNT \
  --keystore $STARKNET_KEYSTORE \
  --rpc $STARKNET_RPC

echo "✅ Staking contract linked to Vesting"
```

### Step 4: Transfer StEarnToken Ownership to Staking

```bash
starkli invoke \
  $STEARN_ADDR \
  transfer_ownership \
  $STAKING_ADDR \
  --account $STARKNET_ACCOUNT \
  --keystore $STARKNET_KEYSTORE \
  --rpc $STARKNET_RPC

echo "✅ StEarnToken ownership transferred to Staking contract"
```

---

## 🧪 Quick Test Suite

```bash
echo "=========================================="
echo "Testing Deployed Contracts"
echo "=========================================="
echo ""

# Test 1: Check EARNS total supply
echo "1️⃣ Checking EARNS total supply..."
SUPPLY=$(starkli call $EARNS_ADDR total_supply --rpc $STARKNET_RPC)
echo "Total supply: $SUPPLY"
echo "Expected: 1000000000000000000000000000 (1 billion with 18 decimals)"
echo ""

# Test 2: Check EARNS name
echo "2️⃣ Checking EARNS name..."
starkli call $EARNS_ADDR name --rpc $STARKNET_RPC
echo ""

# Test 3: Check contract4 address
echo "3️⃣ Checking contract4..."
CONTRACT4=$(starkli call $EARNS_ADDR get_contract4 --rpc $STARKNET_RPC)
echo "Contract4: $CONTRACT4"
echo "Expected: $ESCROW_ADDR"
echo ""

# Test 4: Check stEARN symbol
echo "4️⃣ Checking stEARN symbol..."
starkli call $STEARN_ADDR symbol --rpc $STARKNET_RPC
echo ""

# Test 5: Check escrow balance
echo "5️⃣ Checking Escrow balance..."
ESCROW_BAL=$(starkli call $ESCROW_ADDR get_escrow_balance --rpc $STARKNET_RPC)
echo "Escrow balance: $ESCROW_BAL"
echo "Expected: 500000000000000000000000000 (500 million)"
echo ""

# Test 6: Check bulk vesting categories
echo "6️⃣ Checking BulkVesting category 0 (Seed Investors)..."
starkli call $BULK_VESTING_ADDR get_category_details 0 --rpc $STARKNET_RPC
echo ""

# Test 7: Check staking contract
echo "7️⃣ Checking Staking total staked EARN..."
starkli call $STAKING_ADDR get_total_staked_earn --rpc $STARKNET_RPC
echo "Expected: 0 (no stakes yet)"
echo ""

# Test 8: Check vesting platform fee
echo "8️⃣ Checking Vesting platform fee..."
starkli call $VESTING_ADDR get_platform_fee_pct --rpc $STARKNET_RPC
echo "Expected: 200 (2%)"
echo ""

echo "=========================================="
echo "✅ All tests completed!"
echo "=========================================="
```

---

## 🎉 Success!

You've deployed all 9 Earnscape contracts to Starknet!

### View on Explorer

- **EarnsToken**: `https://sepolia.starkscan.co/contract/$EARNS_ADDR`
- **Staking**: `https://sepolia.starkscan.co/contract/$STAKING_ADDR`
- **Vesting**: `https://sepolia.starkscan.co/contract/$VESTING_ADDR`
- **All others**: Check `deployed_contracts.txt`

### Next Steps

1. ✅ Verify contracts on Starkscan
2. ✅ Add users to BulkVesting categories
3. ✅ Test staking functionality
4. ✅ Test vesting and tipping
5. ✅ Integrate with frontend

### Important Files

- `deployed_contracts.txt` - All deployment addresses (KEEP SAFE!)
- `CAIRO_CONTRACTS.md` - Complete contract documentation
- `SOLIDITY_CONTRACTS.md` - Original Solidity reference

---

## 🆘 Troubleshooting

**"Insufficient balance"**: Need more testnet ETH from faucet

**"Class already declared"**: Reuse the existing class hash (save gas!)

**"Account not found"**: Make sure account is deployed first

**"RPC error"**: Try different RPC endpoint or check network status

**"Invalid constructor arguments"**: Check argument order and types

**Need help?**: Check contract documentation or test each function individually

---

**Created**: October 16, 2025  
**Status**: Ready for Complete Deployment  
**Contracts**: 7/7 Complete (100%)  
**Note**: USDCBNBManager and USDCMATICManager excluded from Starknet deployment
**Network**: Starknet Sepolia Testnet
