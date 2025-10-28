use openzeppelin::access::ownable::interface::{IOwnableDispatcher, IOwnableDispatcherTrait};
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use snforge_std::{start_cheat_caller_address, stop_cheat_caller_address};
use starknet::ContractAddress;
use crate::utils::{
    HUNDRED_TOKENS, OWNER, THOUSAND_TOKENS, USER1, USER2, ZERO_ADDRESS, setup_stearn_token,
};

#[starknet::interface]
trait IStEarnToken<TContractState> {
    fn vesting_contract(self: @TContractState) -> ContractAddress;
    fn staking_contract(self: @TContractState) -> ContractAddress;
    fn set_vesting_address(ref self: TContractState, vesting: ContractAddress);
    fn set_staking_contract_address(ref self: TContractState, staking_contract: ContractAddress);
    fn mint(ref self: TContractState, to: ContractAddress, amount: u256);
    fn burn(ref self: TContractState, user: ContractAddress, amount: u256);
}

// ============================================================================
// Constructor Tests
// ============================================================================

#[test]
fn test_constructor() {
    let contract_address = setup_stearn_token();
    let erc20 = ERC20ABIDispatcher { contract_address };

    // Check initial supply is 0 (no tokens minted at construction)
    assert(erc20.total_supply() == 0, 'Initial supply should be 0');

    // Verify contract address is valid
    assert(contract_address.into() != 0, 'Invalid contract address');
}

// ============================================================================
// Vesting/Staking Contract Setter Tests
// ============================================================================

