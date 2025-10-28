use openzeppelin::access::ownable::interface::{IOwnableDispatcher, IOwnableDispatcherTrait};
use snforge_std::{
    start_cheat_block_timestamp_global, start_cheat_caller_address,
    stop_cheat_block_timestamp_global, stop_cheat_caller_address,
};
use starknet::ContractAddress;
use crate::utils::{
    OWNER, THOUSAND_TOKENS, USER1, USER2, ZERO_ADDRESS, setup_earn_token, setup_earnstark_manager,
    setup_staking, setup_stearn_token, setup_vesting, transfer_token,
};

#[starknet::interface]
trait IEarnSTARKManager<TContractState> {
    fn set_vesting_address(ref self: TContractState, vesting: ContractAddress);
}

#[starknet::interface]
trait IStEarnToken<TContractState> {
    fn set_vesting_address(ref self: TContractState, vesting: ContractAddress);
    fn set_staking_contract_address(ref self: TContractState, staking_contract: ContractAddress);
}

#[starknet::interface]
trait IEarnscapeStaking<TContractState> {
    fn set_vesting_contract(ref self: TContractState, contract: ContractAddress);
}

#[starknet::interface]
trait IVesting<TContractState> {
    // Admin functions
    fn update_earn_stark_manager(ref self: TContractState, earn_stark_manager: ContractAddress);
    fn update_staking_contract(ref self: TContractState, staking_contract: ContractAddress);
    fn set_fee_recipient(ref self: TContractState, recipient: ContractAddress);
    fn set_platform_fee_pct(ref self: TContractState, pct: u64);
    fn update_merchandise_admin_wallet(ref self: TContractState, merch_wallet: ContractAddress);
    fn update_earn_stark_manager_address(ref self: TContractState, contract_addr: ContractAddress);

    // Balance management
    fn get_earn_balance(self: @TContractState, beneficiary: ContractAddress) -> u256;
    fn update_earn_balance(ref self: TContractState, user: ContractAddress, amount: u256);
    fn get_stearn_balance(self: @TContractState, beneficiary: ContractAddress) -> u256;
    fn update_stearn_balance(ref self: TContractState, user: ContractAddress, amount: u256);
    fn st_earn_transfer(ref self: TContractState, sender: ContractAddress, amount: u256);

    // Vesting operations
    fn deposit_earn(ref self: TContractState, beneficiary: ContractAddress, amount: u256);
    fn calculate_releasable_amount(
        self: @TContractState, beneficiary: ContractAddress,
    ) -> (u256, u256);
    fn release_vested_amount(ref self: TContractState, beneficiary: ContractAddress);
    fn force_release_vested_amount(ref self: TContractState, beneficiary: ContractAddress);
    fn release_vested_admins(ref self: TContractState);

    // Vesting queries
    fn get_user_vesting_count(self: @TContractState, beneficiary: ContractAddress) -> u32;
    fn get_vesting_schedule(
        self: @TContractState, beneficiary: ContractAddress, index: u32,
    ) -> (ContractAddress, u64, u64, u64, u64, u256, u256);
    fn get_user_vesting_details(
        self: @TContractState, beneficiary: ContractAddress,
    ) -> Array<(u32, ContractAddress, u64, u64, u64, u64, u256, u256)>;
    fn preview_vesting_params(self: @TContractState, beneficiary: ContractAddress) -> (u64, u64);

    // Configuration getters
    fn get_fee_recipient(self: @TContractState) -> ContractAddress;
    fn get_platform_fee_pct(self: @TContractState) -> u64;
    fn get_merchandise_admin_wallet(self: @TContractState) -> ContractAddress;
    fn get_earn_stark_manager(self: @TContractState) -> ContractAddress;
    fn get_default_vesting_time(self: @TContractState) -> u64;
    fn get_total_amount_vested(self: @TContractState) -> u256;

    // Tipping
    fn give_a_tip(ref self: TContractState, receiver: ContractAddress, tip_amount: u256);
}

// ============================================================================
// Constructor Tests
// ============================================================================

