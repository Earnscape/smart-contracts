use openzeppelin::access::ownable::interface::{IOwnableDispatcher, IOwnableDispatcherTrait};
use snforge_std::{start_cheat_caller_address, stop_cheat_caller_address};
use starknet::ContractAddress;
use crate::utils::{
    LEVEL_1_COST, LEVEL_2_COST, LEVEL_3_COST, LEVEL_4_COST, LEVEL_5_COST, ONE_TOKEN, OWNER,
    THOUSAND_TOKENS, USER1, USER2, approve_token, get_balance, setup_complete_system,
    setup_earn_token, setup_earnstark_manager, setup_staking, setup_stearn_token, transfer_token,
};

#[starknet::interface]
trait IEarnscapeStaking<TContractState> {
    fn stake(ref self: TContractState, category: felt252, levels: Span<u256>);
    fn stake_with_earn(ref self: TContractState, amount: u256, level: u8, category_to_stake: u8);
    fn unstake(ref self: TContractState);
    fn reshuffle(ref self: TContractState);
    fn get_user_data(
        self: @TContractState, user: ContractAddress,
    ) -> (Array<felt252>, Array<u256>, Array<u256>, Array<ContractAddress>);
    fn get_user_stearn_data(
        self: @TContractState, user: ContractAddress,
    ) -> (Array<felt252>, Array<u256>, Array<u256>, Array<ContractAddress>);
    fn read_level(self: @TContractState, user: ContractAddress, category: felt252) -> u256;
    fn get_staked_amount(self: @TContractState, user: ContractAddress) -> u256;
    fn get_earn_staked_amount(
        self: @TContractState, user: ContractAddress, token: ContractAddress,
    ) -> u256;
    fn check_is_staked_with_earn(
        self: @TContractState, user: ContractAddress, token: ContractAddress,
    ) -> bool;
    fn get_level_costs(self: @TContractState, category: felt252) -> Array<u256>;
    fn set_level_cost(ref self: TContractState, level: u8, cost: u256);
    fn set_level_costs(ref self: TContractState, category: felt252, costs: Span<u256>);
    fn get_level_cost(self: @TContractState, category: felt252, level: u8) -> u256;
    fn transfer_all_earn(ref self: TContractState);
    fn set_earn_stark_manager(ref self: TContractState, new_contract: ContractAddress);
    fn set_vesting_contract(ref self: TContractState, contract: ContractAddress);
    fn set_stearn_contract(ref self: TContractState, contract: ContractAddress);
    fn earn_token(self: @TContractState) -> ContractAddress;
    fn stearn_token(self: @TContractState) -> ContractAddress;
    fn manager(self: @TContractState) -> ContractAddress;
    fn earn_stark_manager(self: @TContractState) -> ContractAddress;
    fn vesting_contract(self: @TContractState) -> ContractAddress;
    fn stearn_contract(self: @TContractState) -> ContractAddress;
    fn transfer_all_tokens(ref self: TContractState, to: ContractAddress);
}

#[starknet::interface]
trait IStEarnToken<TContractState> {
    fn set_vesting_address(ref self: TContractState, vesting: ContractAddress);
    fn set_staking_contract_address(ref self: TContractState, staking_contract: ContractAddress);
}

// ============================================================================
// Constructor Tests
// ============================================================================

#[test]
fn test_constructor() {
    let (earn_token, _) = setup_earn_token();
    let stearn_token = setup_stearn_token();
    let manager = setup_earnstark_manager(earn_token);
    let staking_address = setup_staking(earn_token, stearn_token, manager);
    let staking = IEarnscapeStakingDispatcher { contract_address: staking_address };

    // Check owner
    let ownable = IOwnableDispatcher { contract_address: staking_address };
    assert(ownable.owner() == OWNER(), 'Wrong owner');

    // Check addresses
    assert(staking.earn_token() == earn_token, 'Wrong earn token');
    assert(staking.stearn_token() == stearn_token, 'Wrong stearn token');
    assert(staking.earn_stark_manager() == manager, 'Wrong manager');
}

