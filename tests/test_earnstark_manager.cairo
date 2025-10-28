use openzeppelin::access::ownable::interface::{IOwnableDispatcher, IOwnableDispatcherTrait};
use snforge_std::{start_cheat_caller_address, stop_cheat_caller_address};
use starknet::ContractAddress;
use crate::utils::{
    HUNDRED_TOKENS, OWNER, THOUSAND_TOKENS, USER1, USER2, ZERO_ADDRESS, get_balance,
    setup_earn_token, setup_earnstark_manager, transfer_token,
};

#[starknet::interface]
trait IEarnSTARKManager<TContractState> {
    fn transfer_earns(ref self: TContractState, to: ContractAddress, amount: u256);
    fn transfer_eth(ref self: TContractState, to: ContractAddress, amount: u256);
    fn vesting_deposit(ref self: TContractState, amount: u256);
    fn earn_deposit_to_vesting(ref self: TContractState, receiver: ContractAddress, amount: u256);
    fn get_earns_balance(self: @TContractState) -> u256;
    fn get_eth_balance(self: @TContractState) -> u256;
    fn set_vesting_contract(ref self: TContractState, vesting: ContractAddress);
    fn set_vesting_address(ref self: TContractState, vesting: ContractAddress);
    fn earns_token(self: @TContractState) -> ContractAddress;
    fn vesting_contract(self: @TContractState) -> ContractAddress;
    fn vesting(self: @TContractState) -> ContractAddress;
}

// ============================================================================
// Constructor Tests
// ============================================================================

#[test]
fn test_constructor() {
    let (earn_token, _) = setup_earn_token();
    let manager_address = setup_earnstark_manager(earn_token);
    let manager = IEarnSTARKManagerDispatcher { contract_address: manager_address };

    // Check owner
    let ownable = IOwnableDispatcher { contract_address: manager_address };
    assert(ownable.owner() == OWNER(), 'Wrong owner');

    // Check vesting is unset initially
    assert(manager.vesting().into() == 0, 'Vesting should be unset');

    // Check balances are zero initially
    assert(manager.get_earns_balance() == 0, 'EARNS balance should be 0');
}

// ============================================================================
// Set Vesting Address Tests
// ============================================================================

