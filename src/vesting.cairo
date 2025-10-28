#[starknet::contract]
mod Vesting {
    use core::array::ArrayTrait;
    use core::num::traits::Zero;
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address, get_contract_address};

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    // Interface for stEARN token
    #[starknet::interface]
    trait IStEarn<TContractState> {
        fn burn(ref self: TContractState, user: ContractAddress, amount: u256);
        fn mint(ref self: TContractState, to: ContractAddress, amount: u256);
        fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
        fn transfer(ref self: TContractState, to: ContractAddress, amount: u256) -> bool;
    }

    // Interface for Staking Contract
    #[starknet::interface]
    trait IEarnscapeStaking<TContractState> {
        fn get_user_data(
            self: @TContractState, user: ContractAddress,
        ) -> (Array<felt252>, Array<u256>, Array<u256>, Array<ContractAddress>);
        fn get_user_stearn_data(
            self: @TContractState, user: ContractAddress,
        ) -> (Array<felt252>, Array<u256>, Array<u256>, Array<ContractAddress>);
        fn get_user_pending_stearn_tax(self: @TContractState, user: ContractAddress) -> u256;
        fn calculate_user_stearn_tax(self: @TContractState, user: ContractAddress) -> (u256, u256);
        fn update_user_pending_stearn_tax(
            ref self: TContractState, user: ContractAddress, new_tax_amount: u256,
        );
    }

    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        // Token references
        earn_token: IERC20Dispatcher,
        stearn_token: ContractAddress,
        staking_contract: ContractAddress,
        earn_stark_manager: ContractAddress,
        // Configuration
        total_amount_vested: u256,
        default_vesting_time: u64,
        platform_fee_pct: u64,
        cliff_period: u64,
        sliced_period: u64,
        fee_recipient: ContractAddress,
        merchandise_admin_wallet: ContractAddress,
        // User balances (mapping to match Solidity's Earnbalance and stearnBalance)
        earn_balance: Map<ContractAddress, u256>,
        stearn_balance: Map<ContractAddress, u256>,
        // Vesting schedules (mapping to match Solidity's holdersVestingCount and vestedUserDetail)
        user_vesting_count: Map<ContractAddress, u32>,
        vesting_beneficiary: Map<(ContractAddress, u32), ContractAddress>,
        vesting_cliff: Map<(ContractAddress, u32), u64>,
        vesting_start: Map<(ContractAddress, u32), u64>,
        vesting_duration: Map<(ContractAddress, u32), u64>,
        vesting_slice_period: Map<(ContractAddress, u32), u64>,
        vesting_amount_total: Map<(ContractAddress, u32), u256>,
        vesting_released: Map<(ContractAddress, u32), u256>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        TokensLocked: TokensLocked,
        PendingEarnDueToStearnUnstake: PendingEarnDueToStearnUnstake,
        TipGiven: TipGiven,
        PlatformFeeTaken: PlatformFeeTaken,
        VestingScheduleCreated: VestingScheduleCreated,
        TokensReleasedImmediately: TokensReleasedImmediately,
    }

    #[derive(Drop, starknet::Event)]
    struct TokensLocked {
        #[key]
        beneficiary: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct PendingEarnDueToStearnUnstake {
        #[key]
        user: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct TipGiven {
        #[key]
        giver: ContractAddress,
        #[key]
        receiver: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct PlatformFeeTaken {
        #[key]
        from: ContractAddress,
        #[key]
        to: ContractAddress,
        fee_amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct VestingScheduleCreated {
        #[key]
        beneficiary: ContractAddress,
        start: u64,
        cliff: u64,
        duration: u64,
        slice_period_seconds: u64,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct TokensReleasedImmediately {
        category_id: u256,
        #[key]
        recipient: ContractAddress,
        amount: u256,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        token_address: ContractAddress,
        stearn_address: ContractAddress,
        earn_stark_manager: ContractAddress,
        staking_contract: ContractAddress,
        owner: ContractAddress,
    ) {
        self.ownable.initializer(owner);
        self.earn_token.write(IERC20Dispatcher { contract_address: token_address });
        self.stearn_token.write(stearn_address);
        self.earn_stark_manager.write(earn_stark_manager);
        self.staking_contract.write(staking_contract);
        self.default_vesting_time.write(2880 * 60); // 2880 minutes in seconds
        self.platform_fee_pct.write(40);
        self.fee_recipient.write(owner);
        self.merchandise_admin_wallet.write(owner);
        self.cliff_period.write(0);
        self.sliced_period.write(60); // 60 seconds = 1 minute for testing
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        // Internal function to create vesting schedule
        fn _create_vesting_schedule(
            ref self: ContractState,
            beneficiary: ContractAddress,
            start: u64,
            cliff: u64,
            duration: u64,
            slice_period_seconds: u64,
            amount: u256,
        ) {
            assert(duration >= cliff, 'Duration must be >= cliff');
            let cliff_time = start + cliff;
            let current_index = self.user_vesting_count.entry(beneficiary).read();

            self.vesting_beneficiary.entry((beneficiary, current_index)).write(beneficiary);
            self.vesting_cliff.entry((beneficiary, current_index)).write(cliff_time);
            self.vesting_start.entry((beneficiary, current_index)).write(start);
            self.vesting_duration.entry((beneficiary, current_index)).write(duration);
            self
                .vesting_slice_period
                .entry((beneficiary, current_index))
                .write(slice_period_seconds);
            self.vesting_amount_total.entry((beneficiary, current_index)).write(amount);
            self.vesting_released.entry((beneficiary, current_index)).write(0);

            self.user_vesting_count.entry(beneficiary).write(current_index + 1);
            self.total_amount_vested.write(self.total_amount_vested.read() + amount);

            self
                .emit(
                    VestingScheduleCreated {
                        beneficiary, start, cliff, duration, slice_period_seconds, amount,
                    },
                );
        }

        // Compute releasable amount for a specific vesting schedule
        fn _compute_releasable_amount(
            ref self: ContractState, beneficiary: ContractAddress, index: u32,
        ) -> (u256, u256) {
            let current_time = get_block_timestamp();
            let cliff = self.vesting_cliff.entry((beneficiary, index)).read();
            let start = self.vesting_start.entry((beneficiary, index)).read();
            let duration = self.vesting_duration.entry((beneficiary, index)).read();
            let amount_total = self.vesting_amount_total.entry((beneficiary, index)).read();
            let released = self.vesting_released.entry((beneficiary, index)).read();

            if current_time < cliff {
                return (0, amount_total - released);
            }

            if current_time >= start + duration {
                let releasable = amount_total - released;
                return (releasable, 0);
            }

            let time_from_start = current_time - start;
            let slice_period = self.vesting_slice_period.entry((beneficiary, index)).read();
            let vested_slice_periods = time_from_start / slice_period;
            let vested_seconds = vested_slice_periods * slice_period;
            let total_vested = (amount_total * vested_seconds.into()) / duration.into();
            let releasable = total_vested - released;
            let remaining = amount_total - total_vested;

            (releasable, remaining)
        }

        // Adjust stEARN balance by burning excess
        fn _adjust_stearn_balance(ref self: ContractState, user: ContractAddress) {
            let (_, locked) = self._calculate_releasable_sum(user);
            let stearn_bal = self.stearn_balance.entry(user).read();

            if stearn_bal > locked {
                let excess = stearn_bal - locked;
                self.stearn_balance.entry(user).write(locked);
                let stearn_addr = self.stearn_token.read();
                let stearn = IStEarnDispatcher { contract_address: stearn_addr };
                let contract_addr = get_contract_address();
                stearn.burn(contract_addr, excess);
            }
        }

        // Calculate total releasable and locked amounts
        fn _calculate_releasable_sum(
            ref self: ContractState, user: ContractAddress,
        ) -> (u256, u256) {
            let vesting_count = self.user_vesting_count.entry(user).read();
            let mut total_releasable: u256 = 0;
            let mut total_remaining: u256 = 0;
            let mut i: u32 = 0;

            while i < vesting_count {
                let (releasable, remaining) = self._compute_releasable_amount(user, i);
                total_releasable += releasable;
                total_remaining += remaining;
                i += 1;
            }

            (total_releasable, total_remaining)
        }

        // Update vesting schedules after tip deduction
        fn _update_vesting_after_tip(
            ref self: ContractState, user: ContractAddress, tip_deduction: u256,
        ) {
            let mut remaining_deduction = tip_deduction;
            let vesting_count = self.user_vesting_count.entry(user).read();
            let mut i: u32 = 0;

            while i < vesting_count && remaining_deduction > 0 {
                let amt_total = self.vesting_amount_total.entry((user, i)).read();
                let released = self.vesting_released.entry((user, i)).read();
                let effective_balance = amt_total - released;

                if effective_balance == 0 {
                    i += 1;
                    continue;
                }

                if remaining_deduction >= effective_balance {
                    remaining_deduction -= effective_balance;
                    self.vesting_amount_total.entry((user, i)).write(released);
                } else {
                    let leftover = effective_balance - remaining_deduction;
                    let start = self.vesting_start.entry((user, i)).read();
                    let duration = self.vesting_duration.entry((user, i)).read();
                    let original_end = start + duration;
                    let now = get_block_timestamp();
                    let new_duration = if original_end > now {
                        original_end - now
                    } else {
                        0
                    };

                    self.vesting_start.entry((user, i)).write(now);
                    self.vesting_cliff.entry((user, i)).write(now);
                    self.vesting_duration.entry((user, i)).write(new_duration);
                    self.vesting_amount_total.entry((user, i)).write(released + leftover);
                    self.vesting_released.entry((user, i)).write(0);
                    remaining_deduction = 0;
                }
                i += 1;
            };
        }

        // Process net tip from vesting
        fn _process_net_tip_vesting(
            ref self: ContractState,
            sender: ContractAddress,
            receiver: ContractAddress,
            vesting_net: u256,
            total_releasable: u256,
            total_remaining: u256,
        ) {
            self
                .stearn_balance
                .entry(sender)
                .write(self.stearn_balance.entry(sender).read() - vesting_net);
            self
                .earn_balance
                .entry(sender)
                .write(self.earn_balance.entry(sender).read() - vesting_net);
            self
                .stearn_balance
                .entry(receiver)
                .write(self.stearn_balance.entry(receiver).read() + vesting_net);
            self
                .earn_balance
                .entry(receiver)
                .write(self.earn_balance.entry(receiver).read() + vesting_net);

            self._update_vesting_after_tip(sender, vesting_net);

            let releasable_receiver = if vesting_net <= total_releasable {
                vesting_net
            } else {
                total_releasable
            };
            let locked_receiver = vesting_net - releasable_receiver;
            assert(locked_receiver <= total_remaining, 'Exceeds available vesting');

            let now = get_block_timestamp();

            if releasable_receiver > 0 {
                self._create_vesting_schedule(receiver, now, 0, 0, 0, releasable_receiver);
            }

            if locked_receiver > 0 {
                let merch = self.merchandise_admin_wallet.read();
                let fee_recip = self.fee_recipient.read();
                let vesting_duration = if receiver == merch || receiver == fee_recip {
                    0
                } else {
                    let (_, duration) = self._preview_vesting_params_internal(receiver);
                    duration
                };

                let cliff = self.cliff_period.read();
                let slice = self.sliced_period.read();
                self
                    ._create_vesting_schedule(
                        receiver, now, cliff, vesting_duration, slice, locked_receiver,
                    );
            }
        }

        // Preview vesting parameters for a beneficiary
        fn _preview_vesting_params_internal(
            self: @ContractState, beneficiary: ContractAddress,
        ) -> (u64, u64) {
            let staking_addr = self.staking_contract.read();
            let staking = IEarnscapeStakingDispatcher { contract_address: staking_addr };
            let (categories, levels, _, _) = staking.get_user_data(beneficiary);

            let mut vesting_duration = self.default_vesting_time.read();
            let category_v: felt252 = 'V';
            let mut i: u32 = 0;

            while i < categories.len() {
                if *categories.at(i) == category_v {
                    let level = *levels.at(i);
                    if level == 1 {
                        vesting_duration = 144000;
                    } else if level == 2 {
                        vesting_duration = 123420;
                    } else if level == 3 {
                        vesting_duration = 108000;
                    } else if level == 4 {
                        vesting_duration = 96000;
                    } else if level == 5 {
                        vesting_duration = 86400;
                    }
                    break;
                }
                i += 1;
            }

            let start = get_block_timestamp();
            (start, vesting_duration)
        }

        // Check if user has staked tokens
        fn _has_staked_tokens(self: @ContractState, staked_amounts: Array<u256>) -> bool {
            let mut i: u32 = 0;
            while i < staked_amounts.len() {
                if *staked_amounts.at(i) > 0 {
                    return true;
                }
                i += 1;
            }
            false
        }

        // Swap and delete vesting schedule (for compression)
        fn _swap_and_delete_schedule(
            ref self: ContractState, beneficiary: ContractAddress, index: u32, last_index: u32,
        ) {
            if index < last_index {
                self
                    .vesting_beneficiary
                    .entry((beneficiary, index))
                    .write(self.vesting_beneficiary.entry((beneficiary, last_index)).read());
                self
                    .vesting_cliff
                    .entry((beneficiary, index))
                    .write(self.vesting_cliff.entry((beneficiary, last_index)).read());
                self
                    .vesting_start
                    .entry((beneficiary, index))
                    .write(self.vesting_start.entry((beneficiary, last_index)).read());
                self
                    .vesting_duration
                    .entry((beneficiary, index))
                    .write(self.vesting_duration.entry((beneficiary, last_index)).read());
                self
                    .vesting_slice_period
                    .entry((beneficiary, index))
                    .write(self.vesting_slice_period.entry((beneficiary, last_index)).read());
                self
                    .vesting_amount_total
                    .entry((beneficiary, index))
                    .write(self.vesting_amount_total.entry((beneficiary, last_index)).read());
                self
                    .vesting_released
                    .entry((beneficiary, index))
                    .write(self.vesting_released.entry((beneficiary, last_index)).read());
            }
        }
    }

    #[abi(embed_v0)]
    impl VestingImpl of super::IVesting<ContractState> {
        // Update earnStarkManager address
        fn update_earn_stark_manager(ref self: ContractState, earn_stark_manager: ContractAddress) {
            self.ownable.assert_only_owner();
            self.earn_stark_manager.write(earn_stark_manager);
        }

        // Update staking contract address
        fn update_staking_contract(ref self: ContractState, staking_contract: ContractAddress) {
            self.ownable.assert_only_owner();
            self.staking_contract.write(staking_contract);
        }

        // Get EARN balance
        fn get_earn_balance(self: @ContractState, beneficiary: ContractAddress) -> u256 {
            self.earn_balance.entry(beneficiary).read()
        }

        // Update EARN balance (only callable by staking contract)
        fn update_earn_balance(ref self: ContractState, user: ContractAddress, amount: u256) {
            let caller = get_caller_address();
            let staking = self.staking_contract.read();
            assert(caller == staking, 'Only staking contract');

            let current = self.earn_balance.entry(user).read();
            assert(current >= amount, 'Insufficient Earn balance');
            self.earn_balance.entry(user).write(amount);
        }

        // Get stEARN balance
        fn get_stearn_balance(self: @ContractState, beneficiary: ContractAddress) -> u256 {
            self.stearn_balance.entry(beneficiary).read()
        }

        // Update stEARN balance (only callable by staking contract)
        fn update_stearn_balance(ref self: ContractState, user: ContractAddress, amount: u256) {
            let caller = get_caller_address();
            let staking = self.staking_contract.read();
            assert(caller == staking, 'Only staking contract');

            let current = self.stearn_balance.entry(user).read();
            assert(current >= amount, 'Insufficient stEARN balance');
            self.stearn_balance.entry(user).write(amount);
        }

        // Transfer stEARN tokens
        fn st_earn_transfer(ref self: ContractState, sender: ContractAddress, amount: u256) {
            let current = self.stearn_balance.entry(sender).read();
            if current >= amount {
                self.stearn_balance.entry(sender).write(current - amount);
                let stearn_token = self.stearn_token.read();
                IERC20Dispatcher { contract_address: stearn_token }
                    .transfer(get_caller_address(), amount);
            }
        }

        // Deposit EARN tokens and create vesting schedule
        fn deposit_earn(ref self: ContractState, beneficiary: ContractAddress, amount: u256) {
            let caller = get_caller_address();
            let manager = self.earn_stark_manager.read();
            assert(caller == manager, 'Only earnStarkManager');
            assert(amount > 0, 'Amount must be > 0');

            let mut vesting_duration = self.default_vesting_time.read();
            let staking_addr = self.staking_contract.read();
            let staking = IEarnscapeStakingDispatcher { contract_address: staking_addr };
            let (categories, levels, _, _) = staking.get_user_data(beneficiary);

            let mut is_in_category_v = false;
            let category_v: felt252 = 'V';
            let mut i: u32 = 0;

            while i < categories.len() {
                if *categories.at(i) == category_v {
                    is_in_category_v = true;
                    let level = *levels.at(i);

                    if level == 1 {
                        vesting_duration = 144000; // 2400 minutes in seconds
                    } else if level == 2 {
                        vesting_duration = 123420; // 2057 minutes in seconds
                    } else if level == 3 {
                        vesting_duration = 108000; // 1800 minutes in seconds
                    } else if level == 4 {
                        vesting_duration = 96000; // 1600 minutes in seconds
                    } else if level == 5 {
                        vesting_duration = 86400; // 1440 minutes in seconds
                    }
                    break;
                }
                i += 1;
            }

            let prev_earn = self.earn_balance.entry(beneficiary).read();
            self.earn_balance.entry(beneficiary).write(prev_earn + amount);

            let stearn_addr = self.stearn_token.read();
            let stearn = IStEarnDispatcher { contract_address: stearn_addr };
            let contract_addr = get_contract_address();
            stearn.mint(contract_addr, amount);

            let prev_stearn = self.stearn_balance.entry(beneficiary).read();
            self.stearn_balance.entry(beneficiary).write(prev_stearn + amount);

            let now = get_block_timestamp();
            let cliff = self.cliff_period.read();
            let slice = self.sliced_period.read();

            self._create_vesting_schedule(beneficiary, now, cliff, vesting_duration, slice, amount);

            self.emit(TokensLocked { beneficiary, amount });
        }

        // Calculate total releasable and remaining amounts
        fn calculate_releasable_amount(
            self: @ContractState, beneficiary: ContractAddress,
        ) -> (u256, u256) {
            let vesting_count = self.user_vesting_count.entry(beneficiary).read();
            let mut total_releasable: u256 = 0;
            let mut total_remaining: u256 = 0;
            let mut i: u32 = 0;

            while i < vesting_count {
                let current_time = get_block_timestamp();
                let cliff = self.vesting_cliff.entry((beneficiary, i)).read();
                let start = self.vesting_start.entry((beneficiary, i)).read();
                let duration = self.vesting_duration.entry((beneficiary, i)).read();
                let amount_total = self.vesting_amount_total.entry((beneficiary, i)).read();
                let released = self.vesting_released.entry((beneficiary, i)).read();

                let (releasable, remaining) = if current_time < cliff {
                    (0, amount_total - released)
                } else if current_time >= start + duration {
                    (amount_total - released, 0)
                } else {
                    let time_from_start = current_time - start;
                    let slice_period = self.vesting_slice_period.entry((beneficiary, i)).read();
                    let vested_slice_periods = time_from_start / slice_period;
                    let vested_seconds = vested_slice_periods * slice_period;
                    let total_vested = (amount_total * vested_seconds.into()) / duration.into();
                    let rel = total_vested - released;
                    let rem = amount_total - total_vested;
                    (rel, rem)
                };

                total_releasable += releasable;
                total_remaining += remaining;
                i += 1;
            }

            (total_releasable, total_remaining)
        }

        // Release vested amount with tax deduction
        fn release_vested_amount(ref self: ContractState, beneficiary: ContractAddress) {
            let (rel, _) = self.calculate_releasable_amount(beneficiary);
            assert(rel > 0, 'No releasable amount');

            self._adjust_stearn_balance(beneficiary);

            let staking_addr = self.staking_contract.read();
            let staking = IEarnscapeStakingDispatcher { contract_address: staking_addr };

            let tax = staking.get_user_pending_stearn_tax(beneficiary);
            let (_, st) = staking.calculate_user_stearn_tax(beneficiary);

            // Remove tax from locked vesting
            self._update_vesting_after_tip(beneficiary, tax);
            let ben_earn = self.earn_balance.entry(beneficiary).read();
            self.earn_balance.entry(beneficiary).write(ben_earn - tax);

            // Pay out tax to manager
            if tax > 0 {
                let manager = self.earn_stark_manager.read();
                assert(self.earn_token.read().transfer(manager, tax), 'Tax transfer failed');
                staking.update_user_pending_stearn_tax(beneficiary, 0);
            }

            // Compute net payout
            let pay = if rel > st {
                rel - st
            } else {
                0
            };
            assert(pay > 0, 'No claimable after tax');

            // Slice through vesting schedules
            let mut cnt = self.user_vesting_count.entry(beneficiary).read();
            let mut remaining_pay = pay;
            let mut i: u32 = 0;

            while i < cnt && remaining_pay > 0 {
                let amt_total = self.vesting_amount_total.entry((beneficiary, i)).read();
                let released = self.vesting_released.entry((beneficiary, i)).read();
                let available = amt_total - released;

                if available == 0 {
                    if i < cnt - 1 {
                        self._swap_and_delete_schedule(beneficiary, i, cnt - 1);
                    }
                    cnt -= 1;
                    continue;
                }

                let slice = if remaining_pay < available {
                    remaining_pay
                } else {
                    available
                };
                self.vesting_released.entry((beneficiary, i)).write(released + slice);

                let ben_earn_current = self.earn_balance.entry(beneficiary).read();
                self.earn_balance.entry(beneficiary).write(ben_earn_current - slice);

                remaining_pay -= slice;
                assert(
                    self.earn_token.read().transfer(beneficiary, slice), 'Token transfer failed',
                );

                let new_released = released + slice;
                if new_released == amt_total {
                    if i < cnt - 1 {
                        self._swap_and_delete_schedule(beneficiary, i, cnt - 1);
                    }
                    cnt -= 1;
                    continue;
                }
                i += 1;
            }

            self.user_vesting_count.entry(beneficiary).write(cnt);
            let actual_released = pay - remaining_pay;

            // Match Solidity's event emission: (rel - st) - tax - remaining_pay
            let category_id_value = if rel > st {
                rel - st
            } else {
                0
            };
            let final_category = if category_id_value > tax {
                category_id_value - tax
            } else {
                0
            };
            let event_category = if final_category > remaining_pay {
                final_category - remaining_pay
            } else {
                0
            };

            self
                .emit(
                    TokensReleasedImmediately {
                        category_id: event_category,
                        recipient: beneficiary,
                        amount: actual_released,
                    },
                );
        }

        // Force release vested amount (matches Solidity forceReleaseVestedAmount)
        fn force_release_vested_amount(ref self: ContractState, beneficiary: ContractAddress) {
            let (unlock, locked) = self.calculate_releasable_amount(beneficiary);
            let total_amount = unlock + locked;

            self._adjust_stearn_balance(beneficiary);
            assert(total_amount > 0, 'No vested tokens');

            let vesting_count = self.user_vesting_count.entry(beneficiary).read();
            assert(vesting_count > 0, 'No vesting schedules');

            // Check if user has staked tokens (matches Solidity)
            let staking_addr = self.staking_contract.read();
            let staking = IEarnscapeStakingDispatcher { contract_address: staking_addr };
            let (_, _, staked_amounts, _) = staking.get_user_stearn_data(beneficiary);

            let has_staked = self._has_staked_tokens(staked_amounts);
            assert(!has_staked, 'Unstake first to get earns');

            // Handle tax (matches Solidity transferTaxToManager)
            let tax_amount = staking.get_user_pending_stearn_tax(beneficiary);

            if tax_amount > 0 {
                let manager = self.earn_stark_manager.read();
                assert(self.earn_token.read().transfer(manager, tax_amount), 'Tax transfer failed');
                staking.update_user_pending_stearn_tax(beneficiary, 0);
            }

            // Process vesting schedules (matches Solidity processVestingSchedules)
            assert(total_amount >= tax_amount, 'Insufficient amount for tax');
            let mut remaining_amount = total_amount - tax_amount;

            let mut i: u32 = 0;
            while i < vesting_count && remaining_amount > 0 {
                let amt_total = self.vesting_amount_total.entry((beneficiary, i)).read();
                let released = self.vesting_released.entry((beneficiary, i)).read();
                let unreleased_amount = amt_total - released;

                if unreleased_amount > 0 {
                    let transfer_amount = if unreleased_amount > remaining_amount {
                        remaining_amount
                    } else {
                        unreleased_amount
                    };

                    self.vesting_released.entry((beneficiary, i)).write(released + transfer_amount);
                    remaining_amount -= transfer_amount;

                    // Burn and transfer tokens (matches Solidity burnAndTransferTokens)
                    let balance = self.stearn_balance.entry(beneficiary).read();
                    let stearn_addr = self.stearn_token.read();
                    let stearn = IStEarnDispatcher { contract_address: stearn_addr };
                    let contract_balance = stearn.balance_of(get_contract_address());

                    if balance > 0 && contract_balance >= balance {
                        stearn.burn(get_contract_address(), balance);
                        self.stearn_balance.entry(beneficiary).write(0);
                    }

                    self.earn_balance.entry(beneficiary).write(0);
                    assert(
                        self.earn_token.read().transfer(beneficiary, transfer_amount),
                        'Token transfer failed',
                    );
                }
                i += 1;
            }

            // Clear vesting count
            self.user_vesting_count.entry(beneficiary).write(0);

            // Emit event (matches Solidity)
            self
                .emit(
                    TokensReleasedImmediately {
                        category_id: total_amount - remaining_amount,
                        recipient: beneficiary,
                        amount: total_amount,
                    },
                );
        }

        // Get user vesting details
        fn get_user_vesting_details(
            self: @ContractState, beneficiary: ContractAddress,
        ) -> Array<(u32, ContractAddress, u64, u64, u64, u64, u256, u256)> {
            let vesting_count = self.user_vesting_count.entry(beneficiary).read();
            let mut details = ArrayTrait::new();
            let mut i: u32 = 0;

            while i < vesting_count {
                let schedule = (
                    i,
                    self.vesting_beneficiary.entry((beneficiary, i)).read(),
                    self.vesting_cliff.entry((beneficiary, i)).read(),
                    self.vesting_start.entry((beneficiary, i)).read(),
                    self.vesting_duration.entry((beneficiary, i)).read(),
                    self.vesting_slice_period.entry((beneficiary, i)).read(),
                    self.vesting_amount_total.entry((beneficiary, i)).read(),
                    self.vesting_released.entry((beneficiary, i)).read(),
                );
                details.append(schedule);
                i += 1;
            }
            details
        }

        // Get user vesting count
        fn get_user_vesting_count(self: @ContractState, beneficiary: ContractAddress) -> u32 {
            self.user_vesting_count.entry(beneficiary).read()
        }

        // Get specific vesting schedule
        fn get_vesting_schedule(
            self: @ContractState, beneficiary: ContractAddress, index: u32,
        ) -> (ContractAddress, u64, u64, u64, u64, u256, u256) {
            (
                self.vesting_beneficiary.entry((beneficiary, index)).read(),
                self.vesting_cliff.entry((beneficiary, index)).read(),
                self.vesting_start.entry((beneficiary, index)).read(),
                self.vesting_duration.entry((beneficiary, index)).read(),
                self.vesting_slice_period.entry((beneficiary, index)).read(),
                self.vesting_amount_total.entry((beneficiary, index)).read(),
                self.vesting_released.entry((beneficiary, index)).read(),
            )
        }

        // Set fee recipient
        fn set_fee_recipient(ref self: ContractState, recipient: ContractAddress) {
            self.ownable.assert_only_owner();
            assert(!recipient.is_zero(), 'Zero address');
            self.fee_recipient.write(recipient);
        }

        // Set platform fee percentage
        fn set_platform_fee_pct(ref self: ContractState, pct: u64) {
            self.ownable.assert_only_owner();
            assert(pct <= 100, 'Pct>100');
            self.platform_fee_pct.write(pct);
        }

        // Update merchandise admin wallet
        fn update_merchandise_admin_wallet(ref self: ContractState, merch_wallet: ContractAddress) {
            self.ownable.assert_only_owner();
            self.merchandise_admin_wallet.write(merch_wallet);
        }

        // Update earnStarkManager address
        fn update_earn_stark_manager_address(
            ref self: ContractState, contract_addr: ContractAddress,
        ) {
            self.ownable.assert_only_owner();
            self.earn_stark_manager.write(contract_addr);
        }

        // Get fee recipient
        fn get_fee_recipient(self: @ContractState) -> ContractAddress {
            self.fee_recipient.read()
        }

        // Get platform fee percentage
        fn get_platform_fee_pct(self: @ContractState) -> u64 {
            self.platform_fee_pct.read()
        }

        // Get merchandise admin wallet
        fn get_merchandise_admin_wallet(self: @ContractState) -> ContractAddress {
            self.merchandise_admin_wallet.read()
        }

        // Get earnStarkManager address
        fn get_earn_stark_manager(self: @ContractState) -> ContractAddress {
            self.earn_stark_manager.read()
        }

        // Get default vesting time
        fn get_default_vesting_time(self: @ContractState) -> u64 {
            self.default_vesting_time.read()
        }

        // Get total amount vested
        fn get_total_amount_vested(self: @ContractState) -> u256 {
            self.total_amount_vested.read()
        }

        // Give a tip (matches Solidity giveATip)
        fn give_a_tip(ref self: ContractState, receiver: ContractAddress, tip_amount: u256) {
            let sender = get_caller_address();
            assert(!receiver.is_zero(), 'Invalid receiver address');

            let wallet_avail = self.earn_token.read().balance_of(sender);
            let vesting_avail = self.earn_balance.entry(sender).read();
            assert(wallet_avail + vesting_avail >= tip_amount, 'Insufficient total funds');

            // Skip fees for merchandise wallet
            let merch_wallet = self.merchandise_admin_wallet.read();
            let is_merch = receiver == merch_wallet;
            let fee_pct = if is_merch {
                0
            } else {
                self.platform_fee_pct.read()
            };

            // Calculate current vesting pools
            let (total_releasable, total_remaining) = self.calculate_releasable_amount(sender);
            let fee_amount = (tip_amount * fee_pct.into()) / 100;

            // Wallet-based fee & net
            let wallet_fee = if wallet_avail >= fee_amount {
                fee_amount
            } else {
                wallet_avail
            };
            if wallet_fee > 0 {
                let fee_recip = self.fee_recipient.read();
                assert(
                    self.earn_token.read().transfer_from(sender, fee_recip, wallet_fee),
                    'Fee transfer failed',
                );
            }

            let wallet_net = if tip_amount <= wallet_avail {
                tip_amount - wallet_fee
            } else {
                wallet_avail - wallet_fee
            };
            if wallet_net > 0 {
                assert(
                    self.earn_token.read().transfer_from(sender, receiver, wallet_net),
                    'Net transfer failed',
                );
            }

            // Vesting-based fee
            let vesting_fee = if fee_amount > wallet_fee {
                fee_amount - wallet_fee
            } else {
                0
            };
            let mut adjusted_releasable = total_releasable;

            if vesting_fee > 0 {
                assert(vesting_fee <= vesting_avail, 'Insufficient vesting fee');

                self
                    .stearn_balance
                    .entry(sender)
                    .write(self.stearn_balance.entry(sender).read() - vesting_fee);
                self
                    .earn_balance
                    .entry(sender)
                    .write(self.earn_balance.entry(sender).read() - vesting_fee);

                let fee_recip = self.fee_recipient.read();
                self
                    .stearn_balance
                    .entry(fee_recip)
                    .write(self.stearn_balance.entry(fee_recip).read() + vesting_fee);
                self
                    .earn_balance
                    .entry(fee_recip)
                    .write(self.earn_balance.entry(fee_recip).read() + vesting_fee);

                let now = get_block_timestamp();
                self._create_vesting_schedule(fee_recip, now, 0, 0, 0, vesting_fee);
                self._update_vesting_after_tip(sender, vesting_fee);

                adjusted_releasable =
                    if total_releasable > vesting_fee {
                        total_releasable - vesting_fee
                    } else {
                        0
                    };
            }

            // Vesting-based net tip
            let vesting_net = tip_amount - wallet_fee - wallet_net - vesting_fee;
            if vesting_net > 0 {
                self
                    ._process_net_tip_vesting(
                        sender, receiver, vesting_net, adjusted_releasable, total_remaining,
                    );
            }

            self.emit(TipGiven { giver: sender, receiver, amount: tip_amount });
        }

        // Release vested for admin wallets (matches Solidity releaseVestedAdmins)
        fn release_vested_admins(ref self: ContractState) {
            let caller = get_caller_address();
            let merch = self.merchandise_admin_wallet.read();
            let fee_recip = self.fee_recipient.read();
            assert(caller == merch || caller == fee_recip, 'Not authorized');

            self._adjust_stearn_balance(caller);

            let vesting_count = self.user_vesting_count.entry(caller).read();
            assert(vesting_count > 0, 'No vesting schedules');

            // Sum all schedules
            let mut total_to_release: u256 = 0;
            let mut i: u32 = 0;
            while i < vesting_count {
                let amt_total = self.vesting_amount_total.entry((caller, i)).read();
                let released = self.vesting_released.entry((caller, i)).read();
                let available = amt_total - released;
                if available > 0 {
                    total_to_release += available;
                    self.vesting_released.entry((caller, i)).write(amt_total);
                }
                i += 1;
            }

            // Wipe all vesting state
            self.user_vesting_count.entry(caller).write(0);
            self.earn_balance.entry(caller).write(0);
            self.stearn_balance.entry(caller).write(0);

            assert(total_to_release > 0, 'No vested tokens');
            assert(self.earn_token.read().transfer(caller, total_to_release), 'Transfer failed');

            self
                .emit(
                    TokensReleasedImmediately {
                        category_id: 0, recipient: caller, amount: total_to_release,
                    },
                );
        }

        // Preview vesting parameters
        fn preview_vesting_params(
            self: @ContractState, beneficiary: ContractAddress,
        ) -> (u64, u64) {
            let staking_addr = self.staking_contract.read();
            let staking = IEarnscapeStakingDispatcher { contract_address: staking_addr };
            let (categories, levels, _, _) = staking.get_user_data(beneficiary);

            let mut vesting_duration = self.default_vesting_time.read();
            let category_v: felt252 = 'V';
            let mut i: u32 = 0;

            while i < categories.len() {
                if *categories.at(i) == category_v {
                    let level = *levels.at(i);
                    if level == 1 {
                        vesting_duration = 144000; // 2400 minutes
                    } else if level == 2 {
                        vesting_duration = 123420; // 2057 minutes
                    } else if level == 3 {
                        vesting_duration = 108000; // 1800 minutes
                    } else if level == 4 {
                        vesting_duration = 96000; // 1600 minutes
                    } else if level == 5 {
                        vesting_duration = 86400; // 1440 minutes
                    }
                    break;
                }
                i += 1;
            }

            let start = get_block_timestamp();
            (start, vesting_duration)
        }
    }
}

// Public interface matching Solidity contract
#[starknet::interface]
trait IVesting<TContractState> {
    // Admin functions
    fn update_earn_stark_manager(
        ref self: TContractState, earn_stark_manager: starknet::ContractAddress,
    );
    fn update_staking_contract(
        ref self: TContractState, staking_contract: starknet::ContractAddress,
    );
    fn set_fee_recipient(ref self: TContractState, recipient: starknet::ContractAddress);
    fn set_platform_fee_pct(ref self: TContractState, pct: u64);
    fn update_merchandise_admin_wallet(
        ref self: TContractState, merch_wallet: starknet::ContractAddress,
    );
    fn update_earn_stark_manager_address(
        ref self: TContractState, contract_addr: starknet::ContractAddress,
    );

    // Balance management
    fn get_earn_balance(self: @TContractState, beneficiary: starknet::ContractAddress) -> u256;
    fn update_earn_balance(ref self: TContractState, user: starknet::ContractAddress, amount: u256);
    fn get_stearn_balance(self: @TContractState, beneficiary: starknet::ContractAddress) -> u256;
    fn update_stearn_balance(
        ref self: TContractState, user: starknet::ContractAddress, amount: u256,
    );
    fn st_earn_transfer(ref self: TContractState, sender: starknet::ContractAddress, amount: u256);

    // Vesting operations
    fn deposit_earn(ref self: TContractState, beneficiary: starknet::ContractAddress, amount: u256);
    fn calculate_releasable_amount(
        self: @TContractState, beneficiary: starknet::ContractAddress,
    ) -> (u256, u256);
    fn release_vested_amount(ref self: TContractState, beneficiary: starknet::ContractAddress);
    fn force_release_vested_amount(
        ref self: TContractState, beneficiary: starknet::ContractAddress,
    );
    fn release_vested_admins(ref self: TContractState);

    // Vesting queries
    fn get_user_vesting_count(self: @TContractState, beneficiary: starknet::ContractAddress) -> u32;
    fn get_vesting_schedule(
        self: @TContractState, beneficiary: starknet::ContractAddress, index: u32,
    ) -> (starknet::ContractAddress, u64, u64, u64, u64, u256, u256);
    fn get_user_vesting_details(
        self: @TContractState, beneficiary: starknet::ContractAddress,
    ) -> Array<(u32, starknet::ContractAddress, u64, u64, u64, u64, u256, u256)>;
    fn preview_vesting_params(
        self: @TContractState, beneficiary: starknet::ContractAddress,
    ) -> (u64, u64);

    // Configuration getters
    fn get_fee_recipient(self: @TContractState) -> starknet::ContractAddress;
    fn get_platform_fee_pct(self: @TContractState) -> u64;
    fn get_merchandise_admin_wallet(self: @TContractState) -> starknet::ContractAddress;
    fn get_earn_stark_manager(self: @TContractState) -> starknet::ContractAddress;
    fn get_default_vesting_time(self: @TContractState) -> u64;
    fn get_total_amount_vested(self: @TContractState) -> u256;

    // Tipping
    fn give_a_tip(ref self: TContractState, receiver: starknet::ContractAddress, tip_amount: u256);
}
