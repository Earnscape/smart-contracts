// Complete integration tests — single-file, in-place fixes only.
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use snforge_std::{
    start_cheat_block_timestamp_global, start_cheat_caller_address,
    stop_cheat_block_timestamp_global, stop_cheat_caller_address,
};
use starknet::ContractAddress;
use crate::utils::{
    LEVEL_1_COST, LEVEL_2_COST, ONE_TOKEN, OWNER, THOUSAND_TOKENS, USER1, USER2, USER3,
    ADMIN, ZERO_ADDRESS,
    approve_token, get_balance, setup_complete_system, transfer_token, print_step, print_success,
    print_check, print_error_test, print_divider,
};

// ---------------------------------------------------------------------------
// Small verification helpers
// ---------------------------------------------------------------------------

fn verify_vesting_balances(
    vesting: IVestingDispatcher,
    user: ContractAddress,
) -> (u256, u256) {
    let earn_bal = vesting.get_earn_balance(user);
    let stearn_bal = vesting.get_stearn_balance(user);
    print_check('EARN_Balance', earn_bal);
    print_check('stEARN_Balance', stearn_bal);
    (earn_bal, stearn_bal)
}

fn verify_releasable_amount(
    vesting: IVestingDispatcher,
    user: ContractAddress,
) -> (u256, u256) {
    let (releasable, locked) = vesting.calculate_releasable_amount(user);
    print_check('Releasable', releasable);
    print_check('Locked', locked);
    (releasable, locked)
}

fn verify_staking_data(
    staking: IEarnscapeStakingDispatcher,
    user: ContractAddress,
    category: felt252,
) {
    let level = staking.read_level(user, category);
    print_check('Staking_Level', level.into());

    // Annotate the tuple type to avoid ambiguous `.len()` / `.at()` method calls
    let (categories, _levels, _staked_amounts, _) : (Array<felt252>, Array<u256>, Array<u256>, u32) = staking.get_user_data(user);
    println!("  CHECK: Categories_Count = {}", categories.len());
}

// ---------------------------------------------------------------------------
// Flow implementations (kept simple and defensive)
// ---------------------------------------------------------------------------

fn execute_basic_flow(
    earn_token: ContractAddress,
    stearn_token: ContractAddress,
    manager_address: ContractAddress,
    staking_address: ContractAddress,
    vesting_address: ContractAddress,
    user: ContractAddress,
    user_name: felt252,
    use_unstake: bool,
) {
    print_divider('FLOW_START');
    println!("User: {}", user_name);

    let manager = IEarnSTARKManagerDispatcher { contract_address: manager_address };
    let vesting = IVestingDispatcher { contract_address: vesting_address };
    let staking = IEarnscapeStakingDispatcher { contract_address: staking_address };

    // deposit
    print_step(1, 'Deposit_EARN_to_Vesting');
    let deposit_amount = 1000 * ONE_TOKEN;
    start_cheat_caller_address(manager_address, OWNER());
    manager.earn_deposit_to_vesting(user, deposit_amount);
    stop_cheat_caller_address(manager_address);
    print_success('Deposit_Complete');

    // verify balances
    print_step(2, 'Verify_Vesting_Balances');
    let (earn_bal, stearn_bal) = verify_vesting_balances(vesting, user);
    assert(earn_bal == deposit_amount, 'EARN balance mismatch');
    assert(stearn_bal == deposit_amount, 'stEARN balance mismatch');

    // check releasable
    print_step(3, 'Check_Releasable_Amount');
    let (rel, _lock) = verify_releasable_amount(vesting, user);
    assert(rel > 0, 'Should have releasable amount');

    // approve & stake
    print_step(4, 'Approve_stEARN_for_Staking');
    approve_token(stearn_token, user, staking_address, LEVEL_1_COST);
    print_success('Approval_Complete');

    print_step(5, 'Stake_Level1_CategoryT');
    let levels = array![1].span();
    start_cheat_caller_address(staking_address, user);
    staking.stake('T', levels);
    stop_cheat_caller_address(staking_address);
    print_success('Staking_Complete');

    print_step(6, 'Verify_Staking_Data');
    verify_staking_data(staking, user, 'T');
    let lvl = staking.read_level(user, 'T');
    assert(lvl == 1, 'Level should be 1');

    // release
    print_step(7, 'Release_Vested_Amount');
    start_cheat_caller_address(vesting_address, user);
    vesting.release_vested_amount(user);
    stop_cheat_caller_address(vesting_address);
    print_success('Release_Complete');

    // unstake or reshuffle
    if use_unstake {
        print_step(8, 'Unstake');
        start_cheat_caller_address(staking_address, user);
        staking.unstake();
        stop_cheat_caller_address(staking_address);
        print_success('Unstake_Complete');
    } else {
        print_step(8, 'Reshuffle');
        start_cheat_caller_address(staking_address, user);
        staking.reshuffle();
        stop_cheat_caller_address(staking_address);
        print_success('Reshuffle_Complete');
    }

    // final checks
    verify_staking_data(staking, user, 'T');
    let level_after = staking.read_level(user, 'T');
    assert(level_after == 0, 'Level should be 0');
    verify_vesting_balances(vesting, user);
    print_divider('FLOW_COMPLETED');
}

