# Earnscape Smart Contracts

Smart-contract monorepo for **Earnscape**, containing all on-chain logic deployed on **Starknet** (Cairo v2) and a single **BNB Chain** (EVM) contract responsible for **rewards distribution**. This repository is code-only (no clients, APIs, or infra), designed to be auditable, modular, and production-ready.

---

## Contents

* **Starknet (Cairo v2)**
  Core protocol: stream/session lifecycle, creator accounts, earnings ledger, fraud/strike registry hooks, payout intents, oracle adapters, and L2 treasury.
* **BNB Chain (Solidity)**
  Reward distribution contract (pull-based), merkle/claims tooling, role-gated funding, and spend limits.

```
.
├─ contracts/
│  ├─ starknet/
│  │  ├─ core/
│  │  │  ├─ CreatorRegistry.cairo
│  │  │  ├─ StreamRegistry.cairo
│  │  │  ├─ SessionManager.cairo
│  │  │  ├─ EarningsLedger.cairo
│  │  │  └─ TreasuryL2.cairo
│  │  ├─ rewards/
│  │  │  ├─ PayoutIntent.cairo
│  │  │  ├─ MerklePublisher.cairo
│  │  │  └─ StablecoinAdapter.cairo
│  │  ├─ governance/
│  │  │  ├─ Roles.cairo
│  │  │  ├─ Pausable.cairo
│  │  │  └─ Proxy.cairo
│  │  ├─ libs/
│  │  │  ├─ math/
│  │  │  └─ utils/
│  │  └─ interfaces/
│  │     ├─ ICreatorRegistry.cairo
│  │     ├─ IStreamRegistry.cairo
│  │     └─ IPayoutIntent.cairo
│  └─ evm/
│     ├─ RewardsDistributor.sol
│     ├─ MerkleRootHistory.sol
│     ├─ AccessRoles.sol
│     └─ interfaces/
│        ├─ IERC20.sol
│        └─ IRewardsDistributor.sol
├─ scripts/
│  ├─ starknet/
│  │  ├─ deploy.sh
│  │  ├─ publish_merkle.ts
│  │  └─ simulate_payout.ts
│  └─ evm/
│     ├─ deploy.ts
│     └─ seed_treasury.ts
├─ test/
│  ├─ starknet/  (snforge tests)
│  └─ evm/       (foundry tests)
├─ audits/       (place external reports here)
├─ .env.example
└─ LICENSE
```

---

## High-Level Architecture

* **Starknet L2 (truth layer)**

  * `CreatorRegistry`: KYC/attestation hash anchor, role flags, ban/strike status.
  * `StreamRegistry`: canonical source of stream/session metadata and status.
  * `SessionManager`: session open/close; accumulates earnings signals (views, ad events, milestones) from off-chain attestors via allow-listed callers.
  * `EarningsLedger`: net earnings per creator; emits `PayoutIntent` creation events.
  * `PayoutIntent`: builds **merkle leaves** for claimable rewards; writes roots to `MerklePublisher`.
  * `TreasuryL2`: holds stablecoin on L2 for accounting; not a user-facing disburser.
  * **Upgradeability** via minimal proxy + UUPS-style pattern; **Pausable** and **Roles** guard rails.

* **BNB Chain L1 (distribution layer)**

  * `RewardsDistributor`: ERC20 payouts (e.g., USDC) using **Merkle proofs**. Supports time-boxed roots, per-epoch spend caps, re-entrancy protection, and role-gated funding.
  * `MerkleRootHistory`: append-only registry of active roots and epochs.
  * Separation of concerns: L2 computes and publishes roots; L1 only verifies membership and transfers tokens.

> Messaging/bridging: this repo expects an **off-chain publisher** (script/ops pipeline) to sync the latest **merkle root** produced on Starknet into the `RewardsDistributor` on BNB Chain. You may use any bridging/ops stack you trust; the contracts are agnostic.

---

## Key Properties

* **Immediate earning eligibility**: no minimum followers enforced on-chain; policy gates live off-chain via registry flags.
* **Pull-based claims**: creators claim to their own wallet, minimizing custodial risk.
* **Double-spend safe**: leaf nonce and epoch scoping; claimed bitmap per epoch.
* **Auditable**: merkle roots and per-epoch caps visible on-chain; L2 events anchor the computation trail.
* **Upgradable yet safe**: admin timelock and pause pattern recommended (see deployment notes).

---

## Prerequisites

