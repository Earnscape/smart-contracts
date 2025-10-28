use openzeppelin::access::ownable::interface::{IOwnableDispatcher, IOwnableDispatcherTrait};
use snforge_std::{start_cheat_caller_address, stop_cheat_caller_address};
use starknet::ContractAddress;
use crate::utils::{
    HUNDRED_TOKENS, ONE_DAY, OWNER, THOUSAND_TOKENS, TREASURY, USER1, USER2, get_balance,
    setup_earn_token, setup_escrow, transfer_token,
};

#[starknet::interface]
trait IEscrow<TContractState> {
    fn transfer_to(ref self: TContractState, to: ContractAddress, amount: u256);
    fn transfer_all_to_treasury(ref self: TContractState);
    fn transfer_all(ref self: TContractState);
    fn withdraw_to_contract4(ref self: TContractState, amount: u256);
    fn set_contract4(ref self: TContractState, contract_address: ContractAddress);
    fn get_earns_balance(self: @TContractState) -> u256;
    fn earns_token(self: @TContractState) -> ContractAddress;
    fn treasury(self: @TContractState) -> ContractAddress;
    fn earnscape_treasury(self: @TContractState) -> ContractAddress;
    fn contract4(self: @TContractState) -> ContractAddress;
    fn get_deployment_time(self: @TContractState) -> u64;
    fn get_closing_time(self: @TContractState) -> u64;
}

// ============================================================================
// Constructor Tests
// ============================================================================

#[test]
fn test_constructor() {
    let (earn_token, _) = setup_earn_token();
    let escrow_address = setup_escrow(earn_token, TREASURY());
    let escrow = IEscrowDispatcher { contract_address: escrow_address };

    // Check addresses are set correctly
    assert(escrow.earns_token() == earn_token, 'Wrong token address');
    assert(escrow.earnscape_treasury() == TREASURY(), 'Wrong treasury address');

    // Check deployment time is set
    let deployment_time = escrow.get_deployment_time();
    assert(deployment_time >= 0, 'Deployment time invalid');

    // Check closing time (should be deployment_time + 1 day)
    let closing_time = escrow.get_closing_time();
    assert(closing_time == deployment_time + ONE_DAY, 'Wrong closing time');

    // Contract4 should be unset initially
    assert(escrow.contract4().into() == 0, 'Contract4 should be unset');
}

// ============================================================================
// Set Contract4 Tests
// ============================================================================