fn execute_user3_tip_flow(
    earn_token: ContractAddress,
    stearn_token: ContractAddress,
    manager_address: ContractAddress,
    staking_address: ContractAddress,
    vesting_address: ContractAddress,
) {
    print_divider('USER3_TIP_FLOW_START');
    let manager = IEarnSTARKManagerDispatcher { contract_address: manager_address };
    let vesting = IVestingDispatcher { contract_address: vesting_address };
    let staking = IEarnscapeStakingDispatcher { contract_address: staking_address };
    let user3 = USER3();
    let user1 = USER1();

    // deposit
    print_step(1, 'Deposit_EARN_to_USER3');
    let deposit_amount = 2000 * ONE_TOKEN;
    start_cheat_caller_address(manager_address, OWNER());
    manager.earn_deposit_to_vesting(user3, deposit_amount);
    stop_cheat_caller_address(manager_address);
    print_success('Deposit_Complete');

    // approve & stake
    approve_token(stearn_token, user3, staking_address, LEVEL_2_COST);
    let levels = array![1, 2].span();
    start_cheat_caller_address(staking_address, user3);
    staking.stake('R', levels);
    stop_cheat_caller_address(staking_address);
    print_success('USER3_Staked_Level2');

    // tip
    print_step(8, 'USER3_Give_Tip_to_USER1');
    let tip_amount = 100 * ONE_TOKEN;
    start_cheat_caller_address(vesting_address, user3);
    vesting.give_a_tip(user1, tip_amount);
    stop_cheat_caller_address(vesting_address);
    print_success('Tip_Sent');

    // force release for user1
    start_cheat_caller_address(vesting_address, user1);
    vesting.force_release_vested_amount(user1);
    stop_cheat_caller_address(vesting_address);
    print_success('USER1_Force_Release_Done');

    // unstake user3
    start_cheat_caller_address(staking_address, user3);
    staking.unstake();
    stop_cheat_caller_address(staking_address);
    print_success('USER3_Unstaked');
    print_divider('USER3_TIP_FLOW_DONE');
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[test]
fn test_complete_integration_flow() {
    print_divider('COMPLETE_INTEGRATION_TEST');
    print_step(0, 'Setup_System');
    let (earn_token, stearn_token, _escrow, manager_address, staking_address, vesting_address, _bulk_vesting) = setup_complete_system();

    // configure tokens & staking
    let stearn_dispatcher = IStEarnTokenDispatcher { contract_address: stearn_token };
    start_cheat_caller_address(stearn_token, OWNER());
    stearn_dispatcher.set_vesting_address(vesting_address);
    stearn_dispatcher.set_staking_contract_address(staking_address);
    stop_cheat_caller_address(stearn_token);

    let staking = IEarnscapeStakingDispatcher { contract_address: staking_address };
    start_cheat_caller_address(staking_address, OWNER());
    staking.set_vesting_contract(vesting_address);
    stop_cheat_caller_address(staking_address);

    // seed manager
    transfer_token(earn_token, OWNER(), manager_address, 20000 * ONE_TOKEN);

    start_cheat_block_timestamp_global(1000);
    execute_user3_tip_flow(earn_token, stearn_token, manager_address, staking_address, vesting_address);
    stop_cheat_block_timestamp_global();
    print_divider('USER3_TEST_COMPLETED');
}

#[test]
fn test_user1_reshuffle_flow() {
    print_divider('USER1_RESHUFFLE_TEST');
    let (earn_token, stearn_token, _escrow, manager_address, staking_address, vesting_address, _bulk_vesting) = setup_complete_system();
    let stearn_dispatcher = IStEarnTokenDispatcher { contract_address: stearn_token };
    start_cheat_caller_address(stearn_token, OWNER());
    stearn_dispatcher.set_vesting_address(vesting_address);
    stearn_dispatcher.set_staking_contract_address(staking_address);
    stop_cheat_caller_address(stearn_token);
    let staking = IEarnscapeStakingDispatcher { contract_address: staking_address };
    start_cheat_caller_address(staking_address, OWNER());
    staking.set_vesting_contract(vesting_address);
    stop_cheat_caller_address(staking_address);
    transfer_token(earn_token, OWNER(), manager_address, 10000 * ONE_TOKEN);
    start_cheat_block_timestamp_global(1000);
    execute_basic_flow(earn_token, stearn_token, manager_address, staking_address, vesting_address, USER1(), 'USER1', false);
    stop_cheat_block_timestamp_global();
    print_divider('USER1_TEST_COMPLETED');
}

#[test]
fn test_user2_unstake_flow() {
    print_divider('USER2_UNSTAKE_TEST');
    let (earn_token, stearn_token, _escrow, manager_address, staking_address, vesting_address, _bulk_vesting) = setup_complete_system();
    let stearn_dispatcher = IStEarnTokenDispatcher { contract_address: stearn_token };
    start_cheat_caller_address(stearn_token, OWNER());
    stearn_dispatcher.set_vesting_address(vesting_address);
    stearn_dispatcher.set_staking_contract_address(staking_address);
    stop_cheat_caller_address(stearn_token);
    let staking = IEarnscapeStakingDispatcher { contract_address: staking_address };
    start_cheat_caller_address(staking_address, OWNER());
    staking.set_vesting_contract(vesting_address);
    stop_cheat_caller_address(staking_address);
    transfer_token(earn_token, OWNER(), manager_address, 10000 * ONE_TOKEN);
    start_cheat_block_timestamp_global(1000);
    execute_basic_flow(earn_token, stearn_token, manager_address, staking_address, vesting_address, USER2(), 'USER2', true);
    stop_cheat_block_timestamp_global();
    print_divider('USER2_TEST_COMPLETED');
}
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use snforge_std::{
    start_cheat_block_timestamp_global, start_cheat_caller_address,
    stop_cheat_block_timestamp_global, stop_cheat_caller_address,
};
use starknet::ContractAddress;
use crate::utils::{
    LEVEL_1_COST, LEVEL_2_COST, ONE_TOKEN, OWNER, THOUSAND_TOKENS, USER1, USER2, USER3, ADMIN, ZERO_ADDRESS,
    approve_token, get_balance, setup_complete_system, transfer_token, print_step, print_success,
    print_check, print_error_test, print_divider,
};

// Local minimal interfaces used by the tests (keeps tests decoupled from contract
// module names and matches the pattern used elsewhere in this repo).
#[starknet::interface]
trait IEarnSTARKManager<TContractState> {
    fn earn_deposit_to_vesting(ref self: TContractState, beneficiary: ContractAddress, amount: u256);
    fn get_earns_balance(self: @TContractState) -> u256;
    fn vesting(self: @TContractState) -> ContractAddress;
}

#[starknet::interface]
trait IStEarnToken<TContractState> {
    fn set_vesting_address(ref self: TContractState, vesting: ContractAddress);
    fn set_staking_contract_address(ref self: TContractState, staking_contract: ContractAddress);
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
}

#[starknet::interface]
trait IEarnscapeStaking<TContractState> {

// Main Flow Execution Functions
// ============================================================================

fn execute_basic_flow(
    earn_token: ContractAddress,
    stearn_token: ContractAddress,
    manager_address: ContractAddress,
    staking_address: ContractAddress,
    vesting_address: ContractAddress,
    user: ContractAddress,
    user_name: felt252,
    use_unstake: bool,
) {
    print_divider('FLOW_START');
    println!("User: {}", user_name);
    
    let manager = IEarnSTARKManagerDispatcher { contract_address: manager_address };
    let vesting = IVestingDispatcher { contract_address: vesting_address };
    let staking = IEarnscapeStakingDispatcher { contract_address: staking_address };
    
    // STEP 1: Deposit to Vesting
    print_step(1, 'Deposit_EARN_to_Vesting');
    let deposit_amount = 1000 * ONE_TOKEN;
    
    start_cheat_caller_address(manager_address, OWNER());
    manager.earn_deposit_to_vesting(user, deposit_amount);
    stop_cheat_caller_address(manager_address);
    print_success('Deposit_Complete');
    
    // STEP 2: Verify balances
    print_step(2, 'Verify_Vesting_Balances');
    let (earn_bal, stearn_bal) = verify_vesting_balances(vesting, user);
    assert(earn_bal == deposit_amount, 'EARN balance mismatch');
    assert(stearn_bal == deposit_amount, 'stEARN balance mismatch');
    
    // STEP 3: Check releasable amount
    print_step(3, 'Check_Releasable_Amount');
    let (rel, _lock) = verify_releasable_amount(vesting, user);
    assert(rel > 0, 'Should have releasable amount');
    
    // STEP 4: Approve stEARN
    print_step(4, 'Approve_stEARN_for_Staking');
    approve_token(stearn_token, user, staking_address, LEVEL_1_COST);
    print_success('Approval_Complete');
    
    // STEP 5: Stake Level 1, Category T
    print_step(5, 'Stake_Level1_CategoryT');
    let levels = array![1].span();
    
    start_cheat_caller_address(staking_address, user);
        fn set_vesting_contract(ref self: TContractState, contract: ContractAddress);
        fn stake(ref self: TContractState, category: felt252, levels: Span<u8>);
        fn unstake(ref self: TContractState);
        fn reshuffle(ref self: TContractState);
        fn read_level(self: @TContractState, user: ContractAddress, category: felt252) -> u256;
        fn get_user_data(self: @TContractState, user: ContractAddress) -> (Array<felt252>, Array<u256>, Array<u256>, u32);
        fn get_level_cost(self: @TContractState, category: felt252, level: u8) -> u256;
        fn change_staking_token(ref self: TContractState, token: ContractAddress) -> Result<(), u64>;
    }

    // Main Flow Execution Functions
    // ============================================================================

    staking.stake('T', levels);
    stop_cheat_caller_address(staking_address);
    print_success('Staking_Complete');
    
    // STEP 6: Verify staking
    print_step(6, 'Verify_Staking_Data');
    verify_staking_data(staking, user, 'T');
    let level = staking.read_level(user, 'T');
    assert(level == 1, 'Level should be 1');
    
    // STEP 7: Release vested amount
    print_step(7, 'Release_Vested_Amount');
    start_cheat_caller_address(vesting_address, user);
    vesting.release_vested_amount(user);
    stop_cheat_caller_address(vesting_address);
    print_success('Release_Complete');
    
    // STEP 8: Verify after release
    print_step(8, 'Verify_After_Release');
    verify_releasable_amount(vesting, user);
    
    // STEP 9: Unstake or Reshuffle
    if use_unstake {
        print_step(9, 'Unstake');
        start_cheat_caller_address(staking_address, user);
        staking.unstake();
        stop_cheat_caller_address(staking_address);
        print_success('Unstake_Complete');
    } else {
        assert(earn_bal == deposit_amount, 'EARN balance mismatch');
        assert(stearn_bal == deposit_amount, 'stEARN balance mismatch');
        staking.reshuffle();
        stop_cheat_caller_address(staking_address);
        print_success('Reshuffle_Complete');
    }
        assert(rel > 0, 'Should have releasable amount');
    // STEP 10: Verify cleared
    print_step(10, 'Verify_Data_Cleared');
    verify_staking_data(staking, user, 'T');
    let level_after = staking.read_level(user, 'T');
    assert(level_after == 0, 'Level should be 0');
    
    // STEP 11: Check balances
    print_step(11, 'Check_Final_Balances');
    verify_vesting_balances(vesting, user);
    
    // STEP 12: Force release
    print_step(12, 'Force_Release_Vested');
    start_cheat_caller_address(vesting_address, user);
    vesting.force_release_vested_amount(user);
    stop_cheat_caller_address(vesting_address);
    print_success('Force_Release_Complete');
    
    // STEP 13: Final verification
    print_step(13, 'Final_Verification');
        assert(level == 1, 'Level should be 1');
    verify_vesting_balances(vesting, user);
    
    print_divider('FLOW_COMPLETED');
}

fn execute_user3_tip_flow(
    earn_token: ContractAddress,
    stearn_token: ContractAddress,
    manager_address: ContractAddress,
    staking_address: ContractAddress,
    vesting_address: ContractAddress,
) {
    print_divider('USER3_TIP_FLOW_START');
    println!("User: USER3");
    
    let manager = IEarnSTARKManagerDispatcher { contract_address: manager_address };
    let vesting = IVestingDispatcher { contract_address: vesting_address };
    let staking = IEarnscapeStakingDispatcher { contract_address: staking_address };
    let user3 = USER3();
    let user1 = USER1();
    
    // STEP 1: Deposit for USER3
    print_step(1, 'Deposit_EARN_to_USER3');
    let deposit_amount = 2000 * ONE_TOKEN;
    
    start_cheat_caller_address(manager_address, OWNER());
    manager.earn_deposit_to_vesting(user3, deposit_amount);
    stop_cheat_caller_address(manager_address);
    print_success('Deposit_Complete');
    
    // STEP 2: Verify USER3 balances
        assert(level_after == 0, 'Level should be 0');
    let (earn_bal, stearn_bal) = verify_vesting_balances(vesting, user3);
    assert(earn_bal == deposit_amount, 'USER3 EARN mismatch');
    assert(stearn_bal == deposit_amount, 'USER3 stEARN mismatch');
    
    // STEP 3: Approve and Stake for USER3
    print_step(3, 'Stake_USER3_CategoryR');
    approve_token(stearn_token, user3, staking_address, LEVEL_2_COST);
    
    let levels = array![1, 2].span();
    start_cheat_caller_address(staking_address, user3);
    staking.stake('R', levels);
    stop_cheat_caller_address(staking_address);
    print_success('USER3_Staked_Level2');
    
    // STEP 4: Verify USER3 staking
    print_step(4, 'Verify_USER3_Staking');
    verify_staking_data(staking, user3, 'R');
    let level = staking.read_level(user3, 'R');
    assert(level == 2, 'Should be level 2');
    
    // STEP 5: Release vested for USER3
    print_step(5, 'Release_USER3_Vested');
    start_cheat_caller_address(vesting_address, user3);
    vesting.release_vested_amount(user3);
    stop_cheat_caller_address(vesting_address);
    print_success('Release_Complete');
    
    // STEP 6: Check USER1 balances BEFORE tip
    print_step(6, 'USER1_Balance_BEFORE_Tip');
    let (user1_earn_before, user1_stearn_before) = verify_vesting_balances(vesting, user1);
    let (user1_rel_before, user1_lock_before) = verify_releasable_amount(vesting, user1);
    
    // STEP 7: Check USER3 balances BEFORE tip
    print_step(7, 'USER3_Balance_BEFORE_Tip');
    let (user3_earn_before, user3_stearn_before) = verify_vesting_balances(vesting, user3);
    
    // STEP 8: USER3 gives tip to USER1
    print_step(8, 'USER3_Give_Tip_to_USER1');
    let tip_amount = 100 * ONE_TOKEN;
    
    start_cheat_caller_address(vesting_address, user3);
    vesting.give_a_tip(user1, tip_amount);
    stop_cheat_caller_address(vesting_address);
    print_success('Tip_Sent');
    
    // STEP 9: Check USER1 balances AFTER tip
    print_step(9, 'USER1_Balance_AFTER_Tip');
    let (user1_earn_after, user1_stearn_after) = verify_vesting_balances(vesting, user1);
    let (user1_rel_after, user1_lock_after) = verify_releasable_amount(vesting, user1);
    
    println!("\n  COMPARISON USER1:");
    println!("    EARN: {} -> {}", user1_earn_before, user1_earn_after);
    println!("    stEARN: {} -> {}", user1_stearn_before, user1_stearn_after);
    println!("    Releasable: {} -> {}", user1_rel_before, user1_rel_after);
    println!("    Locked: {} -> {}", user1_lock_before, user1_lock_after);
    
    // STEP 10: Check USER3 balances AFTER tip
    print_step(10, 'USER3_Balance_AFTER_Tip');
    let (user3_earn_after, user3_stearn_after) = verify_vesting_balances(vesting, user3);
    
    println!("\n  COMPARISON USER3:");
    println!("    EARN: {} -> {}", user3_earn_before, user3_earn_after);
    println!("    stEARN: {} -> {}", user3_stearn_before, user3_stearn_after);
    
    // STEP 11: USER1 force release after receiving tip
    print_step(11, 'USER1_Force_Release_After_Tip');
    start_cheat_caller_address(vesting_address, user1);
    vesting.force_release_vested_amount(user1);
    stop_cheat_caller_address(vesting_address);
    print_success('USER1_Force_Release_Done');
    
    // STEP 12: Verify USER1 final state
    print_step(12, 'USER1_Final_State');
    verify_vesting_balances(vesting, user1);
    verify_releasable_amount(vesting, user1);
    
    // STEP 13: USER3 unstakes from first staking
    print_step(13, 'USER3_Unstake_First_Position');
    start_cheat_caller_address(staking_address, user3);
    staking.unstake();
    stop_cheat_caller_address(staking_address);
    print_success('USER3_Unstaked');
    
    // STEP 14: Verify USER3 data cleared
    print_step(14, 'Verify_USER3_Data_Cleared');
    verify_staking_data(staking, user3, 'R');
    let level_after = staking.read_level(user3, 'R');
    assert(level_after == 0, 'Level should be 0');
    
    print_divider('USER3_TIP_FLOW_PART1_DONE');
    
    // ========================================================================
    // PART 2: USER3 Stakes Again with Different Category and Error Testing
    // ========================================================================
    
    print_divider('USER3_SECOND_STAKE');
    
    // STEP 15: Deposit more for USER3
    print_step(15, 'Deposit_More_for_USER3');
    let second_deposit = 1500 * ONE_TOKEN;
    
    start_cheat_caller_address(manager_address, OWNER());
    manager.earn_deposit_to_vesting(user3, second_deposit);
    stop_cheat_caller_address(manager_address);
    print_success('Second_Deposit_Complete');
    
    // STEP 16: Verify balances
    print_step(16, 'Verify_USER3_New_Balances');
    verify_vesting_balances(vesting, user3);
    
    // STEP 17: Approve for different category/level
    print_step(17, 'Stake_CategoryA_Level3');
    let level3_cost = LEVEL_1_COST + LEVEL_2_COST + staking.get_level_cost('A', 3);
    approve_token(stearn_token, user3, staking_address, level3_cost);
    
    let levels_a = array![1, 2, 3].span();
    start_cheat_caller_address(staking_address, user3);
    staking.stake('A', levels_a);
    stop_cheat_caller_address(staking_address);
    print_success('USER3_Staked_CategoryA_Level3');
    
    // STEP 18: Verify new staking
    print_step(18, 'Verify_CategoryA_Staking');
    verify_staking_data(staking, user3, 'A');
    let level_a = staking.read_level(user3, 'A');
    assert(level_a == 3, 'Should be level 3');
    
    // Error test with invalid category
    let invalid_levels = array![1].span();
    start_cheat_caller_address(staking_address, user3);
    let result = staking.stake('X', invalid_levels);
    stop_cheat_caller_address(staking_address);
    assert(result.is_err(), 'Should fail with invalid category');
    println!("  SKIP: Error test commented (would panic)");
    
    // STEP 20: Error Test - Try to stake without approval
    print_step(20, 'ERROR_TEST_No_Approval');
    print_error_test('Attempt_stake_without_approval');
    println!("  SKIP: Would require fresh user");
    
        // Error test with invalid token address
    start_cheat_caller_address(staking_address, ADMIN());
    let result_change = staking.change_staking_token(ZERO_ADDRESS());
    assert(result_change.is_err(), 'Should fail changing to invalid token');
    
    let balance_before_stake = stearn_dispatcher.balance_of(user3);
    let category = 'X1';
    let selected_levels = array![1, 1].span();
    start_cheat_caller_address(staking_address, user3);
    let result_stake = staking.stake(category, selected_levels);
    stop_cheat_caller_address(staking_address);
    assert(result_stake.is_err(), 'Should fail staking with invalid token');
    
    // STEP 22: Release vested for USER3
    print_step(22, 'Release_USER3_Vested_Again');
    start_cheat_caller_address(vesting_address, user3);
    vesting.release_vested_amount(user3);
    stop_cheat_caller_address(vesting_address);
    print_success('Release_Complete');
    
    // STEP 23: Check data before unstake
    print_step(23, 'Before_Final_Unstake');
    verify_staking_data(staking, user3, 'A');
    verify_vesting_balances(vesting, user3);
    
    // STEP 24: USER3 unstakes second position
    print_step(24, 'USER3_Final_Unstake');
    start_cheat_caller_address(staking_address, user3);
    staking.unstake();
    stop_cheat_caller_address(staking_address);
    print_success('Final_Unstake_Complete');
    
    // STEP 25: Verify final cleared state
    print_step(25, 'Verify_Final_Cleared_State');
    verify_staking_data(staking, user3, 'A');
    let final_level = staking.read_level(user3, 'A');
    assert(final_level == 0, 'Final level should be 0');
    
    // STEP 26: Check final balances
    print_step(26, 'USER3_Final_Balances');
    verify_vesting_balances(vesting, user3);
    verify_releasable_amount(vesting, user3);
    
    print_divider('USER3_COMPLETE_FLOW_DONE');
}

// ============================================================================
// Main Integration Tests
// ============================================================================

#[test]
fn test_complete_integration_flow() {
    println!("\n");
    print_divider('COMPLETE_INTEGRATION_TEST');
    
    // Setup system
    print_step(0, 'Setup_System');
    let (earn_token, stearn_token, _escrow, manager_address, 
         staking_address, vesting_address, _bulk_vesting) = setup_complete_system();
    
    // Configure contracts
    let stearn_dispatcher = IStEarnTokenDispatcher { contract_address: stearn_token };
    start_cheat_caller_address(stearn_token, OWNER());
    stearn_dispatcher.set_vesting_address(vesting_address);
    stearn_dispatcher.set_staking_contract_address(staking_address);
    stop_cheat_caller_address(stearn_token);
    
    let staking = IEarnscapeStakingDispatcher { contract_address: staking_address };
    start_cheat_caller_address(staking_address, OWNER());
    staking.set_vesting_contract(vesting_address);
    stop_cheat_caller_address(staking_address);
    
    // Transfer tokens to manager for USER3 operations
    transfer_token(earn_token, OWNER(), manager_address, 20000 * ONE_TOKEN);
    
    // Set initial timestamp for vesting operations
    start_cheat_block_timestamp_global(1000);
    
    // Execute USER3 complete flow (tip + advanced features)
    execute_user3_tip_flow(
        earn_token,
        stearn_token,
        manager_address,
        staking_address,
        vesting_address,
    );
    
    // Clean up timestamp
    stop_cheat_block_timestamp_global();
    
    print_divider('USER3_TEST_COMPLETED');
}

// ============================================================================
// Additional Error Testing Functions (Optional)
// ============================================================================

#[test]
#[should_panic(expected: ('Invalid category',))]
fn test_stake_invalid_category() {
    println!("\n");
    print_divider('ERROR_TEST_INVALID_CATEGORY');
    
    let (earn_token, stearn_token, _escrow, manager_address, 
         staking_address, vesting_address, _bulk_vesting) = setup_complete_system();
    
    // Configure
    let stearn_dispatcher = IStEarnTokenDispatcher { contract_address: stearn_token };
    start_cheat_caller_address(stearn_token, OWNER());
    stearn_dispatcher.set_vesting_address(vesting_address);
    stearn_dispatcher.set_staking_contract_address(staking_address);
    stop_cheat_caller_address(stearn_token);
    
    let staking = IEarnscapeStakingDispatcher { contract_address: staking_address };
    start_cheat_caller_address(staking_address, OWNER());
    staking.set_vesting_contract(vesting_address);
    stop_cheat_caller_address(staking_address);
    
    // Setup user with tokens
    transfer_token(earn_token, OWNER(), manager_address, 10000 * ONE_TOKEN);
    
    let manager = IEarnSTARKManagerDispatcher { contract_address: manager_address };
    start_cheat_caller_address(manager_address, OWNER());
    manager.earn_deposit_to_vesting(USER1(), 1000 * ONE_TOKEN);
    stop_cheat_caller_address(manager_address);
    
    // Approve
    approve_token(stearn_token, USER1(), staking_address, LEVEL_1_COST);
    
    // Try to stake with invalid category 'X' - should panic
    let levels = array![1].span();
    start_cheat_caller_address(staking_address, USER1());
    staking.stake('X', levels); // This will panic
    stop_cheat_caller_address(staking_address);
}

#[test]
#[should_panic(expected: ('Insufficient stEARN balance',))]
fn test_stake_insufficient_balance() {
    let (earn_token, stearn_token, manager_address, staking_address, vesting_address) = setup();
    let staking = IEarnscapeStakingDispatcher { contract_address: staking_address };

    // Setup user with minimal tokens
    let manager = IEarnSTARKManagerDispatcher { contract_address: manager_address };
    transfer_token(earn_token, OWNER(), manager_address, 10000 * ONE_TOKEN);
    
    start_cheat_caller_address(manager_address, OWNER());
    manager.earn_deposit_to_vesting(USER1(), 10 * ONE_TOKEN); // Only 10 tokens
    stop_cheat_caller_address(manager_address);
    
    // Approve more than balance
    approve_token(stearn_token, USER1(), staking_address, LEVEL_1_COST);
    
    // Try to stake level 1 - should panic due to insufficient balance
    let levels = array![1].span();
    start_cheat_caller_address(staking_address, USER1());
    staking.stake('T', levels);
    stop_cheat_caller_address(staking_address);
}

#[test]
#[should_panic(expected: ('ERC20: insufficient allowance',))]
fn test_stake_no_approval() {
    println!("\n");
    print_divider('ERROR_TEST_NO_APPROVAL');
    
    let (earn_token, stearn_token, _escrow, manager_address, 
         staking_address, vesting_address, _bulk_vesting) = setup_complete_system();
    
    // Configure
    let stearn_dispatcher = IStEarnTokenDispatcher { contract_address: stearn_token };
    start_cheat_caller_address(stearn_token, OWNER());
    stearn_dispatcher.set_vesting_address(vesting_address);
    stearn_dispatcher.set_staking_contract_address(staking_address);
    stop_cheat_caller_address(stearn_token);
    
    let staking = IEarnscapeStakingDispatcher { contract_address: staking_address };
    start_cheat_caller_address(staking_address, OWNER());
    staking.set_vesting_contract(vesting_address);
    stop_cheat_caller_address(staking_address);
    
    // Setup user with tokens
    transfer_token(earn_token, OWNER(), manager_address, 10000 * ONE_TOKEN);
    
    let manager = IEarnSTARKManagerDispatcher { contract_address: manager_address };
    start_cheat_caller_address(manager_address, OWNER());
    manager.earn_deposit_to_vesting(USER1(), 1000 * ONE_TOKEN);
    stop_cheat_caller_address(manager_address);
    
    // DO NOT approve tokens
    // approve_token(stearn_token, USER1(), staking_address, LEVEL_1_COST);
    
    // Try to stake without approval - should panic
    let levels = array![1].span();
    start_cheat_caller_address(staking_address, USER1());
    staking.stake('T', levels); // This will panic
    stop_cheat_caller_address(staking_address);
}

#[test]
#[should_panic(expected: ('No Earn or Stearn staking data',))]
fn test_unstake_without_staking() {
    println!("\n");
    print_divider('ERROR_TEST_UNSTAKE_NO_DATA');
    
    let (earn_token, stearn_token, _escrow, manager_address, 
         staking_address, vesting_address, _bulk_vesting) = setup_complete_system();
    
    // Configure
    let stearn_dispatcher = IStEarnTokenDispatcher { contract_address: stearn_token };
    start_cheat_caller_address(stearn_token, OWNER());
    stearn_dispatcher.set_vesting_address(vesting_address);
    stearn_dispatcher.set_staking_contract_address(staking_address);
    stop_cheat_caller_address(stearn_token);
    
    let staking = IEarnscapeStakingDispatcher { contract_address: staking_address };
    start_cheat_caller_address(staking_address, OWNER());
    staking.set_vesting_contract(vesting_address);
    stop_cheat_caller_address(staking_address);
    
    // Try to unstake without any staking data - should panic
    start_cheat_caller_address(staking_address, USER1());
    staking.unstake(); // This will panic
    stop_cheat_caller_address(staking_address);
}

#[test]
#[should_panic(expected: ('No Earn or Stearn staking data',))]
fn test_reshuffle_without_staking() {
    println!("\n");
    print_divider('ERROR_TEST_RESHUFFLE_NO_DATA');
    
    let (earn_token, stearn_token, _escrow, manager_address, 
         staking_address, vesting_address, _bulk_vesting) = setup_complete_system();
    
    // Configure
    let stearn_dispatcher = IStEarnTokenDispatcher { contract_address: stearn_token };
    start_cheat_caller_address(stearn_token, OWNER());
    stearn_dispatcher.set_vesting_address(vesting_address);
    stearn_dispatcher.set_staking_contract_address(staking_address);
    stop_cheat_caller_address(stearn_token);
    
    let staking = IEarnscapeStakingDispatcher { contract_address: staking_address };
    start_cheat_caller_address(staking_address, OWNER());
    staking.set_vesting_contract(vesting_address);
    stop_cheat_caller_address(staking_address);
    
    // Try to reshuffle without any staking data - should panic
    start_cheat_caller_address(staking_address, USER1());
    staking.reshuffle(); // This will panic
    stop_cheat_caller_address(staking_address);
}_cheat_caller_address(staking_address);
    
    print_success('System_Configured');
    
    // Check owner balance
    print_step(1, 'Check_Owner_Balance');
    let owner_balance = get_balance(earn_token, OWNER());
    print_check('Owner_Balance', owner_balance);
    assert(owner_balance > 0, 'Owner has no tokens');
    
    // Transfer to manager
    print_step(2, 'Transfer_to_Manager');
    let transfer_amount = 20000 * ONE_TOKEN;
    transfer_token(earn_token, OWNER(), manager_address, transfer_amount);
    
    let manager = IEarnSTARKManagerDispatcher { contract_address: manager_address };
    let manager_balance = manager.get_earns_balance();
    print_check('Manager_Balance', manager_balance);
    assert(manager_balance == transfer_amount, 'Transfer failed');
    
    // Verify addresses
    print_step(3, 'Verify_Contract_Addresses');
    let vesting_addr = manager.vesting();
    assert(vesting_addr == vesting_address, 'Vesting mismatch');
    print_success('Addresses_Verified');
    
    // Set timestamp
    start_cheat_block_timestamp_global(1000);
    
    // Execute USER1 flow (reshuffle)
    execute_basic_flow(
        earn_token,
        stearn_token,
        manager_address,
        staking_address,
        vesting_address,
        USER1(),
        'USER1',
        false,
    );
    
    // Wait
    start_cheat_block_timestamp_global(2000);
    
    // Execute USER2 flow (unstake)
    execute_basic_flow(
        earn_token,
        stearn_token,
        manager_address,
        staking_address,
        vesting_address,
        USER2(),
        'USER2',
        true,
    );
    
    // Wait
    start_cheat_block_timestamp_global(3000);
    
    // Execute USER3 flow (with tip and advanced features)
    execute_user3_tip_flow(
        earn_token,
        stearn_token,
        manager_address,
        staking_address,
        vesting_address,
    );
    
    stop_cheat_block_timestamp_global();
    
    print_divider('ALL_TESTS_COMPLETED');
}