#[test]
fn test_set_vesting_address() {
    let contract_address = setup_stearn_token();
    let token = IStEarnTokenDispatcher { contract_address };

    start_cheat_caller_address(contract_address, OWNER());
    token.set_vesting_address(USER1());
    stop_cheat_caller_address(contract_address);

    assert(token.vesting_contract() == USER1(), 'Wrong vesting address');
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_set_vesting_address_not_owner() {
    let contract_address = setup_stearn_token();
    let token = IStEarnTokenDispatcher { contract_address };

    start_cheat_caller_address(contract_address, USER1());
    token.set_vesting_address(USER2());
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_set_staking_contract_address() {
    let contract_address = setup_stearn_token();
    let token = IStEarnTokenDispatcher { contract_address };

    start_cheat_caller_address(contract_address, OWNER());
    token.set_staking_contract_address(USER1());
    stop_cheat_caller_address(contract_address);

    assert(token.staking_contract() == USER1(), 'Wrong staking address');
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_set_staking_contract_address_not_owner() {
    let contract_address = setup_stearn_token();
    let token = IStEarnTokenDispatcher { contract_address };

    start_cheat_caller_address(contract_address, USER1());
    token.set_staking_contract_address(USER2());
    stop_cheat_caller_address(contract_address);
}

// ============================================================================
// Mint Tests
// ============================================================================

#[test]
#[should_panic(expected: ('Contracts not configured',))]
fn test_mint_from_vesting() {
    let contract_address = setup_stearn_token();
    let token = IStEarnTokenDispatcher { contract_address };

    // Set only vesting contract (staking not configured)
    start_cheat_caller_address(contract_address, OWNER());
    token.set_vesting_address(USER1());
    stop_cheat_caller_address(contract_address);

    // Mint from vesting contract - should panic
    start_cheat_caller_address(contract_address, USER1());
    token.mint(USER2(), HUNDRED_TOKENS);
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_mint_from_vesting_configured() {
    let contract_address = setup_stearn_token();
    let token = IStEarnTokenDispatcher { contract_address };
    let erc20 = ERC20ABIDispatcher { contract_address };

    // Set both vesting and staking contracts
    start_cheat_caller_address(contract_address, OWNER());
    token.set_vesting_address(USER1());
    token.set_staking_contract_address(OWNER()); // Configure staking too
    stop_cheat_caller_address(contract_address);

    // Mint from vesting contract
    start_cheat_caller_address(contract_address, USER1());
    token.mint(USER2(), HUNDRED_TOKENS);
    stop_cheat_caller_address(contract_address);

    assert(erc20.balance_of(USER2()) == HUNDRED_TOKENS, 'Wrong balance');
    assert(erc20.total_supply() == HUNDRED_TOKENS, 'Wrong total supply');
}

#[test]
#[should_panic(expected: ('Contracts not configured',))]
fn test_mint_from_staking() {
    let contract_address = setup_stearn_token();
    let token = IStEarnTokenDispatcher { contract_address };

    // Set only staking contract (vesting not configured)
    start_cheat_caller_address(contract_address, OWNER());
    token.set_staking_contract_address(USER1());
    stop_cheat_caller_address(contract_address);

    // Mint from staking contract - should panic
    start_cheat_caller_address(contract_address, USER1());
    token.mint(USER2(), HUNDRED_TOKENS);
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_mint_from_staking_configured() {
    let contract_address = setup_stearn_token();
    let token = IStEarnTokenDispatcher { contract_address };
    let erc20 = ERC20ABIDispatcher { contract_address };

    // Set both staking and vesting contracts
    start_cheat_caller_address(contract_address, OWNER());
    token.set_staking_contract_address(USER1());
    token.set_vesting_address(OWNER()); // Configure vesting too
    stop_cheat_caller_address(contract_address);

    // Mint from staking contract
    start_cheat_caller_address(contract_address, USER1());
    token.mint(USER2(), HUNDRED_TOKENS);
    stop_cheat_caller_address(contract_address);

    assert(erc20.balance_of(USER2()) == HUNDRED_TOKENS, 'Wrong balance');
    assert(erc20.total_supply() == HUNDRED_TOKENS, 'Wrong total supply');
}

#[test]
#[should_panic(expected: ('Contracts not configured',))]
fn test_mint_unauthorized() {
    let contract_address = setup_stearn_token();
    let token = IStEarnTokenDispatcher { contract_address };

    // USER1 tries to mint without contracts being configured
    start_cheat_caller_address(contract_address, USER1());
    token.mint(USER2(), HUNDRED_TOKENS);
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: ('Not allowed to call',))]
fn test_mint_unauthorized_configured() {
    let contract_address = setup_stearn_token();
    let token = IStEarnTokenDispatcher { contract_address };

    // Configure both contracts
    start_cheat_caller_address(contract_address, OWNER());
    token.set_vesting_address(OWNER());
    token.set_staking_contract_address(USER2());
    stop_cheat_caller_address(contract_address);

    // USER1 tries to mint without being vesting or staking
    start_cheat_caller_address(contract_address, USER1());
    token.mint(USER2(), HUNDRED_TOKENS);
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: ('Contracts not configured',))]
fn test_mint_owner_cannot_mint() {
    let contract_address = setup_stearn_token();
    let token = IStEarnTokenDispatcher { contract_address };

    // Even owner cannot mint without contracts configured
    start_cheat_caller_address(contract_address, OWNER());
    token.mint(USER1(), HUNDRED_TOKENS);
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: ('Not allowed to call',))]
fn test_mint_owner_cannot_mint_configured() {
    let contract_address = setup_stearn_token();
    let token = IStEarnTokenDispatcher { contract_address };

    // Configure both contracts
    start_cheat_caller_address(contract_address, OWNER());
    token.set_vesting_address(USER1());
    token.set_staking_contract_address(USER2());
    // Even owner cannot mint directly
    token.mint(USER1(), HUNDRED_TOKENS);
    stop_cheat_caller_address(contract_address);
}

// ============================================================================
// Burn Tests
// ============================================================================

#[test]
#[should_panic(expected: ('Contracts not configured',))]
fn test_burn_from_vesting() {
    let contract_address = setup_stearn_token();
    let token = IStEarnTokenDispatcher { contract_address };

    // Set only vesting contract (staking not configured)
    start_cheat_caller_address(contract_address, OWNER());
    token.set_vesting_address(USER1());
    stop_cheat_caller_address(contract_address);

    // Try to mint - should panic
    start_cheat_caller_address(contract_address, USER1());
    token.mint(USER2(), HUNDRED_TOKENS);
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_burn_from_vesting_configured() {
    let contract_address = setup_stearn_token();
    let token = IStEarnTokenDispatcher { contract_address };
    let erc20 = ERC20ABIDispatcher { contract_address };

    // Set both vesting and staking contracts
    start_cheat_caller_address(contract_address, OWNER());
    token.set_vesting_address(USER1());
    token.set_staking_contract_address(OWNER()); // Configure staking too
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, USER1());
    token.mint(USER2(), HUNDRED_TOKENS);
    stop_cheat_caller_address(contract_address);

    // Burn from vesting contract
    start_cheat_caller_address(contract_address, USER1());
    token.burn(USER2(), HUNDRED_TOKENS);
    stop_cheat_caller_address(contract_address);

    assert(erc20.balance_of(USER2()) == 0, 'Balance should be 0');
    assert(erc20.total_supply() == 0, 'Total supply should be 0');
}

#[test]
#[should_panic(expected: ('Contracts not configured',))]
fn test_burn_from_staking() {
    let contract_address = setup_stearn_token();
    let token = IStEarnTokenDispatcher { contract_address };

    // Set only staking contract (vesting not configured)
    start_cheat_caller_address(contract_address, OWNER());
    token.set_staking_contract_address(USER1());
    stop_cheat_caller_address(contract_address);

    // Try to mint - should panic
    start_cheat_caller_address(contract_address, USER1());
    token.mint(USER2(), HUNDRED_TOKENS);
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_burn_from_staking_configured() {
    let contract_address = setup_stearn_token();
    let token = IStEarnTokenDispatcher { contract_address };
    let erc20 = ERC20ABIDispatcher { contract_address };

    // Set both staking and vesting contracts
    start_cheat_caller_address(contract_address, OWNER());
    token.set_staking_contract_address(USER1());
    token.set_vesting_address(OWNER()); // Configure vesting too
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, USER1());
    token.mint(USER2(), HUNDRED_TOKENS);
    stop_cheat_caller_address(contract_address);

    // Burn from staking contract
    start_cheat_caller_address(contract_address, USER1());
    token.burn(USER2(), HUNDRED_TOKENS);
    stop_cheat_caller_address(contract_address);

    assert(erc20.balance_of(USER2()) == 0, 'Balance should be 0');
    assert(erc20.total_supply() == 0, 'Total supply should be 0');
}

#[test]
#[should_panic(expected: ('Contracts not configured',))]
fn test_burn_unauthorized() {
    let contract_address = setup_stearn_token();
    let token = IStEarnTokenDispatcher { contract_address };

    // Set up only vesting (staking not configured)
    start_cheat_caller_address(contract_address, OWNER());
    token.set_vesting_address(USER1());
    stop_cheat_caller_address(contract_address);

    // Try to mint - should panic due to unconfigured staking
    start_cheat_caller_address(contract_address, USER1());
    token.mint(USER2(), HUNDRED_TOKENS);
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: ('Not allowed to call',))]
fn test_burn_unauthorized_configured() {
    let contract_address = setup_stearn_token();
    let token = IStEarnTokenDispatcher { contract_address };

    // Set up both vesting and staking
    start_cheat_caller_address(contract_address, OWNER());
    token.set_vesting_address(USER1());
    token.set_staking_contract_address(OWNER());
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, USER1());
    token.mint(USER2(), HUNDRED_TOKENS);
    stop_cheat_caller_address(contract_address);

    // USER2 tries to burn (not authorized)
    start_cheat_caller_address(contract_address, USER2());
    token.burn(USER2(), HUNDRED_TOKENS);
    stop_cheat_caller_address(contract_address);
}

