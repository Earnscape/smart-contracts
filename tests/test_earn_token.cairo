use openzeppelin::access::ownable::interface::{IOwnableDispatcher, IOwnableDispatcherTrait};
use openzeppelin::token::erc20::interface::ERC20ABIDispatcherTrait;
use snforge_std::{start_cheat_caller_address, stop_cheat_caller_address};
use crate::utils::{
    HUNDRED_TOKENS, ONE_BILLION_TOKENS, OWNER, THOUSAND_TOKENS, USER1, USER2, ZERO_ADDRESS,
    setup_earn_token,
};

// ============================================================================
// Constructor Tests
// ============================================================================

#[test]
fn test_constructor() {
    let (contract_address, token) = setup_earn_token();

    // Check initial supply minted to owner
    let owner_balance = token.balance_of(OWNER());
    assert(owner_balance == ONE_BILLION_TOKENS, 'Wrong initial supply');

    // Check total supply matches
    let total = token.total_supply();
    assert(total == ONE_BILLION_TOKENS, 'Wrong total supply');

    // Verify contract address is not zero
    assert(contract_address.into() != 0, 'Invalid contract address');
}

// ============================================================================
// Transfer Tests
// ============================================================================

#[test]
fn test_transfer() {
    let (_, token) = setup_earn_token();
    let transfer_amount = HUNDRED_TOKENS;

    // Check owner transfers
    start_cheat_caller_address(token.contract_address, OWNER());
    let success = token.transfer(USER1(), transfer_amount);
    stop_cheat_caller_address(token.contract_address);

    assert(success, 'Transfer failed');

    // Check balances
    let user1_balance = token.balance_of(USER1());
    assert(user1_balance == transfer_amount, 'Wrong USER1 balance');

    let owner_balance = token.balance_of(OWNER());
    assert(owner_balance == ONE_BILLION_TOKENS - transfer_amount, 'Wrong owner balance');
}

#[test]
#[should_panic(expected: ('ERC20: insufficient balance',))]
fn test_transfer_insufficient_balance() {
    let (_, token) = setup_earn_token();

    // USER1 has no tokens, tries to transfer
    start_cheat_caller_address(token.contract_address, USER1());
    token.transfer(USER2(), HUNDRED_TOKENS);
    stop_cheat_caller_address(token.contract_address);
}

#[test]
#[should_panic(expected: ('ERC20: transfer to 0',))]
fn test_transfer_to_zero_address() {
    let (_, token) = setup_earn_token();

    start_cheat_caller_address(token.contract_address, OWNER());
    token.transfer(ZERO_ADDRESS(), HUNDRED_TOKENS);
    stop_cheat_caller_address(token.contract_address);
}

#[test]
fn test_transfer_zero_amount() {
    let (_, token) = setup_earn_token();

    start_cheat_caller_address(token.contract_address, OWNER());
    let success = token.transfer(USER1(), 0);
    stop_cheat_caller_address(token.contract_address);

    assert(success, 'Transfer should succeed');
    assert(token.balance_of(USER1()) == 0, 'Balance should be zero');
}

// ============================================================================
// Approve Tests
// ============================================================================

#[test]
fn test_approve() {
    let (_, token) = setup_earn_token();

    let approve_amount = THOUSAND_TOKENS;

    start_cheat_caller_address(token.contract_address, OWNER());
    let success = token.approve(USER1(), approve_amount);
    stop_cheat_caller_address(token.contract_address);

    assert(success, 'Approve failed');

    let allowance = token.allowance(OWNER(), USER1());
    assert(allowance == approve_amount, 'Wrong allowance');
}

#[test]
#[should_panic(expected: ('ERC20: approve to 0',))]
fn test_approve_to_zero_address() {
    let (_, token) = setup_earn_token();

    start_cheat_caller_address(token.contract_address, OWNER());
    token.approve(ZERO_ADDRESS(), HUNDRED_TOKENS);
    stop_cheat_caller_address(token.contract_address);
}

// ============================================================================
// TransferFrom Tests
// ============================================================================

#[test]
fn test_transfer_from() {
    let (_, token) = setup_earn_token();

    let approve_amount = THOUSAND_TOKENS;
    let transfer_amount = HUNDRED_TOKENS;

    // Owner approves USER1
    start_cheat_caller_address(token.contract_address, OWNER());
    token.approve(USER1(), approve_amount);
    stop_cheat_caller_address(token.contract_address);

    // USER1 transfers from OWNER to USER2
    start_cheat_caller_address(token.contract_address, USER1());
    let success = token.transfer_from(OWNER(), USER2(), transfer_amount);
    stop_cheat_caller_address(token.contract_address);

    assert(success, 'TransferFrom failed');

    // Check balances
    assert(token.balance_of(USER2()) == transfer_amount, 'Wrong USER2 balance');
    assert(
        token.balance_of(OWNER()) == ONE_BILLION_TOKENS - transfer_amount, 'Wrong owner balance',
    );

    // Check remaining allowance
    let remaining_allowance = token.allowance(OWNER(), USER1());
    assert(remaining_allowance == approve_amount - transfer_amount, 'Wrong remaining allowance');
}