#[test]
fn test_user1_reshuffle_flow() {
    println!("\n");
    print_divider('USER1_RESHUFFLE_TEST');
    
    let (earn_token, stearn_token, _escrow, manager_address, 
         staking_address, vesting_address, _bulk_vesting) = setup_complete_system();
    
    // Configure
    let stearn_dispatcher = IStEarnTokenDispatcher { contract_address: stearn_token };
    start_cheat_caller_address(stearn_token, OWNER());
    stearn_dispatcher.set_vesting_address(vesting_address);
    stearn_dispatcher.set_staking_contract_address(staking_address);
    stop_cheat_caller_address(stearn_token);
    
    let staking = IEarnscapeStakingDispatcher { contract_address: staking_address };
    start_cheat_caller_address(staking_address, OWNER());
    staking.set_vesting_contract(vesting_address);
    stop_cheat_caller_address(staking_address);
    
    transfer_token(earn_token, OWNER(), manager_address, 10000 * ONE_TOKEN);
    
    start_cheat_block_timestamp_global(1000);
    
    execute_basic_flow(
        earn_token,
        stearn_token,
        manager_address,
        staking_address,
        vesting_address,
        USER1(),
        'USER1',
        false,
    );
    
    stop_cheat_block_timestamp_global();
    print_divider('USER1_TEST_COMPLETED');
}