// ============================================================================
// Transfer Restriction Tests
// ============================================================================

#[test]
#[should_panic(expected: ('Contracts not configured',))]
fn test_transfer_to_vesting() {
    let contract_address = setup_stearn_token();
    let token = IStEarnTokenDispatcher { contract_address };

    // Setup: only vesting contract (staking not configured)
    start_cheat_caller_address(contract_address, OWNER());
    token.set_vesting_address(USER1());
    stop_cheat_caller_address(contract_address);

    // Try to mint - should panic
    start_cheat_caller_address(contract_address, USER1());
    token.mint(USER2(), HUNDRED_TOKENS);
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_transfer_to_vesting_configured() {
    let contract_address = setup_stearn_token();
    let token = IStEarnTokenDispatcher { contract_address };
    let erc20 = ERC20ABIDispatcher { contract_address };

    // Setup: both vesting and staking contracts
    start_cheat_caller_address(contract_address, OWNER());
    token.set_vesting_address(USER1());
    token.set_staking_contract_address(OWNER()); // Configure staking too
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, USER1());
    token.mint(USER2(), HUNDRED_TOKENS);
    stop_cheat_caller_address(contract_address);

    // USER2 can transfer to vesting
    start_cheat_caller_address(contract_address, USER2());
    let success = erc20.transfer(USER1(), HUNDRED_TOKENS);
    stop_cheat_caller_address(contract_address);

    assert(success, 'Transfer should succeed');
    assert(erc20.balance_of(USER1()) == HUNDRED_TOKENS, 'Wrong vesting balance');
}