#[test]
#[should_panic(expected: ('ERC20: insufficient allowance',))]
fn test_transfer_from_insufficient_allowance() {
    let (_, token) = setup_earn_token();

    let approve_amount = HUNDRED_TOKENS;
    let transfer_amount = THOUSAND_TOKENS;

    // Owner approves USER1 for small amount
    start_cheat_caller_address(token.contract_address, OWNER());
    token.approve(USER1(), approve_amount);
    stop_cheat_caller_address(token.contract_address);

    // USER1 tries to transfer more than approved
    start_cheat_caller_address(token.contract_address, USER1());
    token.transfer_from(OWNER(), USER2(), transfer_amount);
    stop_cheat_caller_address(token.contract_address);
}

#[test]
#[should_panic(expected: ('ERC20: insufficient balance',))]
fn test_transfer_from_insufficient_balance() {
    let (_, token) = setup_earn_token();

    // USER1 approves USER2 but has no balance
    start_cheat_caller_address(token.contract_address, USER1());
    token.approve(USER2(), THOUSAND_TOKENS);
    stop_cheat_caller_address(token.contract_address);

    // USER2 tries to transfer from USER1
    start_cheat_caller_address(token.contract_address, USER2());
    token.transfer_from(USER1(), OWNER(), HUNDRED_TOKENS);
    stop_cheat_caller_address(token.contract_address);
}

#[test]
fn test_multiple_transfers() {
    let (_, token) = setup_earn_token();

    // Owner transfers to multiple users
    start_cheat_caller_address(token.contract_address, OWNER());
    token.transfer(USER1(), HUNDRED_TOKENS);
    token.transfer(USER2(), HUNDRED_TOKENS);
    stop_cheat_caller_address(token.contract_address);

    assert(token.balance_of(USER1()) == HUNDRED_TOKENS, 'Wrong USER1 balance');
    assert(token.balance_of(USER2()) == HUNDRED_TOKENS, 'Wrong USER2 balance');
    assert(
        token.balance_of(OWNER()) == ONE_BILLION_TOKENS - (2 * HUNDRED_TOKENS),
        'Wrong owner balance',
    );
}

#[test]
fn test_approve_and_increase() {
    let (_, token) = setup_earn_token();

    // Initial approval
    start_cheat_caller_address(token.contract_address, OWNER());
    token.approve(USER1(), HUNDRED_TOKENS);
    stop_cheat_caller_address(token.contract_address);

    assert(token.allowance(OWNER(), USER1()) == HUNDRED_TOKENS, 'Wrong initial allowance');

    // Increase approval (by setting new value)
    start_cheat_caller_address(token.contract_address, OWNER());
    token.approve(USER1(), THOUSAND_TOKENS);
    stop_cheat_caller_address(token.contract_address);

    assert(token.allowance(OWNER(), USER1()) == THOUSAND_TOKENS, 'Wrong updated allowance');
}

#[test]
fn test_transfer_entire_balance() {
    let (_, token) = setup_earn_token();

    start_cheat_caller_address(token.contract_address, OWNER());
    token.transfer(USER1(), ONE_BILLION_TOKENS);
    stop_cheat_caller_address(token.contract_address);

    assert(token.balance_of(OWNER()) == 0, 'Owner should have zero');
    assert(token.balance_of(USER1()) == ONE_BILLION_TOKENS, 'USER1 should have all');
}

// ============================================================================
// Ownership Tests
// ============================================================================

#[test]
fn test_owner_is_set_correctly() {
    let (contract_address, _) = setup_earn_token();
    let ownable = IOwnableDispatcher { contract_address };

    assert(ownable.owner() == OWNER(), 'Wrong owner');
}

#[test]
fn test_transfer_ownership() {
    let (contract_address, _) = setup_earn_token();
    let ownable = IOwnableDispatcher { contract_address };

    // Transfer ownership
    start_cheat_caller_address(contract_address, OWNER());
    ownable.transfer_ownership(USER1());
    stop_cheat_caller_address(contract_address);

    assert(ownable.owner() == USER1(), 'Ownership not transferred');
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_transfer_ownership_not_owner() {
    let (contract_address, _) = setup_earn_token();
    let ownable = IOwnableDispatcher { contract_address };

    // USER1 tries to transfer ownership
    start_cheat_caller_address(contract_address, USER1());
    ownable.transfer_ownership(USER2());
    stop_cheat_caller_address(contract_address);
}