#[test]
fn test_user2_unstake_flow() {
    println!("\n");
    print_divider('USER2_UNSTAKE_TEST');
    
    let (earn_token, stearn_token, _escrow, manager_address, 
         staking_address, vesting_address, _bulk_vesting) = setup_complete_system();
    
    // Configure
    let stearn_dispatcher = IStEarnTokenDispatcher { contract_address: stearn_token };
    start_cheat_caller_address(stearn_token, OWNER());
    stearn_dispatcher.set_vesting_address(vesting_address);
    stearn_dispatcher.set_staking_contract_address(staking_address);
    stop_cheat_caller_address(stearn_token);
    
    let staking = IEarnscapeStakingDispatcher { contract_address: staking_address };
    start_cheat_caller_address(staking_address, OWNER());
    staking.set_vesting_contract(vesting_address);
    stop_cheat_caller_address(staking_address);
    
    transfer_token(earn_token, OWNER(), manager_address, 10000 * ONE_TOKEN);
    
    start_cheat_block_timestamp_global(1000);
    
    execute_basic_flow(
        earn_token,
        stearn_token,
        manager_address,
        staking_address,
        vesting_address,
        USER2(),
        'USER2',
        true,
    );
    
    stop_cheat_block_timestamp_global();
    print_divider('USER2_TEST_COMPLETED');
}