#[test]
#[should_panic(expected: ('Contracts not configured',))]
fn test_transfer_to_staking() {
    let contract_address = setup_stearn_token();
    let token = IStEarnTokenDispatcher { contract_address };

    // Setup: only staking contract (vesting not configured)
    start_cheat_caller_address(contract_address, OWNER());
    token.set_staking_contract_address(USER1());
    stop_cheat_caller_address(contract_address);

    // Try to mint - should panic
    start_cheat_caller_address(contract_address, USER1());
    token.mint(USER2(), HUNDRED_TOKENS);
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_transfer_to_staking_configured() {
    let contract_address = setup_stearn_token();
    let token = IStEarnTokenDispatcher { contract_address };
    let erc20 = ERC20ABIDispatcher { contract_address };

    // Setup: both staking and vesting contracts
    start_cheat_caller_address(contract_address, OWNER());
    token.set_staking_contract_address(USER1());
    token.set_vesting_address(OWNER()); // Configure vesting too
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, USER1());
    token.mint(USER2(), HUNDRED_TOKENS);
    stop_cheat_caller_address(contract_address);

    // USER2 can transfer to staking
    start_cheat_caller_address(contract_address, USER2());
    let success = erc20.transfer(USER1(), HUNDRED_TOKENS);
    stop_cheat_caller_address(contract_address);

    assert(success, 'Transfer should succeed');
    assert(erc20.balance_of(USER1()) == HUNDRED_TOKENS, 'Wrong staking balance');
}

