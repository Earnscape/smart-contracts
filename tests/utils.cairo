use core::traits::{Into, TryInto};
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_block_timestamp_global,
    start_cheat_caller_address, stop_cheat_block_timestamp_global, stop_cheat_caller_address,
};
use starknet::ContractAddress;

// ============================================================================
// Constants - Addresses
// ============================================================================

pub fn OWNER() -> ContractAddress {
    'owner'.try_into().unwrap()
}

pub fn USER1() -> ContractAddress {
    'user1'.try_into().unwrap()
}

pub fn USER2() -> ContractAddress {
    'user2'.try_into().unwrap()
}

pub fn USER3() -> ContractAddress {
    'user3'.try_into().unwrap()
}

pub fn ADMIN() -> ContractAddress {
    'admin'.try_into().unwrap()
}

pub fn TREASURY() -> ContractAddress {
    'treasury'.try_into().unwrap()
}

pub fn ZERO_ADDRESS() -> ContractAddress {
    0.try_into().unwrap()
}

// ============================================================================
// Constants - Amounts
// ============================================================================

pub const ONE_TOKEN: u256 = 1_000_000_000_000_000_000; // 1 token with 18 decimals
pub const HUNDRED_TOKENS: u256 = 100_000_000_000_000_000_000; // 100 tokens
pub const THOUSAND_TOKENS: u256 = 1_000_000_000_000_000_000_000; // 1000 tokens
pub const ONE_MILLION_TOKENS: u256 = 1_000_000_000_000_000_000_000_000; // 1M tokens
pub const ONE_BILLION_TOKENS: u256 = 1_000_000_000_000_000_000_000_000_000; // 1B tokens

// ============================================================================
// Constants - Time
// ============================================================================

pub const ONE_MINUTE: u64 = 60;
pub const ONE_HOUR: u64 = 3600;
pub const ONE_DAY: u64 = 86400;
pub const ONE_WEEK: u64 = 604800;
pub const ONE_MONTH: u64 = 2592000; // 30 days

// ============================================================================
// Constants - Staking
// ============================================================================

pub const MAX_LEVEL: u8 = 5;
pub const DEFAULT_TAX: u256 = 5000; // 50%
pub const RESHUFFLE_TAX: u256 = 2500; // 25%
pub const BASIS_POINTS: u256 = 10000; // 100%

// Default level costs
pub const LEVEL_1_COST: u256 = 100_000_000_000_000_000_000; // 100 tokens
pub const LEVEL_2_COST: u256 = 200_000_000_000_000_000_000; // 200 tokens
pub const LEVEL_3_COST: u256 = 400_000_000_000_000_000_000; // 400 tokens
pub const LEVEL_4_COST: u256 = 800_000_000_000_000_000_000; // 800 tokens
pub const LEVEL_5_COST: u256 = 1_600_000_000_000_000_000_000; // 1600 tokens

// ============================================================================
// Setup Functions - Tokens
// ============================================================================

pub fn setup_earn_token() -> (ContractAddress, ERC20ABIDispatcher) {
    let contract = declare("EarnToken").unwrap().contract_class();
    let constructor_args = array![OWNER().into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let dispatcher = ERC20ABIDispatcher { contract_address };
    (contract_address, dispatcher)
}

pub fn setup_stearn_token() -> ContractAddress {
    let contract = declare("StEarnToken").unwrap().contract_class();
    let constructor_args = array![OWNER().into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    contract_address
}

// ============================================================================
// Setup Functions - Core Contracts
// ============================================================================

pub fn setup_escrow(earns_token: ContractAddress, treasury: ContractAddress) -> ContractAddress {
    let contract = declare("Escrow").unwrap().contract_class();
    let constructor_args = array![OWNER().into(), earns_token.into(), treasury.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    contract_address
}

pub fn setup_earnstark_manager(earns_token: ContractAddress) -> ContractAddress {
    let contract = declare("EarnSTARKManager").unwrap().contract_class();
    let constructor_args = array![OWNER().into(), earns_token.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    contract_address
}

pub fn setup_staking(
    earn_token: ContractAddress, stearn_token: ContractAddress, manager: ContractAddress,
) -> ContractAddress {
    let contract = declare("EarnscapeStaking").unwrap().contract_class();
    let constructor_args = array![
        OWNER().into(), earn_token.into(), stearn_token.into(), manager.into(),
    ];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    contract_address
}

pub fn setup_vesting(
    earn_token: ContractAddress,
    stearn_token: ContractAddress,
    manager: ContractAddress,
    staking: ContractAddress,
) -> ContractAddress {
    let contract = declare("Vesting").unwrap().contract_class();
    let constructor_args = array![
        earn_token.into(), stearn_token.into(), manager.into(), staking.into(), OWNER().into(),
    ];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    contract_address
}

pub fn setup_bulk_vesting(
    manager: ContractAddress, escrow: ContractAddress, token: ContractAddress,
) -> ContractAddress {
    let contract = declare("EarnscapeBulkVesting").unwrap().contract_class();
    let constructor_args = array![manager.into(), escrow.into(), token.into(), OWNER().into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    contract_address
}

// ============================================================================
// Setup Functions - Complete System
// ============================================================================

pub fn setup_complete_system() -> (
    ContractAddress, // earn_token
    ContractAddress, // stearn_token
    ContractAddress, // escrow
    ContractAddress, // manager
    ContractAddress, // staking
    ContractAddress, // vesting
    ContractAddress // bulk_vesting
) {
    // Deploy tokens
    let (earn_token, _) = setup_earn_token();
    let stearn_token = setup_stearn_token();

    // Deploy escrow
    let escrow = setup_escrow(earn_token, TREASURY());

    // Deploy manager
    let manager = setup_earnstark_manager(earn_token);

    // Deploy staking
    let staking = setup_staking(earn_token, stearn_token, manager);

    // Deploy vesting
    let vesting = setup_vesting(earn_token, stearn_token, manager, staking);

    // Deploy bulk vesting
    let bulk_vesting = setup_bulk_vesting(manager, escrow, earn_token);

    (earn_token, stearn_token, escrow, manager, staking, vesting, bulk_vesting)
}

// ============================================================================
// Helper Functions
// ============================================================================

pub fn approve_token(
    token: ContractAddress, from: ContractAddress, spender: ContractAddress, amount: u256,
) {
    let token_dispatcher = ERC20ABIDispatcher { contract_address: token };
    start_cheat_caller_address(token, from);
    token_dispatcher.approve(spender, amount);
    stop_cheat_caller_address(token);
}

pub fn transfer_token(
    token: ContractAddress, from: ContractAddress, to: ContractAddress, amount: u256,
) {
    let token_dispatcher = ERC20ABIDispatcher { contract_address: token };
    start_cheat_caller_address(token, from);
    token_dispatcher.transfer(to, amount);
    stop_cheat_caller_address(token);
}

pub fn get_balance(token: ContractAddress, account: ContractAddress) -> u256 {
    let token_dispatcher = ERC20ABIDispatcher { contract_address: token };
    token_dispatcher.balance_of(account)
}

pub fn advance_time(seconds: u64) {
    let current_time = starknet::get_block_timestamp();
    start_cheat_block_timestamp_global(current_time + seconds);
}

pub fn reset_time() {
    stop_cheat_block_timestamp_global();
}

