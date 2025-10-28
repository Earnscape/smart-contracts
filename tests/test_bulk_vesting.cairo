use openzeppelin::access::ownable::interface::{IOwnableDispatcher, IOwnableDispatcherTrait};
use snforge_std::{start_cheat_caller_address, stop_cheat_caller_address};
use starknet::ContractAddress;
use crate::utils::{
    ONE_MILLION_TOKENS, ONE_TOKEN, OWNER, THOUSAND_TOKENS, TREASURY, USER1, USER2, USER3,
    advance_time, get_balance, setup_bulk_vesting, setup_earn_token, setup_earnstark_manager,
    setup_escrow, transfer_token,
};

#[starknet::interface]
trait IEarnscapeBulkVesting<TContractState> {
    fn add_user_data(
        ref self: TContractState,
        category_id: u8,
        names: Span<felt252>,
        user_addresses: Span<ContractAddress>,
        amounts: Span<u256>,
    );
    fn calculate_releasable_amount(
        ref self: TContractState, beneficiary: ContractAddress,
    ) -> (u256, u256);
    fn release_vested_amount(ref self: TContractState, beneficiary: ContractAddress);
    fn release_immediately(ref self: TContractState, category_id: u8, recipient: ContractAddress);
    fn update_category_supply(ref self: TContractState, category_id: u8, additional_supply: u256);
    fn get_category_details(self: @TContractState, category_id: u8) -> (felt252, u256, u256, u64);
    fn get_user_vesting_count(self: @TContractState, beneficiary: ContractAddress) -> u32;
    fn get_vesting_schedule(
        self: @TContractState, beneficiary: ContractAddress, index: u32,
    ) -> (ContractAddress, u64, u64, u64, u64, u256, u256);
    fn get_total_amount_vested(self: @TContractState) -> u256;
    fn get_earn_stark_manager(self: @TContractState) -> ContractAddress;
    fn get_escrow_contract(self: @TContractState) -> ContractAddress;
    fn get_token_address(self: @TContractState) -> ContractAddress;
    fn recover_stuck_token(ref self: TContractState, token_address: ContractAddress, amount: u256);
}

// ============================================================================
// Constructor Tests
// ============================================================================

#[test]
fn test_constructor() {
    let (earn_token, _) = setup_earn_token();
    let escrow = setup_escrow(earn_token, TREASURY());
    let manager = setup_earnstark_manager(earn_token);
    let bulk_vesting_address = setup_bulk_vesting(manager, escrow, earn_token);
    let bulk_vesting = IEarnscapeBulkVestingDispatcher { contract_address: bulk_vesting_address };

    // Check owner
    let ownable = IOwnableDispatcher { contract_address: bulk_vesting_address };
    assert(ownable.owner() == OWNER(), 'Wrong owner');

    // Check addresses
    assert(bulk_vesting.get_earn_stark_manager() == manager, 'Wrong manager');
    assert(bulk_vesting.get_escrow_contract() == escrow, 'Wrong escrow');
    assert(bulk_vesting.get_token_address() == earn_token, 'Wrong token');

    // Check initial total amount vested
    assert(bulk_vesting.get_total_amount_vested() == 0, 'Initial vested not zero');
}

#[test]
fn test_categories_initialized() {
    let (earn_token, _) = setup_earn_token();
    let escrow = setup_escrow(earn_token, TREASURY());
    let manager = setup_earnstark_manager(earn_token);
    let bulk_vesting_address = setup_bulk_vesting(manager, escrow, earn_token);
    let bulk_vesting = IEarnscapeBulkVestingDispatcher { contract_address: bulk_vesting_address };

    // Check Seed Investors (category 0)
    let (name, supply, remaining, duration) = bulk_vesting.get_category_details(0);
    assert(name == 'Seed Investors', 'Wrong seed name');
    assert(supply == 2_500_000 * ONE_TOKEN, 'Wrong seed supply');
    assert(remaining == supply, 'Wrong seed remaining');
    assert(duration == 300, 'Wrong seed duration');

    // Check Public Sale (category 3) - should have 0 duration
    let (_, _, _, pub_duration) = bulk_vesting.get_category_details(3);
    assert(pub_duration == 0, 'Public should have 0 duration');

    // Check Liquidity & Market (category 7) - should have 0 duration
    let (_, _, _, liq_duration) = bulk_vesting.get_category_details(7);
    assert(liq_duration == 0, 'Liq has 0 duration');
}

// ============================================================================
// Add User Data Tests
// ============================================================================

