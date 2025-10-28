#[starknet::contract]
mod EarnscapeBulkVesting {
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_contract_address};

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    // Interface for escrow
    #[starknet::interface]
    trait IEscrow<TContractState> {
        fn withdraw_to_contract4(ref self: TContractState, amount: u256);
    }

    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        token: IERC20Dispatcher,
        escrow: ContractAddress, // Escrow contract
        earn_stark_manager: ContractAddress, // EarnStarkManager contract
        total_amount_vested: u256,
        cliff_period: u64,
        sliced_period: u64,
        category_names: Map<u8, felt252>,
        category_supply: Map<u8, u256>,
        category_remaining_supply: Map<u8, u256>,
        category_vesting_duration: Map<u8, u64>,
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
        UserAdded: UserAdded,
        VestingScheduleCreated: VestingScheduleCreated,
        SupplyUpdated: SupplyUpdated,
        TokensReleasedImmediately: TokensReleasedImmediately,
    }

    #[derive(Drop, starknet::Event)]
    struct UserAdded {
        #[key]
        category_id: u8,
        name: felt252,
        user_address: ContractAddress,
        amount: u256,
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
    struct SupplyUpdated {
        #[key]
        category_id: u8,
        additional_supply: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct TokensReleasedImmediately {
        #[key]
        category_id: u8,
        recipient: ContractAddress,
        amount: u256,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        earn_stark_manager: ContractAddress,
        escrow_address: ContractAddress,
        token_address: ContractAddress,
        owner: ContractAddress,
    ) {
        self.ownable.initializer(owner);
        self.earn_stark_manager.write(earn_stark_manager);
        self.escrow.write(escrow_address);
        self.token.write(IERC20Dispatcher { contract_address: token_address });
        self.cliff_period.write(0);
        self.sliced_period.write(60);
        self._initialize_categories();
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _initialize_categories(ref self: ContractState) {
            self.category_names.entry(0).write('Seed Investors');
            let seed_amount = 2500000 * 1000000000000000000;
            self.category_supply.entry(0).write(seed_amount);
            self.category_remaining_supply.entry(0).write(seed_amount);
            self.category_vesting_duration.entry(0).write(300);

            self.category_names.entry(1).write('Private Investors');
            let private_amount = 2500000 * 1000000000000000000;
            self.category_supply.entry(1).write(private_amount);
            self.category_remaining_supply.entry(1).write(private_amount);
            self.category_vesting_duration.entry(1).write(300);

            self.category_names.entry(2).write('KOL Investors');
            let kol_amount = 1600000 * 1000000000000000000;
            self.category_supply.entry(2).write(kol_amount);
            self.category_remaining_supply.entry(2).write(kol_amount);
            self.category_vesting_duration.entry(2).write(300);

            self.category_names.entry(3).write('Public Sale');
            let public_amount = 2000000 * 1000000000000000000;
            self.category_supply.entry(3).write(public_amount);
            self.category_remaining_supply.entry(3).write(public_amount);
            self.category_vesting_duration.entry(3).write(0);

            self.category_names.entry(4).write('Ecosystem Rewards');
            let ecosystem_amount = 201333333 * 1000000000000000000;
            self.category_supply.entry(4).write(ecosystem_amount);
            self.category_remaining_supply.entry(4).write(ecosystem_amount);
            self.category_vesting_duration.entry(4).write(300);

            self.category_names.entry(5).write('Airdrops');
            let airdrop_amount = 50000000 * 1000000000000000000;
            self.category_supply.entry(5).write(airdrop_amount);
            self.category_remaining_supply.entry(5).write(airdrop_amount);
            self.category_vesting_duration.entry(5).write(300);

            self.category_names.entry(6).write('Development Reserve');
            let dev_amount = 200000000 * 1000000000000000000;
            self.category_supply.entry(6).write(dev_amount);
            self.category_remaining_supply.entry(6).write(dev_amount);
            self.category_vesting_duration.entry(6).write(300);

            self.category_names.entry(7).write('Liquidity&Market'); // Limited by felt252 length
            let liquidity_amount = 150000000 * 1000000000000000000;
            self.category_supply.entry(7).write(liquidity_amount);
            self.category_remaining_supply.entry(7).write(liquidity_amount);
            self.category_vesting_duration.entry(7).write(0);

            self.category_names.entry(8).write('Team & Advisors');
            let team_amount = 200000000 * 1000000000000000000;
            self.category_supply.entry(8).write(team_amount);
            self.category_remaining_supply.entry(8).write(team_amount);
            self.category_vesting_duration.entry(8).write(300);
        }

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
    }

    #[abi(embed_v0)]
    impl EarnscapeBulkVestingImpl of super::IEarnscapeBulkVesting<ContractState> {
        fn add_user_data(
            ref self: ContractState,
            category_id: u8,
            names: Span<felt252>,
            user_addresses: Span<ContractAddress>,
            amounts: Span<u256>,
        ) {
            self.ownable.assert_only_owner();
            assert(category_id < 9, 'Invalid category');
            assert(names.len() == user_addresses.len(), 'Length mismatch');
            assert(user_addresses.len() == amounts.len(), 'Length mismatch');
            let mut i: u32 = 0;
            let len = user_addresses.len();
            while i < len {
                let name = *names.at(i);
                let user_address = *user_addresses.at(i);
                let amount = *amounts.at(i);
                let mut remaining = self.category_remaining_supply.entry(category_id).read();
                if remaining < amount {
                    let needed = amount - remaining;
                    assert(
                        category_id == 0 || category_id == 1 || category_id == 2,
                        'Cannot withdraw for category',
                    );
                    let escrow_dispatcher = IEscrowDispatcher {
                        contract_address: self.escrow.read(),
                    };
                    escrow_dispatcher.withdraw_to_contract4(needed);
                    let new_supply = self.category_supply.entry(category_id).read() + needed;
                    self.category_supply.entry(category_id).write(new_supply);
                    remaining += needed;
                    self.category_remaining_supply.entry(category_id).write(remaining);
                }
                assert(remaining >= amount, 'Insufficient category supply');
                self.category_remaining_supply.entry(category_id).write(remaining - amount);
                self.emit(UserAdded { category_id, name, user_address, amount });
                let start = get_block_timestamp();
                let duration = self.category_vesting_duration.entry(category_id).read();
                let cliff = self.cliff_period.read();
                let slice_period = self.sliced_period.read();
                self
                    ._create_vesting_schedule(
                        user_address, start, cliff, duration, slice_period, amount,
                    );
                i += 1;
            };
        }

        fn calculate_releasable_amount(
            ref self: ContractState, beneficiary: ContractAddress,
        ) -> (u256, u256) {
            let vesting_count = self.user_vesting_count.entry(beneficiary).read();
            let mut total_releasable: u256 = 0;
            let mut total_remaining: u256 = 0;
            let mut i: u32 = 0;
            while i < vesting_count {
                let (releasable, remaining) = self._compute_releasable_amount(beneficiary, i);
                total_releasable += releasable;
                total_remaining += remaining;
                i += 1;
            }
            (total_releasable, total_remaining)
        }

        fn release_vested_amount(ref self: ContractState, beneficiary: ContractAddress) {
            self.ownable.assert_only_owner();
            let (releasable, _) = self.calculate_releasable_amount(beneficiary);
            assert(releasable > 0, 'No releasable amount');
            let mut remaining_amount = releasable;
            let vesting_count = self.user_vesting_count.entry(beneficiary).read();
            let mut i: u32 = 0;
            while i < vesting_count && remaining_amount > 0 {
                let (releasable_amount, _) = self._compute_releasable_amount(beneficiary, i);
                if releasable_amount > 0 {
                    let release_amount = if releasable_amount > remaining_amount {
                        remaining_amount
                    } else {
                        releasable_amount
                    };
                    let current_released = self.vesting_released.entry((beneficiary, i)).read();
                    self
                        .vesting_released
                        .entry((beneficiary, i))
                        .write(current_released + release_amount);
                    remaining_amount -= release_amount;
                    self.token.read().transfer(beneficiary, release_amount);
                }
                i += 1;
            };
        }

        fn release_immediately(
            ref self: ContractState, category_id: u8, recipient: ContractAddress,
        ) {
            self.ownable.assert_only_owner();
            assert(category_id == 3 || category_id == 7, 'Only Public/Liquidity allowed');
            let amount = self.category_remaining_supply.entry(category_id).read();
            assert(amount > 0, 'No remaining supply');
            self.category_remaining_supply.entry(category_id).write(0);
            self.token.read().transfer(recipient, amount);
            self.emit(TokensReleasedImmediately { category_id, recipient, amount });
        }

        fn update_category_supply(
            ref self: ContractState, category_id: u8, additional_supply: u256,
        ) {
            self.ownable.assert_only_owner();
            assert(category_id < 9, 'Invalid category');
            let current_remaining = self.category_remaining_supply.entry(category_id).read();
            self
                .category_remaining_supply
                .entry(category_id)
                .write(current_remaining + additional_supply);
            self.emit(SupplyUpdated { category_id, additional_supply });
        }

        fn get_category_details(
            self: @ContractState, category_id: u8,
        ) -> (felt252, u256, u256, u64) {
            assert(category_id < 9, 'Invalid category');
            (
                self.category_names.entry(category_id).read(),
                self.category_supply.entry(category_id).read(),
                self.category_remaining_supply.entry(category_id).read(),
                self.category_vesting_duration.entry(category_id).read(),
            )
        }

        fn get_user_vesting_count(self: @ContractState, beneficiary: ContractAddress) -> u32 {
            self.user_vesting_count.entry(beneficiary).read()
        }

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

        fn get_total_amount_vested(self: @ContractState) -> u256 {
            self.total_amount_vested.read()
        }

        fn get_earn_stark_manager(self: @ContractState) -> ContractAddress {
            self.earn_stark_manager.read()
        }

        fn get_escrow_contract(self: @ContractState) -> ContractAddress {
            self.escrow.read()
        }

        fn get_token_address(self: @ContractState) -> ContractAddress {
            self.token.read().contract_address
        }

        // Emergency function to recover stuck tokens
        fn recover_stuck_token(
            ref self: ContractState, token_address: ContractAddress, amount: u256,
        ) {
            self.ownable.assert_only_owner();
            let token = IERC20Dispatcher { contract_address: token_address };
            let balance = token.balance_of(get_contract_address());
            assert(balance >= amount, 'Insufficient balance to recover');
            let owner = self.ownable.owner();
            token.transfer(owner, amount);
        }
    }
}

#[starknet::interface]
trait IEarnscapeBulkVesting<TContractState> {
    fn add_user_data(
        ref self: TContractState,
        category_id: u8,
        names: Span<felt252>,
        user_addresses: Span<starknet::ContractAddress>,
        amounts: Span<u256>,
    );
    fn calculate_releasable_amount(
        ref self: TContractState, beneficiary: starknet::ContractAddress,
    ) -> (u256, u256);
    fn release_vested_amount(ref self: TContractState, beneficiary: starknet::ContractAddress);
    fn release_immediately(
        ref self: TContractState, category_id: u8, recipient: starknet::ContractAddress,
    );
    fn update_category_supply(ref self: TContractState, category_id: u8, additional_supply: u256);
    fn get_category_details(self: @TContractState, category_id: u8) -> (felt252, u256, u256, u64);
    fn get_user_vesting_count(self: @TContractState, beneficiary: starknet::ContractAddress) -> u32;
    fn get_vesting_schedule(
        self: @TContractState, beneficiary: starknet::ContractAddress, index: u32,
    ) -> (starknet::ContractAddress, u64, u64, u64, u64, u256, u256);
    fn get_total_amount_vested(self: @TContractState) -> u256;
    fn get_earn_stark_manager(self: @TContractState) -> starknet::ContractAddress;
    fn get_escrow_contract(self: @TContractState) -> starknet::ContractAddress;
    fn get_token_address(self: @TContractState) -> starknet::ContractAddress;
    fn recover_stuck_token(
        ref self: TContractState, token_address: starknet::ContractAddress, amount: u256,
    );
}