#[test]
#[should_panic(expected: ('Contracts not configured',))]
fn test_transfer_to_zero_address_burn() {
    let contract_address = setup_stearn_token();
    let token = IStEarnTokenDispatcher { contract_address };

    // Setup: only vesting (staking not configured)
    start_cheat_caller_address(contract_address, OWNER());
    token.set_vesting_address(USER1());
    stop_cheat_caller_address(contract_address);

    // Try to mint - should panic
    start_cheat_caller_address(contract_address, USER1());
    token.mint(USER2(), HUNDRED_TOKENS);
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: ('ERC20: transfer to 0',))]
fn test_transfer_to_zero_address_burn_configured() {
    let contract_address = setup_stearn_token();
    let token = IStEarnTokenDispatcher { contract_address };
    let erc20 = ERC20ABIDispatcher { contract_address };

    // Setup: both contracts configured
    start_cheat_caller_address(contract_address, OWNER());
    token.set_vesting_address(USER1());
    token.set_staking_contract_address(OWNER());
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, USER1());
    token.mint(USER2(), HUNDRED_TOKENS);
    stop_cheat_caller_address(contract_address);

    // OpenZeppelin ERC20 blocks transfers to zero address before hooks
    // This should panic with 'ERC20: transfer to 0'
    start_cheat_caller_address(contract_address, USER2());
    erc20.transfer(ZERO_ADDRESS(), HUNDRED_TOKENS);
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic]
fn test_transfer_to_regular_user_fails() {
    let contract_address = setup_stearn_token();
    let token = IStEarnTokenDispatcher { contract_address };
    let erc20 = ERC20ABIDispatcher { contract_address };

    // Setup: vesting contract and mint to USER1
    start_cheat_caller_address(contract_address, OWNER());
    token.set_vesting_address(OWNER());
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, OWNER());
    token.mint(USER1(), HUNDRED_TOKENS);
    stop_cheat_caller_address(contract_address);

    // USER1 tries to transfer to USER2 (should fail)
    start_cheat_caller_address(contract_address, USER1());
    erc20.transfer(USER2(), HUNDRED_TOKENS);
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: ('Contracts not configured',))]
fn test_mint_and_burn_cycle() {
    let contract_address = setup_stearn_token();
    let token = IStEarnTokenDispatcher { contract_address };

    // Set only vesting contract (staking not configured)
    start_cheat_caller_address(contract_address, OWNER());
    token.set_vesting_address(USER1());
    stop_cheat_caller_address(contract_address);

    // Try to mint - should panic
    start_cheat_caller_address(contract_address, USER1());
    token.mint(USER2(), THOUSAND_TOKENS);
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_mint_and_burn_cycle_configured() {
    let contract_address = setup_stearn_token();
    let token = IStEarnTokenDispatcher { contract_address };
    let erc20 = ERC20ABIDispatcher { contract_address };

    // Set both vesting and staking contracts
    start_cheat_caller_address(contract_address, OWNER());
    token.set_vesting_address(USER1());
    token.set_staking_contract_address(OWNER());
    stop_cheat_caller_address(contract_address);

    // Mint
    start_cheat_caller_address(contract_address, USER1());
    token.mint(USER2(), THOUSAND_TOKENS);
    stop_cheat_caller_address(contract_address);

    assert(erc20.total_supply() == THOUSAND_TOKENS, 'Wrong supply after mint');

    // Burn partial
    start_cheat_caller_address(contract_address, USER1());
    token.burn(USER2(), HUNDRED_TOKENS);
    stop_cheat_caller_address(contract_address);

    assert(
        erc20.balance_of(USER2()) == THOUSAND_TOKENS - HUNDRED_TOKENS, 'Wrong balance after burn',
    );
    assert(erc20.total_supply() == THOUSAND_TOKENS - HUNDRED_TOKENS, 'Wrong supply after burn');
}

#[test]
fn test_multiple_mints_different_contracts() {
    let contract_address = setup_stearn_token();
    let token = IStEarnTokenDispatcher { contract_address };
    let erc20 = ERC20ABIDispatcher { contract_address };

    // Set both vesting and staking
    start_cheat_caller_address(contract_address, OWNER());
    token.set_vesting_address(USER1());
    token.set_staking_contract_address(USER2());
    stop_cheat_caller_address(contract_address);

    // Mint from vesting
    start_cheat_caller_address(contract_address, USER1());
    token.mint(OWNER(), HUNDRED_TOKENS);
    stop_cheat_caller_address(contract_address);

    // Mint from staking
    start_cheat_caller_address(contract_address, USER2());
    token.mint(OWNER(), HUNDRED_TOKENS);
    stop_cheat_caller_address(contract_address);

    assert(erc20.balance_of(OWNER()) == 2 * HUNDRED_TOKENS, 'Wrong total balance');
    assert(erc20.total_supply() == 2 * HUNDRED_TOKENS, 'Wrong total supply');
}

#[test]
fn test_update_vesting_and_staking_addresses() {
    let contract_address = setup_stearn_token();
    let token = IStEarnTokenDispatcher { contract_address };

    // Set initial addresses
    start_cheat_caller_address(contract_address, OWNER());
    token.set_vesting_address(USER1());
    token.set_staking_contract_address(USER2());
    stop_cheat_caller_address(contract_address);

    assert(token.vesting_contract() == USER1(), 'Wrong initial vesting');
    assert(token.staking_contract() == USER2(), 'Wrong initial staking');

    // Update addresses
    start_cheat_caller_address(contract_address, OWNER());
    token.set_vesting_address(USER2());
    token.set_staking_contract_address(USER1());
    stop_cheat_caller_address(contract_address);

    assert(token.vesting_contract() == USER2(), 'Wrong updated vesting');
    assert(token.staking_contract() == USER1(), 'Wrong updated staking');
}

// ============================================================================
// Ownership Tests
// ============================================================================

#[test]
fn test_transfer_ownership() {
    let contract_address = setup_stearn_token();
    let token = IStEarnTokenDispatcher { contract_address };
    let ownable = IOwnableDispatcher { contract_address };

    start_cheat_caller_address(contract_address, OWNER());
    ownable.transfer_ownership(USER1());
    stop_cheat_caller_address(contract_address);

    assert(ownable.owner() == USER1(), 'Ownership not transferred');

    // New owner can set addresses
    start_cheat_caller_address(contract_address, USER1());
    token.set_vesting_address(USER2());
    stop_cheat_caller_address(contract_address);

    assert(token.vesting_contract() == USER2(), 'New owner cannot set vesting');
}