#[test]
fn test_set_contract4() {
    let (earn_token, _) = setup_earn_token();
    let escrow_address = setup_escrow(earn_token, TREASURY());
    let escrow = IEscrowDispatcher { contract_address: escrow_address };

    start_cheat_caller_address(escrow_address, OWNER());
    escrow.set_contract4(USER1());
    stop_cheat_caller_address(escrow_address);

    assert(escrow.contract4() == USER1(), 'Wrong contract4 address');
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_set_contract4_not_owner() {
    let (earn_token, _) = setup_earn_token();
    let escrow_address = setup_escrow(earn_token, TREASURY());
    let escrow = IEscrowDispatcher { contract_address: escrow_address };

    start_cheat_caller_address(escrow_address, USER1());
    escrow.set_contract4(USER2());
    stop_cheat_caller_address(escrow_address);
}

// ============================================================================
// Transfer_to Tests
// ============================================================================

#[test]
fn test_transfer_to() {
    let (earn_token, _token) = setup_earn_token();
    let escrow_address = setup_escrow(earn_token, TREASURY());
    let escrow = IEscrowDispatcher { contract_address: escrow_address };

    // Transfer tokens to escrow first
    transfer_token(earn_token, OWNER(), escrow_address, THOUSAND_TOKENS);

    let initial_balance = get_balance(earn_token, escrow_address);
    assert(initial_balance == THOUSAND_TOKENS, 'Wrong escrow balance');

    // Owner transfers from escrow to USER1
    start_cheat_caller_address(escrow_address, OWNER());
    escrow.transfer_to(USER1(), HUNDRED_TOKENS);
    stop_cheat_caller_address(escrow_address);

    assert(get_balance(earn_token, USER1()) == HUNDRED_TOKENS, 'Wrong USER1 balance');
    assert(
        get_balance(earn_token, escrow_address) == THOUSAND_TOKENS - HUNDRED_TOKENS,
        'Wrong escrow balance after',
    );
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_transfer_to_not_owner() {
    let (earn_token, _) = setup_earn_token();
    let escrow_address = setup_escrow(earn_token, TREASURY());
    let escrow = IEscrowDispatcher { contract_address: escrow_address };

    // Transfer tokens to escrow
    transfer_token(earn_token, OWNER(), escrow_address, THOUSAND_TOKENS);

    // USER1 tries to transfer
    start_cheat_caller_address(escrow_address, USER1());
    escrow.transfer_to(USER2(), HUNDRED_TOKENS);
    stop_cheat_caller_address(escrow_address);
}

#[test]
#[should_panic(expected: ('Insufficient balance',))]
fn test_transfer_to_insufficient_balance() {
    let (earn_token, _) = setup_earn_token();
    let escrow_address = setup_escrow(earn_token, TREASURY());
    let escrow = IEscrowDispatcher { contract_address: escrow_address };

    // Try to transfer without having tokens
    start_cheat_caller_address(escrow_address, OWNER());
    escrow.transfer_to(USER1(), HUNDRED_TOKENS);
    stop_cheat_caller_address(escrow_address);
}

// ============================================================================
// Transfer_from Tests
// ============================================================================

// Note: test_transfer_from removed - Escrow doesn't have transfer_from method

// Note: test_transfer_from_not_owner removed - Escrow doesn't have transfer_from method

// Note: test_transfer_from_insufficient_allowance removed - Escrow doesn't have transfer_from
// method

// ============================================================================
// Transfer_all Tests
// ============================================================================

#[test]
fn test_transfer_all() {
    let (earn_token, _) = setup_earn_token();
    let escrow_address = setup_escrow(earn_token, TREASURY());
    let escrow = IEscrowDispatcher { contract_address: escrow_address };

    // Transfer tokens to escrow
    transfer_token(earn_token, OWNER(), escrow_address, THOUSAND_TOKENS);

    let initial_treasury_balance = get_balance(earn_token, TREASURY());

    // Transfer all to treasury
    start_cheat_caller_address(escrow_address, OWNER());
    escrow.transfer_all();
    stop_cheat_caller_address(escrow_address);

    assert(get_balance(earn_token, escrow_address) == 0, 'Escrow should be empty');
    assert(
        get_balance(earn_token, TREASURY()) == initial_treasury_balance + THOUSAND_TOKENS,
        'Wrong treasury balance',
    );
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_transfer_all_not_owner() {
    let (earn_token, _) = setup_earn_token();
    let escrow_address = setup_escrow(earn_token, TREASURY());
    let escrow = IEscrowDispatcher { contract_address: escrow_address };

    transfer_token(earn_token, OWNER(), escrow_address, THOUSAND_TOKENS);

    start_cheat_caller_address(escrow_address, USER1());
    escrow.transfer_all();
    stop_cheat_caller_address(escrow_address);
}

#[test]
fn test_transfer_all_with_zero_balance() {
    let (earn_token, _) = setup_earn_token();
    let escrow_address = setup_escrow(earn_token, TREASURY());
    let escrow = IEscrowDispatcher { contract_address: escrow_address };

    // No tokens in escrow, should still work
    start_cheat_caller_address(escrow_address, OWNER());
    escrow.transfer_all();
    stop_cheat_caller_address(escrow_address);

    assert(get_balance(earn_token, escrow_address) == 0, 'Escrow should be empty');
}

// ============================================================================
// Withdraw_to_contract4 Tests
// ============================================================================

#[test]
fn test_withdraw_to_contract4() {
    let (earn_token, _) = setup_earn_token();
    let escrow_address = setup_escrow(earn_token, TREASURY());
    let escrow = IEscrowDispatcher { contract_address: escrow_address };

    // Set contract4
    start_cheat_caller_address(escrow_address, OWNER());
    escrow.set_contract4(USER1());
    stop_cheat_caller_address(escrow_address);

    // Transfer tokens to escrow
    transfer_token(earn_token, OWNER(), escrow_address, THOUSAND_TOKENS);

    // Contract4 withdraws
    start_cheat_caller_address(escrow_address, USER1());
    escrow.withdraw_to_contract4(HUNDRED_TOKENS);
    stop_cheat_caller_address(escrow_address);

    assert(get_balance(earn_token, USER1()) == HUNDRED_TOKENS, 'Wrong contract4 balance');
    assert(
        get_balance(earn_token, escrow_address) == THOUSAND_TOKENS - HUNDRED_TOKENS,
        'Wrong escrow balance',
    );
}

#[test]
#[should_panic(expected: ('Only Contract 4',))]
fn test_withdraw_to_contract4_not_contract4() {
    let (earn_token, _) = setup_earn_token();
    let escrow_address = setup_escrow(earn_token, TREASURY());
    let escrow = IEscrowDispatcher { contract_address: escrow_address };

    // Set contract4
    start_cheat_caller_address(escrow_address, OWNER());
    escrow.set_contract4(USER1());
    stop_cheat_caller_address(escrow_address);

    // Transfer tokens to escrow
    transfer_token(earn_token, OWNER(), escrow_address, THOUSAND_TOKENS);

    // USER2 tries to withdraw (not contract4)
    start_cheat_caller_address(escrow_address, USER2());
    escrow.withdraw_to_contract4(HUNDRED_TOKENS);
    stop_cheat_caller_address(escrow_address);
}

#[test]
#[should_panic(expected: ('Only Contract 4',))]
fn test_withdraw_to_contract4_owner_cannot() {
    let (earn_token, _) = setup_earn_token();
    let escrow_address = setup_escrow(earn_token, TREASURY());
    let escrow = IEscrowDispatcher { contract_address: escrow_address };

    // Set contract4
    start_cheat_caller_address(escrow_address, OWNER());
    escrow.set_contract4(USER1());
    stop_cheat_caller_address(escrow_address);

    // Transfer tokens to escrow
    transfer_token(earn_token, OWNER(), escrow_address, THOUSAND_TOKENS);

    // Even owner cannot call withdraw_to_contract4
    start_cheat_caller_address(escrow_address, OWNER());
    escrow.withdraw_to_contract4(HUNDRED_TOKENS);
    stop_cheat_caller_address(escrow_address);
}

#[test]
#[should_panic(expected: ('Insufficient balance',))]
fn test_withdraw_to_contract4_insufficient_balance() {
    let (earn_token, _) = setup_earn_token();
    let escrow_address = setup_escrow(earn_token, TREASURY());
    let escrow = IEscrowDispatcher { contract_address: escrow_address };

    // Set contract4
    start_cheat_caller_address(escrow_address, OWNER());
    escrow.set_contract4(USER1());
    stop_cheat_caller_address(escrow_address);

    // Try to withdraw without having tokens
    start_cheat_caller_address(escrow_address, USER1());
    escrow.withdraw_to_contract4(HUNDRED_TOKENS);
    stop_cheat_caller_address(escrow_address);
}

#[test]
fn test_multiple_operations() {
    let (earn_token, _) = setup_earn_token();
    let escrow_address = setup_escrow(earn_token, TREASURY());
    let escrow = IEscrowDispatcher { contract_address: escrow_address };

    // Setup contract4
    start_cheat_caller_address(escrow_address, OWNER());
    escrow.set_contract4(USER1());
    stop_cheat_caller_address(escrow_address);

    // Transfer tokens to escrow
    transfer_token(earn_token, OWNER(), escrow_address, THOUSAND_TOKENS);

    // Owner transfers some
    start_cheat_caller_address(escrow_address, OWNER());
    escrow.transfer_to(USER2(), HUNDRED_TOKENS);
    stop_cheat_caller_address(escrow_address);

    // Contract4 withdraws some
    start_cheat_caller_address(escrow_address, USER1());
    escrow.withdraw_to_contract4(HUNDRED_TOKENS);
    stop_cheat_caller_address(escrow_address);

    // Transfer remaining to treasury
    start_cheat_caller_address(escrow_address, OWNER());
    escrow.transfer_all();
    stop_cheat_caller_address(escrow_address);

    let expected_treasury = THOUSAND_TOKENS - (2 * HUNDRED_TOKENS);
    assert(get_balance(earn_token, TREASURY()) == expected_treasury, 'Wrong treasury balance');
    assert(get_balance(earn_token, USER2()) == HUNDRED_TOKENS, 'Wrong USER2 balance');
    assert(get_balance(earn_token, USER1()) == HUNDRED_TOKENS, 'Wrong contract4 balance');
    assert(get_balance(earn_token, escrow_address) == 0, 'Escrow should be empty');
}

#[test]
fn test_update_contract4() {
    let (earn_token, _) = setup_earn_token();
    let escrow_address = setup_escrow(earn_token, TREASURY());
    let escrow = IEscrowDispatcher { contract_address: escrow_address };

    // Set initial contract4
    start_cheat_caller_address(escrow_address, OWNER());
    escrow.set_contract4(USER1());
    stop_cheat_caller_address(escrow_address);

    assert(escrow.contract4() == USER1(), 'Wrong initial contract4');

    // Update contract4
    start_cheat_caller_address(escrow_address, OWNER());
    escrow.set_contract4(USER2());
    stop_cheat_caller_address(escrow_address);

    assert(escrow.contract4() == USER2(), 'Wrong updated contract4');

    // Transfer tokens to escrow
    transfer_token(earn_token, OWNER(), escrow_address, THOUSAND_TOKENS);

    // New contract4 can withdraw
    start_cheat_caller_address(escrow_address, USER2());
    escrow.withdraw_to_contract4(HUNDRED_TOKENS);
    stop_cheat_caller_address(escrow_address);

    assert(get_balance(earn_token, USER2()) == HUNDRED_TOKENS, 'New contract4 cannot withdraw');
}

// ============================================================================
// Time-related Tests
// ============================================================================

#[test]
fn test_deployment_and_closing_time() {
    let (earn_token, _) = setup_earn_token();
    let escrow_address = setup_escrow(earn_token, TREASURY());
    let escrow = IEscrowDispatcher { contract_address: escrow_address };

    let deployment = escrow.get_deployment_time();
    let closing = escrow.get_closing_time();

    // Closing time should be 1 day after deployment
    assert(closing == deployment + ONE_DAY, 'Wrong time difference');
    assert(closing > deployment, 'Closing before deployment');
}

// ============================================================================
// Ownership Tests
// ============================================================================

#[test]
fn test_transfer_ownership() {
    let (earn_token, _) = setup_earn_token();
    let escrow_address = setup_escrow(earn_token, TREASURY());
    let escrow = IEscrowDispatcher { contract_address: escrow_address };
    let ownable = IOwnableDispatcher { contract_address: escrow_address };

    start_cheat_caller_address(escrow_address, OWNER());
    ownable.transfer_ownership(USER1());
    stop_cheat_caller_address(escrow_address);

    assert(ownable.owner() == USER1(), 'Ownership not transferred');

    // New owner can perform owner actions
    start_cheat_caller_address(escrow_address, USER1());
    escrow.set_contract4(USER2());
    stop_cheat_caller_address(escrow_address);

    assert(escrow.contract4() == USER2(), 'New owner cannot set contract4');
}