#[test]
fn test_set_vesting_address() {
    let (earn_token, _) = setup_earn_token();
    let manager_address = setup_earnstark_manager(earn_token);
    let manager = IEarnSTARKManagerDispatcher { contract_address: manager_address };

    start_cheat_caller_address(manager_address, OWNER());
    manager.set_vesting_address(USER1());
    stop_cheat_caller_address(manager_address);

    assert(manager.vesting() == USER1(), 'Wrong vesting address');
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_set_vesting_address_not_owner() {
    let (earn_token, _) = setup_earn_token();
    let manager_address = setup_earnstark_manager(earn_token);
    let manager = IEarnSTARKManagerDispatcher { contract_address: manager_address };

    start_cheat_caller_address(manager_address, USER1());
    manager.set_vesting_address(USER2());
    stop_cheat_caller_address(manager_address);
}

// ============================================================================
// Transfer EARNS Tests
// ============================================================================

#[test]
fn test_transfer_earns() {
    let (earn_token, _) = setup_earn_token();
    let manager_address = setup_earnstark_manager(earn_token);
    let manager = IEarnSTARKManagerDispatcher { contract_address: manager_address };

    // Transfer tokens to manager
    transfer_token(earn_token, OWNER(), manager_address, THOUSAND_TOKENS);

    let initial_balance = manager.get_earns_balance();
    assert(initial_balance == THOUSAND_TOKENS, 'Wrong initial balance');

    // Owner transfers from manager to USER1
    start_cheat_caller_address(manager_address, OWNER());
    manager.transfer_earns(USER1(), HUNDRED_TOKENS);
    stop_cheat_caller_address(manager_address);

    assert(get_balance(earn_token, USER1()) == HUNDRED_TOKENS, 'Wrong USER1 balance');
    assert(
        manager.get_earns_balance() == THOUSAND_TOKENS - HUNDRED_TOKENS, 'Wrong manager balance',
    );
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_transfer_earns_not_owner() {
    let (earn_token, _) = setup_earn_token();
    let manager_address = setup_earnstark_manager(earn_token);
    let manager = IEarnSTARKManagerDispatcher { contract_address: manager_address };

    transfer_token(earn_token, OWNER(), manager_address, THOUSAND_TOKENS);

    start_cheat_caller_address(manager_address, USER1());
    manager.transfer_earns(USER2(), HUNDRED_TOKENS);
    stop_cheat_caller_address(manager_address);
}

#[test]
#[should_panic(expected: ('Insufficient earns balance',))]
fn test_transfer_earns_insufficient_balance() {
    let (earn_token, _) = setup_earn_token();
    let manager_address = setup_earnstark_manager(earn_token);
    let manager = IEarnSTARKManagerDispatcher { contract_address: manager_address };

    start_cheat_caller_address(manager_address, OWNER());
    manager.transfer_earns(USER1(), HUNDRED_TOKENS);
    stop_cheat_caller_address(manager_address);
}

// ============================================================================
// Transfer ETH Tests (Note: These test the interface, actual ETH handling may differ)
// ============================================================================

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_transfer_eth_not_owner() {
    let (earn_token, _) = setup_earn_token();
    let manager_address = setup_earnstark_manager(earn_token);
    let manager = IEarnSTARKManagerDispatcher { contract_address: manager_address };

    start_cheat_caller_address(manager_address, USER1());
    manager.transfer_eth(USER2(), HUNDRED_TOKENS);
    stop_cheat_caller_address(manager_address);
}

// ============================================================================
// Get Balance Tests
// ============================================================================

#[test]
fn test_get_earns_balance() {
    let (earn_token, _) = setup_earn_token();
    let manager_address = setup_earnstark_manager(earn_token);
    let manager = IEarnSTARKManagerDispatcher { contract_address: manager_address };

    // Initial balance should be zero
    assert(manager.get_earns_balance() == 0, 'Initial balance not zero');

    // Transfer tokens to manager
    transfer_token(earn_token, OWNER(), manager_address, THOUSAND_TOKENS);

    // Check balance updated
    assert(manager.get_earns_balance() == THOUSAND_TOKENS, 'Balance not updated');
}

#[test]
fn test_get_eth_balance() {
    let (earn_token, _) = setup_earn_token();
    let manager_address = setup_earnstark_manager(earn_token);
    let manager = IEarnSTARKManagerDispatcher { contract_address: manager_address };

    // Can call get_eth_balance (will return 0 unless ETH is sent)
    let eth_balance = manager.get_eth_balance();
    assert(eth_balance == 0, 'Unexpected ETH balance');
}

// ============================================================================
// Earn Deposit to Vesting Tests
// ============================================================================

// Note: We can't fully test earn_deposit_to_vesting without deploying the vesting contract
// These are the basic access control tests
#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_earn_deposit_to_vesting_not_owner() {
    let (earn_token, _) = setup_earn_token();
    let manager_address = setup_earnstark_manager(earn_token);
    let manager = IEarnSTARKManagerDispatcher { contract_address: manager_address };

    // Set vesting address
    start_cheat_caller_address(manager_address, OWNER());
    manager.set_vesting_address(USER1());
    stop_cheat_caller_address(manager_address);

    // USER2 tries to deposit (not owner)
    start_cheat_caller_address(manager_address, USER2());
    manager.earn_deposit_to_vesting(USER1(), HUNDRED_TOKENS);
    stop_cheat_caller_address(manager_address);
}

#[test]
#[should_panic(expected: ('Insufficient earns balance',))]
fn test_earn_deposit_to_vesting_insufficient_balance() {
    let (earn_token, _) = setup_earn_token();
    let manager_address = setup_earnstark_manager(earn_token);
    let manager = IEarnSTARKManagerDispatcher { contract_address: manager_address };

    // Set vesting address
    start_cheat_caller_address(manager_address, OWNER());
    manager.set_vesting_address(USER1());
    stop_cheat_caller_address(manager_address);

    // Try to deposit without having tokens
    start_cheat_caller_address(manager_address, OWNER());
    manager.earn_deposit_to_vesting(USER2(), HUNDRED_TOKENS);
    stop_cheat_caller_address(manager_address);
}

#[test]
fn test_multiple_transfers() {
    let (earn_token, _) = setup_earn_token();
    let manager_address = setup_earnstark_manager(earn_token);
    let manager = IEarnSTARKManagerDispatcher { contract_address: manager_address };

    // Transfer tokens to manager
    transfer_token(earn_token, OWNER(), manager_address, THOUSAND_TOKENS);

    // Multiple transfers
    start_cheat_caller_address(manager_address, OWNER());
    manager.transfer_earns(USER1(), HUNDRED_TOKENS);
    manager.transfer_earns(USER2(), HUNDRED_TOKENS);
    stop_cheat_caller_address(manager_address);

    assert(get_balance(earn_token, USER1()) == HUNDRED_TOKENS, 'Wrong USER1 balance');
    assert(get_balance(earn_token, USER2()) == HUNDRED_TOKENS, 'Wrong USER2 balance');
    assert(
        manager.get_earns_balance() == THOUSAND_TOKENS - (2 * HUNDRED_TOKENS),
        'Wrong manager balance',
    );
}

#[test]
fn test_update_vesting_address() {
    let (earn_token, _) = setup_earn_token();
    let manager_address = setup_earnstark_manager(earn_token);
    let manager = IEarnSTARKManagerDispatcher { contract_address: manager_address };

    // Set initial vesting address
    start_cheat_caller_address(manager_address, OWNER());
    manager.set_vesting_address(USER1());
    stop_cheat_caller_address(manager_address);

    assert(manager.vesting() == USER1(), 'Wrong initial vesting');

    // Update vesting address
    start_cheat_caller_address(manager_address, OWNER());
    manager.set_vesting_address(USER2());
    stop_cheat_caller_address(manager_address);

    assert(manager.vesting() == USER2(), 'Wrong updated vesting');
}

#[test]
fn test_receive_and_transfer_cycle() {
    let (earn_token, _) = setup_earn_token();
    let manager_address = setup_earnstark_manager(earn_token);
    let manager = IEarnSTARKManagerDispatcher { contract_address: manager_address };

    // Initial state
    assert(manager.get_earns_balance() == 0, 'Should start with 0');

    // Receive tokens
    transfer_token(earn_token, OWNER(), manager_address, THOUSAND_TOKENS);
    assert(manager.get_earns_balance() == THOUSAND_TOKENS, 'Wrong after receive');

    // Transfer some out
    start_cheat_caller_address(manager_address, OWNER());
    manager.transfer_earns(USER1(), HUNDRED_TOKENS);
    stop_cheat_caller_address(manager_address);

    assert(manager.get_earns_balance() == THOUSAND_TOKENS - HUNDRED_TOKENS, 'Wrong after transfer');

    // Receive more
    transfer_token(earn_token, OWNER(), manager_address, HUNDRED_TOKENS);
    assert(manager.get_earns_balance() == THOUSAND_TOKENS, 'Wrong after second receive');
}

#[test]
fn test_transfer_all_balance() {
    let (earn_token, _) = setup_earn_token();
    let manager_address = setup_earnstark_manager(earn_token);
    let manager = IEarnSTARKManagerDispatcher { contract_address: manager_address };

    transfer_token(earn_token, OWNER(), manager_address, THOUSAND_TOKENS);

    // Transfer entire balance
    start_cheat_caller_address(manager_address, OWNER());
    manager.transfer_earns(USER1(), THOUSAND_TOKENS);
    stop_cheat_caller_address(manager_address);

    assert(manager.get_earns_balance() == 0, 'Manager should be empty');
    assert(get_balance(earn_token, USER1()) == THOUSAND_TOKENS, 'USER1 should have all');
}

// ============================================================================
// Ownership Tests
// ============================================================================

#[test]
fn test_transfer_ownership() {
    let (earn_token, _) = setup_earn_token();
    let manager_address = setup_earnstark_manager(earn_token);
    let manager = IEarnSTARKManagerDispatcher { contract_address: manager_address };
    let ownable = IOwnableDispatcher { contract_address: manager_address };

    start_cheat_caller_address(manager_address, OWNER());
    ownable.transfer_ownership(USER1());
    stop_cheat_caller_address(manager_address);

    assert(ownable.owner() == USER1(), 'Ownership not transferred');

    // New owner can perform owner actions
    transfer_token(earn_token, OWNER(), manager_address, THOUSAND_TOKENS);

    start_cheat_caller_address(manager_address, USER1());
    manager.transfer_earns(USER2(), HUNDRED_TOKENS);
    stop_cheat_caller_address(manager_address);

    assert(get_balance(earn_token, USER2()) == HUNDRED_TOKENS, 'New owner cannot transfer');
}

#[test]
fn test_new_owner_can_set_vesting() {
    let (earn_token, _) = setup_earn_token();
    let manager_address = setup_earnstark_manager(earn_token);
    let manager = IEarnSTARKManagerDispatcher { contract_address: manager_address };
    let ownable = IOwnableDispatcher { contract_address: manager_address };

    // Transfer ownership
    start_cheat_caller_address(manager_address, OWNER());
    ownable.transfer_ownership(USER1());
    stop_cheat_caller_address(manager_address);

    // New owner can set vesting
    start_cheat_caller_address(manager_address, USER1());
    manager.set_vesting_address(USER2());
    stop_cheat_caller_address(manager_address);

    assert(manager.vesting() == USER2(), 'New owner cannot set vesting');
}

// ============================================================================
// Edge Cases
// ============================================================================

#[test]
fn test_transfer_zero_amount() {
    let (earn_token, _) = setup_earn_token();
    let manager_address = setup_earnstark_manager(earn_token);
    let manager = IEarnSTARKManagerDispatcher { contract_address: manager_address };

    transfer_token(earn_token, OWNER(), manager_address, THOUSAND_TOKENS);

    // Transfer zero amount (should succeed)
    start_cheat_caller_address(manager_address, OWNER());
    manager.transfer_earns(USER1(), 0);
    stop_cheat_caller_address(manager_address);

    assert(get_balance(earn_token, USER1()) == 0, 'USER1 should have 0');
    assert(manager.get_earns_balance() == THOUSAND_TOKENS, 'Manager balance unchanged');
}

#[test]
fn test_set_vesting_to_zero_address() {
    let (earn_token, _) = setup_earn_token();
    let manager_address = setup_earnstark_manager(earn_token);
    let manager = IEarnSTARKManagerDispatcher { contract_address: manager_address };

    // Can set vesting to zero address (to unset it)
    start_cheat_caller_address(manager_address, OWNER());
    manager.set_vesting_address(ZERO_ADDRESS());
    stop_cheat_caller_address(manager_address);

    assert(manager.vesting() == ZERO_ADDRESS(), 'Should allow zero address');
}

#[test]
fn test_sequential_vesting_updates() {
    let (earn_token, _) = setup_earn_token();
    let manager_address = setup_earnstark_manager(earn_token);
    let manager = IEarnSTARKManagerDispatcher { contract_address: manager_address };

    // Set vesting multiple times
    start_cheat_caller_address(manager_address, OWNER());
    manager.set_vesting_address(USER1());
    assert(manager.vesting() == USER1(), 'First update failed');

    manager.set_vesting_address(USER2());
    assert(manager.vesting() == USER2(), 'Second update failed');

    manager.set_vesting_address(ZERO_ADDRESS());
    assert(manager.vesting() == ZERO_ADDRESS(), 'Third update failed');
    stop_cheat_caller_address(manager_address);
}