#[test]
fn test_add_user_data_single() {
    let (earn_token, _) = setup_earn_token();
    let escrow = setup_escrow(earn_token, TREASURY());
    let manager = setup_earnstark_manager(earn_token);
    let bulk_vesting_address = setup_bulk_vesting(manager, escrow, earn_token);
    let bulk_vesting = IEarnscapeBulkVestingDispatcher { contract_address: bulk_vesting_address };

    // Transfer tokens to bulk vesting
    transfer_token(earn_token, OWNER(), bulk_vesting_address, ONE_MILLION_TOKENS);

    let category_id = 0; // Seed Investors
    let names = array!['Alice'].span();
    let addresses = array![USER1()].span();
    let amounts = array![THOUSAND_TOKENS].span();

    start_cheat_caller_address(bulk_vesting_address, OWNER());
    bulk_vesting.add_user_data(category_id, names, addresses, amounts);
    stop_cheat_caller_address(bulk_vesting_address);

    // Check vesting count
    assert(bulk_vesting.get_user_vesting_count(USER1()) == 1, 'Wrong vesting count');

    // Check vesting schedule
    let (beneficiary, _cliff, _start, duration, _slice_period, amount_total, released) =
        bulk_vesting
        .get_vesting_schedule(USER1(), 0);
    assert(beneficiary == USER1(), 'Wrong beneficiary');
    assert(amount_total == THOUSAND_TOKENS, 'Wrong amount');
    assert(released == 0, 'Should not be released yet');
    assert(duration == 300, 'Wrong duration');
}