#[test]
fn test_constructor() {
    let (earn_token, _) = setup_earn_token();
    let stearn_token = setup_stearn_token();
    let manager = setup_earnstark_manager(earn_token);
    let staking = setup_staking(earn_token, stearn_token, manager);
    let vesting_address = setup_vesting(earn_token, stearn_token, manager, staking);
    let vesting = IVestingDispatcher { contract_address: vesting_address };

    // Check owner
    let ownable = IOwnableDispatcher { contract_address: vesting_address };
    assert(ownable.owner() == OWNER(), 'Wrong owner');

    // Check addresses
    assert(vesting.get_earn_stark_manager() == manager, 'Wrong manager');

    // Check initial configuration
    assert(vesting.get_default_vesting_time() == 2880 * 60, 'Wrong default vesting');
    assert(vesting.get_platform_fee_pct() == 40, 'Wrong platform fee');
    assert(vesting.get_total_amount_vested() == 0, 'Initial vested not zero');

    // Check fee recipient is owner
    assert(vesting.get_fee_recipient() == OWNER(), 'Wrong fee recipient');
}

// ============================================================================
// Deposit EARN Tests
// ============================================================================

#[test]
fn test_deposit_earn() {
    let (earn_token, _token) = setup_earn_token();
    let stearn_token = setup_stearn_token();
    let manager = setup_earnstark_manager(earn_token);
    let staking = setup_staking(earn_token, stearn_token, manager);
    let vesting_address = setup_vesting(earn_token, stearn_token, manager, staking);
    let vesting = IVestingDispatcher { contract_address: vesting_address };

    // Configure stearn token
    let stearn_dispatcher = IStEarnTokenDispatcher { contract_address: stearn_token };
    start_cheat_caller_address(stearn_token, OWNER());
    stearn_dispatcher.set_vesting_address(vesting_address);
    stearn_dispatcher.set_staking_contract_address(staking);
    stop_cheat_caller_address(stearn_token);

    // Configure staking contract
    let staking_dispatcher = IEarnscapeStakingDispatcher { contract_address: staking };
    start_cheat_caller_address(staking, OWNER());
    staking_dispatcher.set_vesting_contract(vesting_address);
    stop_cheat_caller_address(staking);

    // Setup: Set vesting address in manager and transfer tokens
    let manager_dispatcher = IEarnSTARKManagerDispatcher { contract_address: manager };
    start_cheat_caller_address(manager, OWNER());
    manager_dispatcher.set_vesting_address(vesting_address);
    stop_cheat_caller_address(manager);

    transfer_token(earn_token, OWNER(), vesting_address, THOUSAND_TOKENS);

    // Deposit from manager
    start_cheat_caller_address(vesting_address, manager);
    vesting.deposit_earn(USER1(), THOUSAND_TOKENS);
    stop_cheat_caller_address(vesting_address);

    // Check balances
    assert(vesting.get_earn_balance(USER1()) == THOUSAND_TOKENS, 'Wrong earn balance');
    assert(vesting.get_stearn_balance(USER1()) == THOUSAND_TOKENS, 'Wrong stearn balance');

    // Check vesting schedule created
    assert(vesting.get_user_vesting_count(USER1()) == 1, 'Wrong vesting count');
}

#[test]
#[should_panic(expected: ('Only earnStarkManager',))]
fn test_deposit_earn_not_manager() {
    let (earn_token, _) = setup_earn_token();
    let stearn_token = setup_stearn_token();
    let manager = setup_earnstark_manager(earn_token);
    let staking = setup_staking(earn_token, stearn_token, manager);
    let vesting_address = setup_vesting(earn_token, stearn_token, manager, staking);
    let vesting = IVestingDispatcher { contract_address: vesting_address };

    transfer_token(earn_token, OWNER(), vesting_address, THOUSAND_TOKENS);

    // USER1 tries to deposit (not manager)
    start_cheat_caller_address(vesting_address, USER1());
    vesting.deposit_earn(USER2(), THOUSAND_TOKENS);
    stop_cheat_caller_address(vesting_address);
}