#[test]
fn test_default_level_costs() {
    let (earn_token, _) = setup_earn_token();
    let stearn_token = setup_stearn_token();
    let manager = setup_earnstark_manager(earn_token);
    let staking_address = setup_staking(earn_token, stearn_token, manager);
    let staking = IEarnscapeStakingDispatcher { contract_address: staking_address };

    // Check level costs for category 'T'
    assert(staking.get_level_cost('T', 1) == LEVEL_1_COST, 'Wrong level 1 cost');
    assert(staking.get_level_cost('T', 2) == LEVEL_2_COST, 'Wrong level 2 cost');
    assert(staking.get_level_cost('T', 3) == LEVEL_3_COST, 'Wrong level 3 cost');
    assert(staking.get_level_cost('T', 4) == LEVEL_4_COST, 'Wrong level 4 cost');
    assert(staking.get_level_cost('T', 5) == LEVEL_5_COST, 'Wrong level 5 cost');
}

// ============================================================================
// Set Level Costs Tests
// ============================================================================

#[test]
fn test_set_level_costs() {
    let (earn_token, _) = setup_earn_token();
    let stearn_token = setup_stearn_token();
    let manager = setup_earnstark_manager(earn_token);
    let staking_address = setup_staking(earn_token, stearn_token, manager);
    let staking = IEarnscapeStakingDispatcher { contract_address: staking_address };

    let new_costs = array![
        200 * ONE_TOKEN, 400 * ONE_TOKEN, 800 * ONE_TOKEN, 1600 * ONE_TOKEN, 3200 * ONE_TOKEN,
    ]
        .span();

    start_cheat_caller_address(staking_address, OWNER());
    staking.set_level_costs('T', new_costs);
    stop_cheat_caller_address(staking_address);

    // Check updated costs
    assert(staking.get_level_cost('T', 1) == 200 * ONE_TOKEN, 'Wrong updated level 1');
    assert(staking.get_level_cost('T', 5) == 3200 * ONE_TOKEN, 'Wrong updated level 5');
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_set_level_costs_not_owner() {
    let (earn_token, _) = setup_earn_token();
    let stearn_token = setup_stearn_token();
    let manager = setup_earnstark_manager(earn_token);
    let staking_address = setup_staking(earn_token, stearn_token, manager);
    let staking = IEarnscapeStakingDispatcher { contract_address: staking_address };

    let new_costs = array![
        200 * ONE_TOKEN, 400 * ONE_TOKEN, 800 * ONE_TOKEN, 1600 * ONE_TOKEN, 3200 * ONE_TOKEN,
    ]
        .span();

    start_cheat_caller_address(staking_address, USER1());
    staking.set_level_costs('T', new_costs);
    stop_cheat_caller_address(staking_address);
}

#[test]
#[should_panic(expected: ('Invalid category',))]
fn test_set_level_costs_invalid_category() {
    let (earn_token, _) = setup_earn_token();
    let stearn_token = setup_stearn_token();
    let manager = setup_earnstark_manager(earn_token);
    let staking_address = setup_staking(earn_token, stearn_token, manager);
    let staking = IEarnscapeStakingDispatcher { contract_address: staking_address };

    let new_costs = array![
        200 * ONE_TOKEN, 400 * ONE_TOKEN, 800 * ONE_TOKEN, 1600 * ONE_TOKEN, 3200 * ONE_TOKEN,
    ]
        .span();

    start_cheat_caller_address(staking_address, OWNER());
    staking.set_level_costs('X', new_costs); // Invalid category
    stop_cheat_caller_address(staking_address);
}

#[test]
#[should_panic(expected: ('Must provide 5 costs',))]
fn test_set_level_costs_wrong_length() {
    let (earn_token, _) = setup_earn_token();
    let stearn_token = setup_stearn_token();
    let manager = setup_earnstark_manager(earn_token);
    let staking_address = setup_staking(earn_token, stearn_token, manager);
    let staking = IEarnscapeStakingDispatcher { contract_address: staking_address };

    let new_costs = array![200 * ONE_TOKEN, 400 * ONE_TOKEN].span(); // Only 2 costs

    start_cheat_caller_address(staking_address, OWNER());
    staking.set_level_costs('T', new_costs);
    stop_cheat_caller_address(staking_address);
}

// ============================================================================
// Stake with EARN Tests
// ============================================================================

#[test]
fn test_stake_with_earn_single_level() {
    // Setup complete system with all cross-references
    let (earn_token, stearn_token, _, _manager, staking_address, vesting_address, _) =
        setup_complete_system();
    let staking = IEarnscapeStakingDispatcher { contract_address: staking_address };

    // Configure vesting and stearn contracts
    let stearn_dispatcher = IStEarnTokenDispatcher { contract_address: stearn_token };
    start_cheat_caller_address(stearn_token, OWNER());
    stearn_dispatcher.set_vesting_address(vesting_address);
    stearn_dispatcher.set_staking_contract_address(staking_address);
    stop_cheat_caller_address(stearn_token);

    start_cheat_caller_address(staking_address, OWNER());
    staking.set_vesting_contract(vesting_address);
    stop_cheat_caller_address(staking_address);

    // Give USER1 tokens and approve
    transfer_token(earn_token, OWNER(), USER1(), THOUSAND_TOKENS);
    approve_token(earn_token, USER1(), staking_address, THOUSAND_TOKENS);

    // Stake level 1 in category 'T'
    let levels = array![1].span();

    start_cheat_caller_address(staking_address, USER1());
    staking.stake('T', levels);
    stop_cheat_caller_address(staking_address);

    // Check staking data
    assert(staking.read_level(USER1(), 'T') == 1, 'Wrong level');
    assert(staking.check_is_staked_with_earn(USER1(), earn_token), 'Should be staked with earn');
    assert(
        staking.get_earn_staked_amount(USER1(), earn_token) == LEVEL_1_COST, 'Wrong staked amount',
    );
}

#[test]
fn test_stake_multiple_levels() {
    // Setup complete system with all cross-references
    let (earn_token, stearn_token, _, _manager, staking_address, vesting_address, _) =
        setup_complete_system();
    let staking = IEarnscapeStakingDispatcher { contract_address: staking_address };

    // Configure vesting and stearn contracts
    let stearn_dispatcher = IStEarnTokenDispatcher { contract_address: stearn_token };
    start_cheat_caller_address(stearn_token, OWNER());
    stearn_dispatcher.set_vesting_address(vesting_address);
    stearn_dispatcher.set_staking_contract_address(staking_address);
    stop_cheat_caller_address(stearn_token);

    start_cheat_caller_address(staking_address, OWNER());
    staking.set_vesting_contract(vesting_address);
    stop_cheat_caller_address(staking_address);

    let total_cost = LEVEL_1_COST + LEVEL_2_COST + LEVEL_3_COST;
    transfer_token(earn_token, OWNER(), USER1(), total_cost);
    approve_token(earn_token, USER1(), staking_address, total_cost);

    // Stake levels 1, 2, 3
    let levels = array![1, 2, 3].span();

    start_cheat_caller_address(staking_address, USER1());
    staking.stake('T', levels);
    stop_cheat_caller_address(staking_address);

    // Should be at level 3
    assert(staking.read_level(USER1(), 'T') == 3, 'Should be level 3');
    assert(staking.get_earn_staked_amount(USER1(), earn_token) == total_cost, 'Wrong total staked');
}

#[test]
#[should_panic(expected: ('No Earn or stEarn to stake',))]
fn test_stake_no_balance() {
    // Setup complete system with all cross-references
    let (_earn_token, stearn_token, _, _manager, staking_address, vesting_address, _) =
        setup_complete_system();
    let staking = IEarnscapeStakingDispatcher { contract_address: staking_address };

    // Configure vesting and stearn contracts
    let stearn_dispatcher = IStEarnTokenDispatcher { contract_address: stearn_token };
    start_cheat_caller_address(stearn_token, OWNER());
    stearn_dispatcher.set_vesting_address(vesting_address);
    stearn_dispatcher.set_staking_contract_address(staking_address);
    stop_cheat_caller_address(stearn_token);

    start_cheat_caller_address(staking_address, OWNER());
    staking.set_vesting_contract(vesting_address);
    stop_cheat_caller_address(staking_address);

    let levels = array![1].span();

    // Try to stake without balance - should panic
    start_cheat_caller_address(staking_address, USER1());
    staking.stake('T', levels);
    stop_cheat_caller_address(staking_address);
}

#[test]
#[should_panic(expected: ('Invalid category',))]
fn test_stake_invalid_category() {
    let (earn_token, _) = setup_earn_token();
    let stearn_token = setup_stearn_token();
    let manager = setup_earnstark_manager(earn_token);
    let staking_address = setup_staking(earn_token, stearn_token, manager);
    let staking = IEarnscapeStakingDispatcher { contract_address: staking_address };

    transfer_token(earn_token, OWNER(), USER1(), THOUSAND_TOKENS);
    approve_token(earn_token, USER1(), staking_address, THOUSAND_TOKENS);

    let levels = array![1].span();

    start_cheat_caller_address(staking_address, USER1());
    staking.stake('X', levels); // Invalid category
    stop_cheat_caller_address(staking_address);
}

// ============================================================================
// Unstake Tests
// ============================================================================

#[test]
fn test_unstake() {
    // Setup complete system with all cross-references
    let (earn_token, stearn_token, _, _manager, staking_address, vesting_address, _) =
        setup_complete_system();
    let staking = IEarnscapeStakingDispatcher { contract_address: staking_address };

    // Configure vesting and stearn contracts
    let stearn_dispatcher = IStEarnTokenDispatcher { contract_address: stearn_token };
    start_cheat_caller_address(stearn_token, OWNER());
    stearn_dispatcher.set_vesting_address(vesting_address);
    stearn_dispatcher.set_staking_contract_address(staking_address);
    stop_cheat_caller_address(stearn_token);

    start_cheat_caller_address(staking_address, OWNER());
    staking.set_vesting_contract(vesting_address);
    stop_cheat_caller_address(staking_address);

    // Setup: Stake first
    transfer_token(earn_token, OWNER(), USER1(), THOUSAND_TOKENS);
    approve_token(earn_token, USER1(), staking_address, THOUSAND_TOKENS);

    let levels = array![1].span();
    start_cheat_caller_address(staking_address, USER1());
    staking.stake('T', levels);
    stop_cheat_caller_address(staking_address);

    // Unstake
    start_cheat_caller_address(staking_address, USER1());
    staking.unstake();
    stop_cheat_caller_address(staking_address);

    // Check user data cleared
    assert(staking.read_level(USER1(), 'T') == 0, 'Level should be reset');
    assert(!staking.check_is_staked_with_earn(USER1(), earn_token), 'Should not be staked');
    assert(staking.get_earn_staked_amount(USER1(), earn_token) == 0, 'Staked amount should be 0');

    // USER1 should have received tokens back
    // Note: Tax may or may not be applied depending on vesting conditions
    let balance = get_balance(earn_token, USER1());
    assert(balance > 0, 'Should have tokens back');
    assert(balance <= THOUSAND_TOKENS, 'Balance exceeds original');
    assert(balance >= THOUSAND_TOKENS / 2, 'Balance too low after unstake');
}

#[test]
#[should_panic(expected: ('No Earn or Stearn staking data',))]
fn test_unstake_no_staking_data() {
    // Setup complete system with all cross-references
    let (_earn_token, stearn_token, _, _manager, staking_address, vesting_address, _) =
        setup_complete_system();
    let staking = IEarnscapeStakingDispatcher { contract_address: staking_address };

    // Configure vesting and stearn contracts
    let stearn_dispatcher = IStEarnTokenDispatcher { contract_address: stearn_token };
    start_cheat_caller_address(stearn_token, OWNER());
    stearn_dispatcher.set_vesting_address(vesting_address);
    stearn_dispatcher.set_staking_contract_address(staking_address);
    stop_cheat_caller_address(stearn_token);

    start_cheat_caller_address(staking_address, OWNER());
    staking.set_vesting_contract(vesting_address);
    stop_cheat_caller_address(staking_address);

    // Try to unstake with no staking data - should panic
    start_cheat_caller_address(staking_address, USER1());
    staking.unstake();
    stop_cheat_caller_address(staking_address);
}

// ============================================================================
// Reshuffle Tests
// ============================================================================

#[test]
fn test_reshuffle() {
    // Setup complete system with all cross-references
    let (earn_token, stearn_token, _, _manager, staking_address, vesting_address, _) =
        setup_complete_system();
    let staking = IEarnscapeStakingDispatcher { contract_address: staking_address };

    // Configure vesting and stearn contracts
    let stearn_dispatcher = IStEarnTokenDispatcher { contract_address: stearn_token };
    start_cheat_caller_address(stearn_token, OWNER());
    stearn_dispatcher.set_vesting_address(vesting_address);
    stearn_dispatcher.set_staking_contract_address(staking_address);
    stop_cheat_caller_address(stearn_token);

    start_cheat_caller_address(staking_address, OWNER());
    staking.set_vesting_contract(vesting_address);
    stop_cheat_caller_address(staking_address);

    // Setup: Stake first
    transfer_token(earn_token, OWNER(), USER1(), THOUSAND_TOKENS);
    approve_token(earn_token, USER1(), staking_address, THOUSAND_TOKENS);

    let levels = array![1].span();
    start_cheat_caller_address(staking_address, USER1());
    staking.stake('T', levels);
    stop_cheat_caller_address(staking_address);

    // Reshuffle
    start_cheat_caller_address(staking_address, USER1());
    staking.reshuffle();
    stop_cheat_caller_address(staking_address);

    // Check user data cleared
    assert(staking.read_level(USER1(), 'T') == 0, 'Level should be reset');

    // USER1 should have received tokens back (with lower reshuffle tax)
    let balance = get_balance(earn_token, USER1());
    assert(balance > 0, 'Should have tokens back');
}

#[test]
#[should_panic(expected: ('No Earn or Stearn staking data',))]
fn test_reshuffle_no_staking_data() {
    // Setup complete system with all cross-references
    let (_earn_token, stearn_token, _, _manager, staking_address, vesting_address, _) =
        setup_complete_system();
    let staking = IEarnscapeStakingDispatcher { contract_address: staking_address };

    // Configure vesting and stearn contracts
    let stearn_dispatcher = IStEarnTokenDispatcher { contract_address: stearn_token };
    start_cheat_caller_address(stearn_token, OWNER());
    stearn_dispatcher.set_vesting_address(vesting_address);
    stearn_dispatcher.set_staking_contract_address(staking_address);
    stop_cheat_caller_address(stearn_token);

    start_cheat_caller_address(staking_address, OWNER());
    staking.set_vesting_contract(vesting_address);
    stop_cheat_caller_address(staking_address);

    // Try to reshuffle with no staking data - should panic
    start_cheat_caller_address(staking_address, USER1());
    staking.reshuffle();
    stop_cheat_caller_address(staking_address);
}

// ============================================================================
// Get User Data Tests
// ============================================================================

#[test]
fn test_get_user_data() {
    // Setup complete system with all cross-references
    let (earn_token, stearn_token, _, _manager, staking_address, vesting_address, _) =
        setup_complete_system();
    let staking = IEarnscapeStakingDispatcher { contract_address: staking_address };

    // Configure vesting and stearn contracts
    let stearn_dispatcher = IStEarnTokenDispatcher { contract_address: stearn_token };
    start_cheat_caller_address(stearn_token, OWNER());
    stearn_dispatcher.set_vesting_address(vesting_address);
    stearn_dispatcher.set_staking_contract_address(staking_address);
    stop_cheat_caller_address(stearn_token);

    start_cheat_caller_address(staking_address, OWNER());
    staking.set_vesting_contract(vesting_address);
    stop_cheat_caller_address(staking_address);

    // Initially empty
    let (categories, _levels, _staked_amounts, _staked_tokens) = staking.get_user_data(USER1());
    assert(categories.len() == 0, 'Should be empty');

    // After staking
    transfer_token(earn_token, OWNER(), USER1(), THOUSAND_TOKENS);
    approve_token(earn_token, USER1(), staking_address, THOUSAND_TOKENS);

    let stake_levels = array![1].span();
    start_cheat_caller_address(staking_address, USER1());
    staking.stake('T', stake_levels);
    stop_cheat_caller_address(staking_address);

    // Check data
    let (categories2, levels2, _staked_amounts2, _staked_tokens2) = staking.get_user_data(USER1());
    assert(categories2.len() == 1, 'Should have 1 category');
    assert(*categories2.at(0) == 'T', 'Wrong category');
    assert(*levels2.at(0) == 1, 'Wrong level');
}

// ============================================================================
// Admin Functions Tests
// ============================================================================

#[test]
fn test_set_earn_stark_manager() {
    let (earn_token, _) = setup_earn_token();
    let stearn_token = setup_stearn_token();
    let manager = setup_earnstark_manager(earn_token);
    let staking_address = setup_staking(earn_token, stearn_token, manager);
    let staking = IEarnscapeStakingDispatcher { contract_address: staking_address };

    start_cheat_caller_address(staking_address, OWNER());
    staking.set_earn_stark_manager(USER1());
    stop_cheat_caller_address(staking_address);

    assert(staking.earn_stark_manager() == USER1(), 'Wrong manager');
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_set_earn_stark_manager_not_owner() {
    let (earn_token, _) = setup_earn_token();
    let stearn_token = setup_stearn_token();
    let manager = setup_earnstark_manager(earn_token);
    let staking_address = setup_staking(earn_token, stearn_token, manager);
    let staking = IEarnscapeStakingDispatcher { contract_address: staking_address };

    start_cheat_caller_address(staking_address, USER1());
    staking.set_earn_stark_manager(USER2());
    stop_cheat_caller_address(staking_address);
}

#[test]
#[should_panic(expected: ('Invalid contract address',))]
fn test_set_earn_stark_manager_zero_address() {
    let (earn_token, _) = setup_earn_token();
    let stearn_token = setup_stearn_token();
    let manager = setup_earnstark_manager(earn_token);
    let staking_address = setup_staking(earn_token, stearn_token, manager);
    let staking = IEarnscapeStakingDispatcher { contract_address: staking_address };

    let zero: ContractAddress = 0.try_into().unwrap();
    start_cheat_caller_address(staking_address, OWNER());
    staking.set_earn_stark_manager(zero);
    stop_cheat_caller_address(staking_address);
}

#[test]
fn test_set_vesting_contract() {
    let (earn_token, _) = setup_earn_token();
    let stearn_token = setup_stearn_token();
    let manager = setup_earnstark_manager(earn_token);
    let staking_address = setup_staking(earn_token, stearn_token, manager);
    let staking = IEarnscapeStakingDispatcher { contract_address: staking_address };

    start_cheat_caller_address(staking_address, OWNER());
    staking.set_vesting_contract(USER1());
    stop_cheat_caller_address(staking_address);

    assert(staking.vesting_contract() == USER1(), 'Wrong vesting');
}

#[test]
fn test_set_stearn_contract() {
    let (earn_token, _) = setup_earn_token();
    let stearn_token = setup_stearn_token();
    let manager = setup_earnstark_manager(earn_token);
    let staking_address = setup_staking(earn_token, stearn_token, manager);
    let staking = IEarnscapeStakingDispatcher { contract_address: staking_address };

    start_cheat_caller_address(staking_address, OWNER());
    staking.set_stearn_contract(USER1());
    stop_cheat_caller_address(staking_address);

    assert(staking.stearn_contract() == USER1(), 'Wrong stearn');
}

#[test]
fn test_transfer_all_tokens() {
    let (earn_token, _) = setup_earn_token();
    let stearn_token = setup_stearn_token();
    let manager = setup_earnstark_manager(earn_token);
    let staking_address = setup_staking(earn_token, stearn_token, manager);
    let staking = IEarnscapeStakingDispatcher { contract_address: staking_address };

    // Transfer some tokens to staking contract
    transfer_token(earn_token, OWNER(), staking_address, THOUSAND_TOKENS);

    start_cheat_caller_address(staking_address, OWNER());
    staking.transfer_all_tokens(USER1());
    stop_cheat_caller_address(staking_address);

    // USER1 should have received tokens
    assert(get_balance(earn_token, USER1()) == THOUSAND_TOKENS, 'Tokens not transferred');
    assert(get_balance(earn_token, staking_address) == 0, 'Contract should be empty');
}

// ============================================================================
// Complex Scenarios
// ============================================================================

#[test]
fn test_stake_multiple_categories() {
    // Setup complete system with all cross-references
    let (earn_token, stearn_token, _, _manager, staking_address, vesting_address, _) =
        setup_complete_system();
    let staking = IEarnscapeStakingDispatcher { contract_address: staking_address };

    // Configure vesting and stearn contracts
    let stearn_dispatcher = IStEarnTokenDispatcher { contract_address: stearn_token };
    start_cheat_caller_address(stearn_token, OWNER());
    stearn_dispatcher.set_vesting_address(vesting_address);
    stearn_dispatcher.set_staking_contract_address(staking_address);
    stop_cheat_caller_address(stearn_token);

    start_cheat_caller_address(staking_address, OWNER());
    staking.set_vesting_contract(vesting_address);
    stop_cheat_caller_address(staking_address);

    let total_cost = LEVEL_1_COST * 3;
    transfer_token(earn_token, OWNER(), USER1(), total_cost);
    approve_token(earn_token, USER1(), staking_address, total_cost);

    let levels = array![1].span();

    start_cheat_caller_address(staking_address, USER1());
    staking.stake('T', levels);
    staking.stake('R', levels);
    staking.stake('A', levels);
    stop_cheat_caller_address(staking_address);

    // Check all categories staked
    assert(staking.read_level(USER1(), 'T') == 1, 'T not staked');
    assert(staking.read_level(USER1(), 'R') == 1, 'R not staked');
    assert(staking.read_level(USER1(), 'A') == 1, 'A not staked');

    let (categories, _, _, _) = staking.get_user_data(USER1());
    assert(categories.len() == 3, 'Should have 3 categories');
}

// ============================================================================
// Ownership Tests
// ============================================================================

#[test]
fn test_transfer_ownership() {
    let (earn_token, _) = setup_earn_token();
    let stearn_token = setup_stearn_token();
    let manager = setup_earnstark_manager(earn_token);
    let staking_address = setup_staking(earn_token, stearn_token, manager);
    let staking = IEarnscapeStakingDispatcher { contract_address: staking_address };
    let ownable = IOwnableDispatcher { contract_address: staking_address };

    start_cheat_caller_address(staking_address, OWNER());
    ownable.transfer_ownership(USER1());
    stop_cheat_caller_address(staking_address);

    assert(ownable.owner() == USER1(), 'Ownership not transferred');

    // New owner can perform owner actions
    start_cheat_caller_address(staking_address, USER1());
    staking.set_earn_stark_manager(USER2());
    stop_cheat_caller_address(staking_address);

    assert(staking.earn_stark_manager() == USER2(), 'New owner cannot set manager');
}

