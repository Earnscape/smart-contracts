# End-to-End Test Cases — Earn / Manager / Vesting / Staking Flow

**Scope:** This document lists concise, professional test cases that verify the full interaction flow between the following Cairo contracts deployed on StarkNet Sepolia: **EarnToken (EARN)**, **EarnStarkManager (Manager)**, **Vesting**, **Staking**, and **stEARN** (if applicable). The tests are organized per-file and focus solely on test case flows and assertions.

---

## Quick summary

The test suite validates: owner token balances and transfer to manager; manager → vesting deposits; vesting releasable/locked balances; staking approvals and staking actions; release and force-release of vested amounts; reshuffle and unstake behaviors; tipping flows between users; and negative/error conditions. The flow repeats for multiple users (user1, user2, user3) with specified differences.

---

## Constants and preconditions

- **TEN_THOUSAND** = 10,000 scaled by token decimals used in project.  
- **ONE_THOUSAND** = 1,000 scaled by token decimals.  
- **TIP_AMOUNT** = 100 scaled by token decimals.  
- **Accounts:** OWNER, USER1, USER2, USER3 (test harness cheat accounts).  
- **Helpers expected:** `setup_*` helpers, `transfer_token`, `approve_token`, `get_balance`, dispatcher interfaces, and time-warp helpers if vesting is time-dependent.

---

## Test file list

- `flow_01_owner_to_manager.cairo` — owner balance and transfer to manager; address wiring checks.  
- `flow_02_deposit_and_vesting_checks.cairo` — manager deposits to vesting and vesting balance/releasable checks.  
- `flow_03_user1_stake_release_reshuffle.cairo` — user1 stake, release, reshuffle, force-release sequence; read checks.  
- `flow_04_user2_stake_release_unstake.cairo` — user2 flow using unstake instead of reshuffle.  
- `flow_05_user3_tip_and_extra_stakes.cairo` — user3 tip behavior and additional stake/error checks.  
- `flow_06_orchestrator_all_sequences.cairo` *(optional)* — single integration test executing full flow for CI.

---

# Detailed per-file test cases

Each file contains purpose, steps and expected assertions. Use your project's helper names where necessary. Ensure consistent token decimal scaling across all tests.

---

## `flow_01_owner_to_manager.cairo`

**Purpose:** Validate owner holds initial supply, transfer **10,000 EARN** → Manager, and ensure Manager links to Staking and Vesting addresses.

**Steps & assertions**

1. Deploy `EarnToken` and confirm `OWNER` balance == total supply.  
2. Deploy `EarnStarkManager` wired to `EarnToken`.  
3. Transfer `TEN_THOUSAND` from `OWNER` → `Manager`; assert Manager's token balance equals `TEN_THOUSAND`.  
4. Deploy `Staking` and `Vesting`; call owner-only setters on Manager to set staking and vesting addresses.  
5. Assert `manager.vesting() == vesting_address` and `manager.staking() == staking_address`.  
6. Negative check (optional): non-owner calling owner-only function should revert.

---

## `flow_02_deposit_and_vesting_checks.cairo`

**Purpose:** Owner deposits **1,000 EARN** for `USER1` via Manager; verify Vesting balances and releasable/locked state.

**Steps & assertions**

1. Ensure Manager has funds (transfer from OWNER if needed).  
2. Owner calls `manager.earn_deposit_to_vesting(USER1, ONE_THOUSAND)`.  
3. Assert `vesting.get_earn_balance(USER1) == ONE_THOUSAND`.  
4. Assert `vesting.get_stearn_balance(USER1) == ONE_THOUSAND` (if contract mints/binds stEARN).  
5. Call `vesting.calculate_releasable_amount(USER1) => (releasable, locked)`; assert `releasable + locked == ONE_THOUSAND`.  
6. If immediate releasable expected assert `releasable > 0`; otherwise advance time using cheat warp then assert `releasable > 0`.

---

## `flow_03_user1_stake_release_reshuffle.cairo`

**Purpose:** `USER1` stakes (category `'T'`, level 1), calls `release_vested_amount`, then `reshuffle`, then `force_release_vested_amount`; verify per-step reads and balances.

**Steps & assertions**

1. Read `staking.get_level_cost('T', 1)` and assert > 0.  
2. Approve `stEARN` (or required token) from `USER1` to Staking for level cost.  
3. `USER1` calls `staking.stake('T', level=1)`. Assert `staking.read(USER1)` shows expected level and metadata.  
4. `USER1` calls `vesting.release_vested_amount(USER1)`. Afterwards, call `calculate_releasable_amount(USER1)` and assert `releasable == 0` and `locked` updated.  
5. `USER1` calls `staking.reshuffle()`. Assert `staking.read(USER1)` updated according to reshuffle logic.  
6. Verify `vesting.get_earn_balance/get_stearn_balance(USER1)` reflect expected values after reshuffle.  
7. `USER1` calls `vesting.force_release_vested_amount(USER1)`. Assert vesting data updated and invariants hold.

---

## `flow_04_user2_stake_release_unstake.cairo`

**Purpose:** `USER2` follows the same flow but calls `unstake()` instead of `reshuffle()`; verify final balances and state.

**Steps & assertions**

1. Repeat deposit and vesting steps for `USER2`.  
2. Approve and stake level 1 for `USER2`.  
3. `USER2` calls `vesting.release_vested_amount(USER2)`.  
4. `USER2` calls `staking.unstake()`. Assert `staking.read(USER2)` is cleared / level 0.  
5. Verify EARN / stEARN balances for `USER2` updated appropriately and invariants preserved.

---

## `flow_05_user3_tip_and_extra_stakes.cairo`

**Purpose:** `USER3` stakes and after vesting-release gives a tip of **100 EARN** to `USER1`; verify before/after releasable and balances; then perform another stake in a different category and include negative/error checks.

**Steps & assertions**

1. Perform deposit and vesting for `USER3` and stake to reach a releasable state.  
2. Record pre-tip: `vesting.calculate_releasable_amount(USER1)` and `get_balance(EARN, USER1)`.  
3. `USER3` calls `give_tip(USER1, TIP_AMOUNT)`. Assert the call succeeds.  
4. Assert `get_balance(EARN, USER1) == pre_tip_balance + TIP_AMOUNT`.  
5. Call `calculate_releasable_amount(USER1)` before and after tip. Assert expected business-logic change (or explicitly assert no change if tips don't affect vesting).  
6. `USER3` attempts invalid stake (e.g., invalid level or insufficient approval) and the test expects revert; then approve correct amount and stake in a different category/level.  
7. Assert `staking.read(USER3)` shows the new level/category after successful stake.

---

# Edge cases & negative tests (recommended)

- Non-owner attempting owner-only functions must revert.  
- Staking without sufficient allowance must revert.  
- Manager attempting deposit with insufficient balance must revert.  
- Tipping with insufficient balance must revert.  
- Repeated `unstake` or `reshuffle` calls must preserve invariants and should either revert or be no-op depending on contract design.

---

# Running notes (snforge)

1. Place test files in your project's `tests/` directory.  
2. Use the same helper names as your existing tests (`setup_*`, `transfer_token`, `approve_token`, `get_balance`).  
3. Run tests with your usual snforge command, e.g. `snforge test` or the equivalent test runner in your environment.  
4. For time-dependent vesting, use snforge time-warp / cheat helpers to advance block timestamp when needed to avoid flaky `releasable > 0` checks.

---