#[test]
#[should_panic(expected: ('Amount must be > 0',))]
fn test_deposit_earn_zero_amount() {
    let (earn_token, _) = setup_earn_token();
    let stearn_token = setup_stearn_token();
    let manager = setup_earnstark_manager(earn_token);
    let staking = setup_staking(earn_token, stearn_token, manager);
    let vesting_address = setup_vesting(earn_token, stearn_token, manager, staking);
    let vesting = IVestingDispatcher { contract_address: vesting_address };

    let manager_dispatcher = IEarnSTARKManagerDispatcher { contract_address: manager };
    start_cheat_caller_address(manager, OWNER());
    manager_dispatcher.set_vesting_address(vesting_address);
    stop_cheat_caller_address(manager);

    start_cheat_caller_address(vesting_address, manager);
    vesting.deposit_earn(USER1(), 0);
    stop_cheat_caller_address(vesting_address);
}

// ============================================================================
// Calculate Releasable Tests
// ============================================================================

#[test]
fn test_calculate_releasable_amount() {
    let (earn_token, _) = setup_earn_token();
    let stearn_token = setup_stearn_token();
    let manager = setup_earnstark_manager(earn_token);
    let staking = setup_staking(earn_token, stearn_token, manager);
    let vesting_address = setup_vesting(earn_token, stearn_token, manager, staking);
    let vesting = IVestingDispatcher { contract_address: vesting_address };

    // Configure stearn token and staking
    let stearn_dispatcher = IStEarnTokenDispatcher { contract_address: stearn_token };
    start_cheat_caller_address(stearn_token, OWNER());
    stearn_dispatcher.set_vesting_address(vesting_address);
    stearn_dispatcher.set_staking_contract_address(staking);
    stop_cheat_caller_address(stearn_token);

    let staking_dispatcher = IEarnscapeStakingDispatcher { contract_address: staking };
    start_cheat_caller_address(staking, OWNER());
    staking_dispatcher.set_vesting_contract(vesting_address);
    stop_cheat_caller_address(staking);

    // Setup and deposit
    let manager_dispatcher = IEarnSTARKManagerDispatcher { contract_address: manager };
    start_cheat_caller_address(manager, OWNER());
    manager_dispatcher.set_vesting_address(vesting_address);
    stop_cheat_caller_address(manager);

    transfer_token(earn_token, OWNER(), vesting_address, THOUSAND_TOKENS);

    start_cheat_caller_address(vesting_address, manager);
    vesting.deposit_earn(USER1(), THOUSAND_TOKENS);
    stop_cheat_caller_address(vesting_address);

    // Initially, some amount should be locked
    let (releasable, locked) = vesting.calculate_releasable_amount(USER1());
    assert(releasable + locked == THOUSAND_TOKENS, 'Total should match');
}

// ============================================================================
// Balance Management Tests
// ============================================================================

#[test]
fn test_get_earn_balance() {
    let (earn_token, _) = setup_earn_token();
    let stearn_token = setup_stearn_token();
    let manager = setup_earnstark_manager(earn_token);
    let staking = setup_staking(earn_token, stearn_token, manager);
    let vesting_address = setup_vesting(earn_token, stearn_token, manager, staking);
    let vesting = IVestingDispatcher { contract_address: vesting_address };

    // Configure stearn token and staking
    let stearn_dispatcher = IStEarnTokenDispatcher { contract_address: stearn_token };
    start_cheat_caller_address(stearn_token, OWNER());
    stearn_dispatcher.set_vesting_address(vesting_address);
    stearn_dispatcher.set_staking_contract_address(staking);
    stop_cheat_caller_address(stearn_token);

    let staking_dispatcher = IEarnscapeStakingDispatcher { contract_address: staking };
    start_cheat_caller_address(staking, OWNER());
    staking_dispatcher.set_vesting_contract(vesting_address);
    stop_cheat_caller_address(staking);

    // Initially zero
    assert(vesting.get_earn_balance(USER1()) == 0, 'Should be zero');

    // After deposit
    let manager_dispatcher = IEarnSTARKManagerDispatcher { contract_address: manager };
    start_cheat_caller_address(manager, OWNER());
    manager_dispatcher.set_vesting_address(vesting_address);
    stop_cheat_caller_address(manager);

    transfer_token(earn_token, OWNER(), vesting_address, THOUSAND_TOKENS);

    start_cheat_caller_address(vesting_address, manager);
    vesting.deposit_earn(USER1(), THOUSAND_TOKENS);
    stop_cheat_caller_address(vesting_address);

    assert(vesting.get_earn_balance(USER1()) == THOUSAND_TOKENS, 'Wrong balance');
}