#[test]
fn test_user3_tip_flow_only() {
    println!("\n");
    print_divider('USER3_TIP_FLOW_TEST');
    
    let (earn_token, stearn_token, _escrow, manager_address, 
         staking_address, vesting_address, _bulk_vesting) = setup_complete_system();
    
    // Configure
    let stearn_dispatcher = IStEarnTokenDispatcher { contract_address: stearn_token };
    start_cheat_caller_address(stearn_token, OWNER());
    stearn_dispatcher.set_vesting_address(vesting_address);
    stearn_dispatcher.set_staking_contract_address(staking_address);
    stop_cheat_caller_address(stearn_token);
    
    let staking = IEarnscapeStakingDispatcher { contract_address: staking_address };
    start_cheat_caller_address(staking_address, OWNER());
    staking.set_vesting_contract(vesting_address);
    stop_cheat_caller_address(staking_address);  // ← ADDED

    // Transfer tokens to manager for USER3 operations
    transfer_token(earn_token, OWNER(), manager_address, 20000 * ONE_TOKEN);

    // Set initial timestamp for vesting operations
    start_cheat_block_timestamp_global(1000);

    // Execute USER3 complete flow
    execute_user3_tip_flow(
        earn_token,
        stearn_token,
        manager_address,
        staking_address,
        vesting_address,
    );

    // Clean up timestamp
    stop_cheat_block_timestamp_global();

    print_divider('USER3_TEST_COMPLETED');
}