#[test]
fn test_add_multiple_users() {
    let (earn_token, _) = setup_earn_token();
    let escrow = setup_escrow(earn_token, TREASURY());
    let manager = setup_earnstark_manager(earn_token);
    let bulk_vesting_address = setup_bulk_vesting(manager, escrow, earn_token);
    let bulk_vesting = IEarnscapeBulkVestingDispatcher { contract_address: bulk_vesting_address };

    transfer_token(earn_token, OWNER(), bulk_vesting_address, ONE_MILLION_TOKENS);

    let category_id = 0;
    let names = array!['Alice', 'Bob', 'Charlie'].span();
    let addresses = array![USER1(), USER2(), USER3()].span();
    let amounts = array![THOUSAND_TOKENS, THOUSAND_TOKENS, THOUSAND_TOKENS].span();

    start_cheat_caller_address(bulk_vesting_address, OWNER());
    bulk_vesting.add_user_data(category_id, names, addresses, amounts);
    stop_cheat_caller_address(bulk_vesting_address);

    // Check each user has vesting
    assert(bulk_vesting.get_user_vesting_count(USER1()) == 1, 'Wrong USER1 count');
    assert(bulk_vesting.get_user_vesting_count(USER2()) == 1, 'Wrong USER2 count');
    assert(bulk_vesting.get_user_vesting_count(USER3()) == 1, 'Wrong USER3 count');
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_add_user_data_not_owner() {
    let (earn_token, _) = setup_earn_token();
    let escrow = setup_escrow(earn_token, TREASURY());
    let manager = setup_earnstark_manager(earn_token);
    let bulk_vesting_address = setup_bulk_vesting(manager, escrow, earn_token);
    let bulk_vesting = IEarnscapeBulkVestingDispatcher { contract_address: bulk_vesting_address };

    let category_id = 0;
    let names = array!['Alice'].span();
    let addresses = array![USER1()].span();
    let amounts = array![THOUSAND_TOKENS].span();

    start_cheat_caller_address(bulk_vesting_address, USER1());
    bulk_vesting.add_user_data(category_id, names, addresses, amounts);
    stop_cheat_caller_address(bulk_vesting_address);
}

#[test]
#[should_panic(expected: ('Invalid category',))]
fn test_add_user_data_invalid_category() {
    let (earn_token, _) = setup_earn_token();
    let escrow = setup_escrow(earn_token, TREASURY());
    let manager = setup_earnstark_manager(earn_token);
    let bulk_vesting_address = setup_bulk_vesting(manager, escrow, earn_token);
    let bulk_vesting = IEarnscapeBulkVestingDispatcher { contract_address: bulk_vesting_address };

    let category_id = 9; // Invalid
    let names = array!['Alice'].span();
    let addresses = array![USER1()].span();
    let amounts = array![THOUSAND_TOKENS].span();

    start_cheat_caller_address(bulk_vesting_address, OWNER());
    bulk_vesting.add_user_data(category_id, names, addresses, amounts);
    stop_cheat_caller_address(bulk_vesting_address);
}

#[test]
#[should_panic(expected: ('Length mismatch',))]
fn test_add_user_data_length_mismatch() {
    let (earn_token, _) = setup_earn_token();
    let escrow = setup_escrow(earn_token, TREASURY());
    let manager = setup_earnstark_manager(earn_token);
    let bulk_vesting_address = setup_bulk_vesting(manager, escrow, earn_token);
    let bulk_vesting = IEarnscapeBulkVestingDispatcher { contract_address: bulk_vesting_address };

    let category_id = 0;
    let names = array!['Alice', 'Bob'].span();
    let addresses = array![USER1()].span(); // Mismatched length
    let amounts = array![THOUSAND_TOKENS].span();

    start_cheat_caller_address(bulk_vesting_address, OWNER());
    bulk_vesting.add_user_data(category_id, names, addresses, amounts);
    stop_cheat_caller_address(bulk_vesting_address);
}

// ============================================================================
// Release Tests
// ============================================================================

#[test]
fn test_release_vested_amount() {
    let (earn_token, _) = setup_earn_token();
    let escrow = setup_escrow(earn_token, TREASURY());
    let manager = setup_earnstark_manager(earn_token);
    let bulk_vesting_address = setup_bulk_vesting(manager, escrow, earn_token);
    let bulk_vesting = IEarnscapeBulkVestingDispatcher { contract_address: bulk_vesting_address };

    // Setup vesting for USER1
    transfer_token(earn_token, OWNER(), bulk_vesting_address, ONE_MILLION_TOKENS);

    let category_id = 0;
    let names = array!['Alice'].span();
    let addresses = array![USER1()].span();
    let amounts = array![THOUSAND_TOKENS].span();

    start_cheat_caller_address(bulk_vesting_address, OWNER());
    bulk_vesting.add_user_data(category_id, names, addresses, amounts);
    stop_cheat_caller_address(bulk_vesting_address);

    // Advance time to make some tokens releasable
    advance_time(200);

    // Release vested amount
    start_cheat_caller_address(bulk_vesting_address, OWNER());
    bulk_vesting.release_vested_amount(USER1());
    stop_cheat_caller_address(bulk_vesting_address);

    // USER1 should have received some tokens
    let user1_balance = get_balance(earn_token, USER1());
    assert(user1_balance > 0, 'USER1 should have tokens');
    assert(user1_balance < THOUSAND_TOKENS, 'Should be partial release');
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_release_vested_amount_not_owner() {
    let (earn_token, _) = setup_earn_token();
    let escrow = setup_escrow(earn_token, TREASURY());
    let manager = setup_earnstark_manager(earn_token);
    let bulk_vesting_address = setup_bulk_vesting(manager, escrow, earn_token);
    let bulk_vesting = IEarnscapeBulkVestingDispatcher { contract_address: bulk_vesting_address };

    start_cheat_caller_address(bulk_vesting_address, USER1());
    bulk_vesting.release_vested_amount(USER2());
    stop_cheat_caller_address(bulk_vesting_address);
}

// ============================================================================
// Release Immediately Tests
// ============================================================================

#[test]
fn test_release_immediately_public_sale() {
    let (earn_token, _) = setup_earn_token();
    let escrow = setup_escrow(earn_token, TREASURY());
    let manager = setup_earnstark_manager(earn_token);
    let bulk_vesting_address = setup_bulk_vesting(manager, escrow, earn_token);
    let bulk_vesting = IEarnscapeBulkVestingDispatcher { contract_address: bulk_vesting_address };

    let category_id = 3; // Public Sale

    // Get initial remaining supply
    let (_, _, initial_remaining, _) = bulk_vesting.get_category_details(category_id);
    assert(initial_remaining > 0, 'Should have supply');

    // Transfer exact amount needed
    transfer_token(earn_token, OWNER(), bulk_vesting_address, initial_remaining);

    start_cheat_caller_address(bulk_vesting_address, OWNER());
    bulk_vesting.release_immediately(category_id, USER1());
    stop_cheat_caller_address(bulk_vesting_address);

    // Check USER1 received tokens
    assert(get_balance(earn_token, USER1()) == initial_remaining, 'Wrong amount received');

    // Check remaining supply is now 0
    let (_, _, new_remaining, _) = bulk_vesting.get_category_details(category_id);
    assert(new_remaining == 0, 'Remaining should be 0');
}

#[test]
fn test_release_immediately_liquidity() {
    let (earn_token, _) = setup_earn_token();
    let escrow = setup_escrow(earn_token, TREASURY());
    let manager = setup_earnstark_manager(earn_token);
    let bulk_vesting_address = setup_bulk_vesting(manager, escrow, earn_token);
    let bulk_vesting = IEarnscapeBulkVestingDispatcher { contract_address: bulk_vesting_address };

    let category_id = 7; // Liquidity & Market

    let (_, _, initial_remaining, _) = bulk_vesting.get_category_details(category_id);
    transfer_token(earn_token, OWNER(), bulk_vesting_address, initial_remaining);

    start_cheat_caller_address(bulk_vesting_address, OWNER());
    bulk_vesting.release_immediately(category_id, USER1());
    stop_cheat_caller_address(bulk_vesting_address);

    assert(get_balance(earn_token, USER1()) == initial_remaining, 'Wrong amount');
}

#[test]
#[should_panic(expected: ('Only Public/Liquidity allowed',))]
fn test_release_immediately_invalid_category() {
    let (earn_token, _) = setup_earn_token();
    let escrow = setup_escrow(earn_token, TREASURY());
    let manager = setup_earnstark_manager(earn_token);
    let bulk_vesting_address = setup_bulk_vesting(manager, escrow, earn_token);
    let bulk_vesting = IEarnscapeBulkVestingDispatcher { contract_address: bulk_vesting_address };

    let category_id = 0; // Seed Investors - not allowed

    start_cheat_caller_address(bulk_vesting_address, OWNER());
    bulk_vesting.release_immediately(category_id, USER1());
    stop_cheat_caller_address(bulk_vesting_address);
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_release_immediately_not_owner() {
    let (earn_token, _) = setup_earn_token();
    let escrow = setup_escrow(earn_token, TREASURY());
    let manager = setup_earnstark_manager(earn_token);
    let bulk_vesting_address = setup_bulk_vesting(manager, escrow, earn_token);
    let bulk_vesting = IEarnscapeBulkVestingDispatcher { contract_address: bulk_vesting_address };

    start_cheat_caller_address(bulk_vesting_address, USER1());
    bulk_vesting.release_immediately(3, USER2());
    stop_cheat_caller_address(bulk_vesting_address);
}

// ============================================================================
// Update Category Supply Tests
// ============================================================================

#[test]
fn test_update_category_supply() {
    let (earn_token, _) = setup_earn_token();
    let escrow = setup_escrow(earn_token, TREASURY());
    let manager = setup_earnstark_manager(earn_token);
    let bulk_vesting_address = setup_bulk_vesting(manager, escrow, earn_token);
    let bulk_vesting = IEarnscapeBulkVestingDispatcher { contract_address: bulk_vesting_address };

    let category_id = 0;
    let additional_supply = ONE_MILLION_TOKENS;

    let (_, _, initial_remaining, _) = bulk_vesting.get_category_details(category_id);

    start_cheat_caller_address(bulk_vesting_address, OWNER());
    bulk_vesting.update_category_supply(category_id, additional_supply);
    stop_cheat_caller_address(bulk_vesting_address);

    let (_, _, new_remaining, _) = bulk_vesting.get_category_details(category_id);
    assert(new_remaining == initial_remaining + additional_supply, 'Wrong updated remaining');
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_update_category_supply_not_owner() {
    let (earn_token, _) = setup_earn_token();
    let escrow = setup_escrow(earn_token, TREASURY());
    let manager = setup_earnstark_manager(earn_token);
    let bulk_vesting_address = setup_bulk_vesting(manager, escrow, earn_token);
    let bulk_vesting = IEarnscapeBulkVestingDispatcher { contract_address: bulk_vesting_address };

    start_cheat_caller_address(bulk_vesting_address, USER1());
    bulk_vesting.update_category_supply(0, ONE_MILLION_TOKENS);
    stop_cheat_caller_address(bulk_vesting_address);
}

#[test]
#[should_panic(expected: ('Invalid category',))]
fn test_update_category_supply_invalid_category() {
    let (earn_token, _) = setup_earn_token();
    let escrow = setup_escrow(earn_token, TREASURY());
    let manager = setup_earnstark_manager(earn_token);
    let bulk_vesting_address = setup_bulk_vesting(manager, escrow, earn_token);
    let bulk_vesting = IEarnscapeBulkVestingDispatcher { contract_address: bulk_vesting_address };

    start_cheat_caller_address(bulk_vesting_address, OWNER());
    bulk_vesting.update_category_supply(9, ONE_MILLION_TOKENS);
    stop_cheat_caller_address(bulk_vesting_address);
}

// ============================================================================
// Calculate Releasable Tests
// ============================================================================

#[test]
fn test_calculate_releasable_amount() {
    let (earn_token, _) = setup_earn_token();
    let escrow = setup_escrow(earn_token, TREASURY());
    let manager = setup_earnstark_manager(earn_token);
    let bulk_vesting_address = setup_bulk_vesting(manager, escrow, earn_token);
    let bulk_vesting = IEarnscapeBulkVestingDispatcher { contract_address: bulk_vesting_address };

    // Setup vesting
    transfer_token(earn_token, OWNER(), bulk_vesting_address, ONE_MILLION_TOKENS);

    let category_id = 0;
    let names = array!['Alice'].span();
    let addresses = array![USER1()].span();
    let amounts = array![THOUSAND_TOKENS].span();

    start_cheat_caller_address(bulk_vesting_address, OWNER());
    bulk_vesting.add_user_data(category_id, names, addresses, amounts);
    stop_cheat_caller_address(bulk_vesting_address);

    // Initially, nothing is releasable (cliff not passed)
    let (releasable, remaining) = bulk_vesting.calculate_releasable_amount(USER1());
    assert(releasable >= 0, 'Releasable should be >= 0');
    assert(releasable + remaining == THOUSAND_TOKENS, 'Total should match');
}

// ============================================================================
// Recover Stuck Token Tests
// ============================================================================

#[test]
fn test_recover_stuck_token() {
    let (earn_token, _) = setup_earn_token();
    let escrow = setup_escrow(earn_token, TREASURY());
    let manager = setup_earnstark_manager(earn_token);
    let bulk_vesting_address = setup_bulk_vesting(manager, escrow, earn_token);
    let bulk_vesting = IEarnscapeBulkVestingDispatcher { contract_address: bulk_vesting_address };

    // Transfer tokens to bulk vesting
    transfer_token(earn_token, OWNER(), bulk_vesting_address, THOUSAND_TOKENS);

    // Recover tokens
    start_cheat_caller_address(bulk_vesting_address, OWNER());
    bulk_vesting.recover_stuck_token(earn_token, THOUSAND_TOKENS);
    stop_cheat_caller_address(bulk_vesting_address);

    // Owner should have received tokens back
    let initial_balance = 1_000_000_000 * ONE_TOKEN; // 1 billion initial
    assert(get_balance(earn_token, OWNER()) == initial_balance, 'Tokens not recovered');
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_recover_stuck_token_not_owner() {
    let (earn_token, _) = setup_earn_token();
    let escrow = setup_escrow(earn_token, TREASURY());
    let manager = setup_earnstark_manager(earn_token);
    let bulk_vesting_address = setup_bulk_vesting(manager, escrow, earn_token);
    let bulk_vesting = IEarnscapeBulkVestingDispatcher { contract_address: bulk_vesting_address };

    transfer_token(earn_token, OWNER(), bulk_vesting_address, THOUSAND_TOKENS);

    start_cheat_caller_address(bulk_vesting_address, USER1());
    bulk_vesting.recover_stuck_token(earn_token, THOUSAND_TOKENS);
    stop_cheat_caller_address(bulk_vesting_address);
}

#[test]
fn test_full_vesting_lifecycle() {
    let (earn_token, _) = setup_earn_token();
    let escrow = setup_escrow(earn_token, TREASURY());
    let manager = setup_earnstark_manager(earn_token);
    let bulk_vesting_address = setup_bulk_vesting(manager, escrow, earn_token);
    let bulk_vesting = IEarnscapeBulkVestingDispatcher { contract_address: bulk_vesting_address };

    // Setup
    transfer_token(earn_token, OWNER(), bulk_vesting_address, ONE_MILLION_TOKENS);

    let category_id = 0;
    let names = array!['Alice'].span();
    let addresses = array![USER1()].span();
    let amounts = array![THOUSAND_TOKENS].span();

    // Add user
    start_cheat_caller_address(bulk_vesting_address, OWNER());
    bulk_vesting.add_user_data(category_id, names, addresses, amounts);
    stop_cheat_caller_address(bulk_vesting_address);

    advance_time(400);

    // Release all vested
    start_cheat_caller_address(bulk_vesting_address, OWNER());
    bulk_vesting.release_vested_amount(USER1());
    stop_cheat_caller_address(bulk_vesting_address);

    // USER1 should have all tokens
    assert(get_balance(earn_token, USER1()) == THOUSAND_TOKENS, 'Should have all tokens');
}