#[test]
fn test_get_stearn_balance() {
    let (earn_token, _) = setup_earn_token();
    let stearn_token = setup_stearn_token();
    let manager = setup_earnstark_manager(earn_token);
    let staking = setup_staking(earn_token, stearn_token, manager);
    let vesting_address = setup_vesting(earn_token, stearn_token, manager, staking);
    let vesting = IVestingDispatcher { contract_address: vesting_address };

    // Configure stearn token and staking
    let stearn_dispatcher = IStEarnTokenDispatcher { contract_address: stearn_token };
    start_cheat_caller_address(stearn_token, OWNER());
    stearn_dispatcher.set_vesting_address(vesting_address);
    stearn_dispatcher.set_staking_contract_address(staking);
    stop_cheat_caller_address(stearn_token);

    let staking_dispatcher = IEarnscapeStakingDispatcher { contract_address: staking };
    start_cheat_caller_address(staking, OWNER());
    staking_dispatcher.set_vesting_contract(vesting_address);
    stop_cheat_caller_address(staking);

    // Initially zero
    assert(vesting.get_stearn_balance(USER1()) == 0, 'Should be zero');

    // After deposit, stearn balance should match
    let manager_dispatcher = IEarnSTARKManagerDispatcher { contract_address: manager };
    start_cheat_caller_address(manager, OWNER());
    manager_dispatcher.set_vesting_address(vesting_address);
    stop_cheat_caller_address(manager);

    transfer_token(earn_token, OWNER(), vesting_address, THOUSAND_TOKENS);

    start_cheat_caller_address(vesting_address, manager);
    vesting.deposit_earn(USER1(), THOUSAND_TOKENS);
    stop_cheat_caller_address(vesting_address);

    assert(vesting.get_stearn_balance(USER1()) == THOUSAND_TOKENS, 'Wrong stearn balance');
}

// ============================================================================
// Vesting Schedule Tests
// ============================================================================

#[test]
fn test_get_user_vesting_count() {
    let (earn_token, _) = setup_earn_token();
    let stearn_token = setup_stearn_token();
    let manager = setup_earnstark_manager(earn_token);
    let staking = setup_staking(earn_token, stearn_token, manager);
    let vesting_address = setup_vesting(earn_token, stearn_token, manager, staking);
    let vesting = IVestingDispatcher { contract_address: vesting_address };

    // Configure stearn token and staking
    let stearn_dispatcher = IStEarnTokenDispatcher { contract_address: stearn_token };
    start_cheat_caller_address(stearn_token, OWNER());
    stearn_dispatcher.set_vesting_address(vesting_address);
    stearn_dispatcher.set_staking_contract_address(staking);
    stop_cheat_caller_address(stearn_token);

    let staking_dispatcher = IEarnscapeStakingDispatcher { contract_address: staking };
    start_cheat_caller_address(staking, OWNER());
    staking_dispatcher.set_vesting_contract(vesting_address);
    stop_cheat_caller_address(staking);

    // Initially zero
    assert(vesting.get_user_vesting_count(USER1()) == 0, 'Should be zero');

    // After deposit
    let manager_dispatcher = IEarnSTARKManagerDispatcher { contract_address: manager };
    start_cheat_caller_address(manager, OWNER());
    manager_dispatcher.set_vesting_address(vesting_address);
    stop_cheat_caller_address(manager);

    transfer_token(earn_token, OWNER(), vesting_address, THOUSAND_TOKENS);

    start_cheat_caller_address(vesting_address, manager);
    vesting.deposit_earn(USER1(), THOUSAND_TOKENS);
    stop_cheat_caller_address(vesting_address);

    assert(vesting.get_user_vesting_count(USER1()) == 1, 'Should be one');
}