// ============================================================================
// Additional Error Test Cases
// ============================================================================

#[test]
#[should_panic(expected: ('Insufficient stEARN balance',))]
fn test_stake_insufficient_balance() {
    let (earn_token, stearn_token, manager_address, staking_address, vesting_address) = setup();
    let staking = IEarnscapeStakingDispatcher { contract_address: staking_address };

    // Setup user with minimal tokens
    let manager = IEarnSTARKManagerDispatcher { contract_address: manager_address };
    transfer_token(earn_token, OWNER(), manager_address, 10000 * ONE_TOKEN);
    
    start_cheat_caller_address(manager_address, OWNER());
    manager.earn_deposit_to_vesting(USER1(), 10 * ONE_TOKEN); // Only 10 tokens
    stop_cheat_caller_address(manager_address);
    
    // Approve more than balance
    approve_token(stearn_token, USER1(), staking_address, LEVEL_1_COST);
    
    // Try to stake level 1 - should panic due to insufficient balance
    let levels = array![1].span();
    start_cheat_caller_address(staking_address, USER1());
    staking.stake('T', levels);
    stop_cheat_caller_address(staking_address);
}

#[test]
#[should_panic(expected: ('ERC20: insufficient allowance',))]
fn test_stake_no_approval() {
    let (earn_token, stearn_token, manager_address, staking_address, vesting_address) = setup();
    let staking = IEarnscapeStakingDispatcher { contract_address: staking_address };
    
    // Setup user with tokens but no approval
    let manager = IEarnSTARKManagerDispatcher { contract_address: manager_address };
    transfer_token(earn_token, OWNER(), manager_address, 10000 * ONE_TOKEN);
    
    start_cheat_caller_address(manager_address, OWNER());
    manager.earn_deposit_to_vesting(USER1(), 1000 * ONE_TOKEN);
    stop_cheat_caller_address(manager_address);
    
    // Try to stake without approval - should panic
    let levels = array![1].span();
    start_cheat_caller_address(staking_address, USER1());
    staking.stake('T', levels);
    stop_cheat_caller_address(staking_address);
}

#[test]
#[should_panic(expected: ('Invalid category',))]
fn test_stake_invalid_category() {
    let (earn_token, stearn_token, manager_address, staking_address, vesting_address) = setup();
    let staking = IEarnscapeStakingDispatcher { contract_address: staking_address };
    
    // Setup user with tokens
    let manager = IEarnSTARKManagerDispatcher { contract_address: manager_address };
    transfer_token(earn_token, OWNER(), manager_address, 10000 * ONE_TOKEN);
    
    start_cheat_caller_address(manager_address, OWNER());
    manager.earn_deposit_to_vesting(USER1(), 1000 * ONE_TOKEN);
    stop_cheat_caller_address(manager_address);
    
    approve_token(stearn_token, USER1(), staking_address, LEVEL_1_COST);
    
    // Try to stake with invalid category - should panic
    let levels = array![1].span();
    start_cheat_caller_address(staking_address, USER1());
    staking.stake('X', levels);
    stop_cheat_caller_address(staking_address);
}