* **Starknet (Cairo v2) toolchain**

  * [Scarb](https://docs.swmansion.com/scarb/)
  * Starknet Foundry: `snforge`, `sncast`
  * Optional CLI: `starkli`
* **EVM toolchain**

  * Foundry (`forge`, `cast`) or Hardhat
  * Node.js 18+, PNPM/Yarn
* **Chains & Tokens**

  * Starknet testnet RPC
  * BNB Chain testnet RPC
  * Test USDC (or ERC20) for funding `RewardsDistributor`

---

## Quick Start

### 1) Clone and install

```bash
git clone https://github.com/your-org/earnscape-contracts.git
cd earnscape-contracts
cp .env.example .env
```

### 2) Build Starknet

```bash
scarb build
snforge test -f starknet
```

### 3) Build EVM

```bash
cd contracts/evm
forge install
forge build
forge test
```

---

## Configuration

Fill `.env` with your endpoints and keys:

```
# Starknet
STARKNET_RPC_URL=
STARKNET_ACCOUNT_ADDRESS=
STARKNET_ACCOUNT_PRIVATE_KEY=

# EVM
EVM_PRIVATE_KEY=
BNB_RPC_URL=
ERC20_TOKEN_ADDRESS=   # e.g., USDC test token
DISTRIBUTOR_ADMIN=     # deployer or timelock
```

---

## Deploy

### Starknet (example using sncast)

```bash
# 1) Deploy libraries if any, then core contracts:
sncast declare --contract-path target/dev/CreatorRegistry.sierra.json
sncast deploy --class-hash <hash> --constructor-calldata <args>

sncast declare --contract-path target/dev/StreamRegistry.sierra.json
sncast deploy --class-hash <hash> --constructor-calldata <args>

# ...repeat for SessionManager, EarningsLedger, PayoutIntent, TreasuryL2, Roles, Pausable, Proxy

# 2) Wire dependencies (set addresses in respective contracts):
sncast invoke --contract-address <EarningsLedger> --function set_payout_intent --calldata <PayoutIntent>
sncast invoke --contract-address <PayoutIntent> --function set_merkle_publisher --calldata <MerklePublisher>
```

### BNB Chain (Foundry)

```bash
forge script scripts/evm/deploy.ts \
  --rpc-url $BNB_RPC_URL \
  --private-key $EVM_PRIVATE_KEY \
  --broadcast
```

---

## Publishing a Payout (End-to-End)

1. **Aggregate off-chain** engagement and earnings → produce `(account, amount, epoch, nonce)` tuples.
2. **Anchor on Starknet**: call `PayoutIntent.create_intent(epoch, leaf_count, root_hash_placeholder)` and emit dataset hash/event.
3. **Generate Merkle** off-chain: compute `root`, build proofs, write JSON artifact.
4. **Publish Root on BNB**: call `RewardsDistributor.setRoot(epoch, root, totalAmount, deadline)`.
5. **Fund Distributor** with sufficient ERC20: `token.transfer(RewardsDistributor, totalAmount)`.
6. **Creators claim**: `claim(epoch, amount, proof)` → transfers tokens to caller.

> Scripts under `scripts/starknet` and `scripts/evm` show reference flows.

---

## Security & Best Practices

* **Roles**:

  * `DEFAULT_ADMIN_ROLE`: timelocked multisig recommended
  * `PUBLISHER_ROLE`: allowed to set merkle roots
  * `TREASURER_ROLE`: allowed to fund/withdraw treasury (if enabled)
* **Pausable**: emergency stop on claim/distribution.
* **Rate Limits**: per-epoch spend caps prevent oversized mistakes.
* **Re-entrancy & Checks-Effects-Interactions**: applied on EVM claims path.
* **Upgrades**: use a timelock + multi-sig; announce changes publicly.
* **Audits**: place third-party reports in `/audits`; do not deploy to mainnet without one.

---

## Testing

* **Starknet**

  ```bash
  snforge test -f starknet
  ```

  Tests cover registry flows, session accounting, ledger integrity, and payout intent emission.

* **EVM**

  ```bash
  forge test -vv
  ```

  Tests cover merkle claims (happy path and failures), re-entrancy guards, role checks, and caps.

---

## Gas, Fees & Limits

* **BNB Chain**: claims are O(log N) via Merkle proofs; gas scales with proof depth.
* **Starknet**: batch operations grouped where possible; per-call calldata kept minimal.

---

## Data Formats

**Merkle leaf (EVM)**
`keccak256(abi.encodePacked(account, amount, epoch, nonce))`

**Payout JSON artifact (off-chain)**

```json
{
  "epoch": 42,
  "token": "0xUSDC...",
  "root": "0x...",
  "total": "123456789",
  "claims": {
    "0xCreator1": { "amount": "1000000", "nonce": "7", "proof": ["0x..","0x.."] },
    "0xCreator2": { "amount": "2500000", "nonce": "3", "proof": ["0x..","0x.."] }
  }
}
```

---

## Integration Notes

* **Stablecoin**: set `ERC20_TOKEN_ADDRESS` to your USDC/paid-out token on BNB Chain.
* **Fraud/Strikes**: the L2 registry exposes flags; off-chain services should exclude flagged accounts from epochs.
* **Bridging**: if you later adopt a canonical bridge, constrain `setRoot` to accept roots only from a bridge messenger.

---

## Contributing

1. Fork and create a feature branch.
2. Add tests (Starknet `snforge`, EVM `forge`).
3. Run linters/formatters and ensure 100% test pass.
4. Open a PR with a concise description and rationale.

---

## License

Unless stated otherwise in the individual files, the contents of this repository are licensed under the **MIT License**. See `LICENSE` for details.

---

## Disclaimer

These contracts are provided **as-is**. Mainnet use requires rigorous audits, formal verification where applicable, and comprehensive monitoring. Always validate addresses, roles, and limits before deployment.