#[test]
fn test_get_vesting_schedule() {
    let (earn_token, _) = setup_earn_token();
    let stearn_token = setup_stearn_token();
    let manager = setup_earnstark_manager(earn_token);
    let staking = setup_staking(earn_token, stearn_token, manager);
    let vesting_address = setup_vesting(earn_token, stearn_token, manager, staking);
    let vesting = IVestingDispatcher { contract_address: vesting_address };

    // Configure stearn token and staking
    let stearn_dispatcher = IStEarnTokenDispatcher { contract_address: stearn_token };
    start_cheat_caller_address(stearn_token, OWNER());
    stearn_dispatcher.set_vesting_address(vesting_address);
    stearn_dispatcher.set_staking_contract_address(staking);
    stop_cheat_caller_address(stearn_token);

    let staking_dispatcher = IEarnscapeStakingDispatcher { contract_address: staking };
    start_cheat_caller_address(staking, OWNER());
    staking_dispatcher.set_vesting_contract(vesting_address);
    stop_cheat_caller_address(staking);

    let manager_dispatcher = IEarnSTARKManagerDispatcher { contract_address: manager };
    start_cheat_caller_address(manager, OWNER());
    manager_dispatcher.set_vesting_address(vesting_address);
    stop_cheat_caller_address(manager);

    transfer_token(earn_token, OWNER(), vesting_address, THOUSAND_TOKENS);

    start_cheat_caller_address(vesting_address, manager);
    vesting.deposit_earn(USER1(), THOUSAND_TOKENS);
    stop_cheat_caller_address(vesting_address);

    // Get schedule
    let (beneficiary, _cliff, _start, duration, _slice_period, amount_total, released) = vesting
        .get_vesting_schedule(USER1(), 0);

    assert(beneficiary == USER1(), 'Wrong beneficiary');
    assert(amount_total == THOUSAND_TOKENS, 'Wrong amount');
    assert(released == 0, 'Should not be released');
    assert(duration > 0, 'Duration should be set');
}

// ============================================================================
// Admin Functions Tests
// ============================================================================

#[test]
fn test_set_fee_recipient() {
    let (earn_token, _) = setup_earn_token();
    let stearn_token = setup_stearn_token();
    let manager = setup_earnstark_manager(earn_token);
    let staking = setup_staking(earn_token, stearn_token, manager);
    let vesting_address = setup_vesting(earn_token, stearn_token, manager, staking);
    let vesting = IVestingDispatcher { contract_address: vesting_address };

    start_cheat_caller_address(vesting_address, OWNER());
    vesting.set_fee_recipient(USER1());
    stop_cheat_caller_address(vesting_address);

    assert(vesting.get_fee_recipient() == USER1(), 'Wrong fee recipient');
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_set_fee_recipient_not_owner() {
    let (earn_token, _) = setup_earn_token();
    let stearn_token = setup_stearn_token();
    let manager = setup_earnstark_manager(earn_token);
    let staking = setup_staking(earn_token, stearn_token, manager);
    let vesting_address = setup_vesting(earn_token, stearn_token, manager, staking);
    let vesting = IVestingDispatcher { contract_address: vesting_address };

    start_cheat_caller_address(vesting_address, USER1());
    vesting.set_fee_recipient(USER2());
    stop_cheat_caller_address(vesting_address);
}

#[test]
#[should_panic(expected: ('Zero address',))]
fn test_set_fee_recipient_zero_address() {
    let (earn_token, _) = setup_earn_token();
    let stearn_token = setup_stearn_token();
    let manager = setup_earnstark_manager(earn_token);
    let staking = setup_staking(earn_token, stearn_token, manager);
    let vesting_address = setup_vesting(earn_token, stearn_token, manager, staking);
    let vesting = IVestingDispatcher { contract_address: vesting_address };

    start_cheat_caller_address(vesting_address, OWNER());
    vesting.set_fee_recipient(ZERO_ADDRESS());
    stop_cheat_caller_address(vesting_address);
}

#[test]
fn test_set_platform_fee_pct() {
    let (earn_token, _) = setup_earn_token();
    let stearn_token = setup_stearn_token();
    let manager = setup_earnstark_manager(earn_token);
    let staking = setup_staking(earn_token, stearn_token, manager);
    let vesting_address = setup_vesting(earn_token, stearn_token, manager, staking);
    let vesting = IVestingDispatcher { contract_address: vesting_address };

    start_cheat_caller_address(vesting_address, OWNER());
    vesting.set_platform_fee_pct(50);
    stop_cheat_caller_address(vesting_address);

    assert(vesting.get_platform_fee_pct() == 50, 'Wrong platform fee');
}

#[test]
#[should_panic(expected: ('Pct>100',))]
fn test_set_platform_fee_pct_too_high() {
    let (earn_token, _) = setup_earn_token();
    let stearn_token = setup_stearn_token();
    let manager = setup_earnstark_manager(earn_token);
    let staking = setup_staking(earn_token, stearn_token, manager);
    let vesting_address = setup_vesting(earn_token, stearn_token, manager, staking);
    let vesting = IVestingDispatcher { contract_address: vesting_address };

    start_cheat_caller_address(vesting_address, OWNER());
    vesting.set_platform_fee_pct(101);
    stop_cheat_caller_address(vesting_address);
}

#[test]
fn test_update_merchandise_admin_wallet() {
    let (earn_token, _) = setup_earn_token();
    let stearn_token = setup_stearn_token();
    let manager = setup_earnstark_manager(earn_token);
    let staking = setup_staking(earn_token, stearn_token, manager);
    let vesting_address = setup_vesting(earn_token, stearn_token, manager, staking);
    let vesting = IVestingDispatcher { contract_address: vesting_address };

    start_cheat_caller_address(vesting_address, OWNER());
    vesting.update_merchandise_admin_wallet(USER1());
    stop_cheat_caller_address(vesting_address);

    assert(vesting.get_merchandise_admin_wallet() == USER1(), 'Wrong merch wallet');
}

#[test]
fn test_update_earn_stark_manager_address() {
    let (earn_token, _) = setup_earn_token();
    let stearn_token = setup_stearn_token();
    let manager = setup_earnstark_manager(earn_token);
    let staking = setup_staking(earn_token, stearn_token, manager);
    let vesting_address = setup_vesting(earn_token, stearn_token, manager, staking);
    let vesting = IVestingDispatcher { contract_address: vesting_address };

    start_cheat_caller_address(vesting_address, OWNER());
    vesting.update_earn_stark_manager_address(USER1());
    stop_cheat_caller_address(vesting_address);

    assert(vesting.get_earn_stark_manager() == USER1(), 'Wrong manager');
}

#[test]
fn test_update_staking_contract() {
    let (earn_token, _) = setup_earn_token();
    let stearn_token = setup_stearn_token();
    let manager = setup_earnstark_manager(earn_token);
    let staking = setup_staking(earn_token, stearn_token, manager);
    let vesting_address = setup_vesting(earn_token, stearn_token, manager, staking);
    let vesting = IVestingDispatcher { contract_address: vesting_address };

    start_cheat_caller_address(vesting_address, OWNER());
    vesting.update_staking_contract(USER1());
    stop_cheat_caller_address(vesting_address);
}

// ============================================================================
// Preview Vesting Params Tests
// ============================================================================

#[test]
fn test_preview_vesting_params() {
    let (earn_token, _) = setup_earn_token();
    let stearn_token = setup_stearn_token();
    let manager = setup_earnstark_manager(earn_token);
    let staking = setup_staking(earn_token, stearn_token, manager);
    let vesting_address = setup_vesting(earn_token, stearn_token, manager, staking);
    let vesting = IVestingDispatcher { contract_address: vesting_address };

    // Configure staking contract so it can query user data
    let staking_dispatcher = IEarnscapeStakingDispatcher { contract_address: staking };
    start_cheat_caller_address(staking, OWNER());
    staking_dispatcher.set_vesting_contract(vesting_address);
    stop_cheat_caller_address(staking);

    // Set block timestamp to a non-zero value
    start_cheat_block_timestamp_global(1000);

    // Preview for user without staking (should return default)
    let (start, duration) = vesting.preview_vesting_params(USER1());
    assert(start == 1000, 'Start should match timestamp');
    assert(duration == 2880 * 60, 'Should be default duration');

    stop_cheat_block_timestamp_global();
}

#[test]
fn test_multiple_deposits() {
    let (earn_token, _) = setup_earn_token();
    let stearn_token = setup_stearn_token();
    let manager = setup_earnstark_manager(earn_token);
    let staking = setup_staking(earn_token, stearn_token, manager);
    let vesting_address = setup_vesting(earn_token, stearn_token, manager, staking);
    let vesting = IVestingDispatcher { contract_address: vesting_address };

    // Configure stearn token and staking
    let stearn_dispatcher = IStEarnTokenDispatcher { contract_address: stearn_token };
    start_cheat_caller_address(stearn_token, OWNER());
    stearn_dispatcher.set_vesting_address(vesting_address);
    stearn_dispatcher.set_staking_contract_address(staking);
    stop_cheat_caller_address(stearn_token);

    let staking_dispatcher = IEarnscapeStakingDispatcher { contract_address: staking };
    start_cheat_caller_address(staking, OWNER());
    staking_dispatcher.set_vesting_contract(vesting_address);
    stop_cheat_caller_address(staking);

    let manager_dispatcher = IEarnSTARKManagerDispatcher { contract_address: manager };
    start_cheat_caller_address(manager, OWNER());
    manager_dispatcher.set_vesting_address(vesting_address);
    stop_cheat_caller_address(manager);

    transfer_token(earn_token, OWNER(), vesting_address, THOUSAND_TOKENS * 3);

    // Multiple deposits
    start_cheat_caller_address(vesting_address, manager);
    vesting.deposit_earn(USER1(), THOUSAND_TOKENS);
    vesting.deposit_earn(USER1(), THOUSAND_TOKENS);
    vesting.deposit_earn(USER1(), THOUSAND_TOKENS);
    stop_cheat_caller_address(vesting_address);

    // Should have 3 vesting schedules
    assert(vesting.get_user_vesting_count(USER1()) == 3, 'Should have 3 schedules');
    assert(vesting.get_earn_balance(USER1()) == THOUSAND_TOKENS * 3, 'Wrong total balance');
}

// ============================================================================
// Ownership Tests
// ============================================================================

#[test]
fn test_transfer_ownership() {
    let (earn_token, _) = setup_earn_token();
    let stearn_token = setup_stearn_token();
    let manager = setup_earnstark_manager(earn_token);
    let staking = setup_staking(earn_token, stearn_token, manager);
    let vesting_address = setup_vesting(earn_token, stearn_token, manager, staking);
    let vesting = IVestingDispatcher { contract_address: vesting_address };
    let ownable = IOwnableDispatcher { contract_address: vesting_address };

    start_cheat_caller_address(vesting_address, OWNER());
    ownable.transfer_ownership(USER1());
    stop_cheat_caller_address(vesting_address);

    assert(ownable.owner() == USER1(), 'Ownership not transferred');

    // New owner can perform owner actions
    start_cheat_caller_address(vesting_address, USER1());
    vesting.set_platform_fee_pct(50);
    stop_cheat_caller_address(vesting_address);

    assert(vesting.get_platform_fee_pct() == 50, 'New owner cannot set fee');
}

