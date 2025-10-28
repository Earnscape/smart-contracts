// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts for Cairo ^0.20.0

#[starknet::contract]
mod Escrow {
    use core::num::traits::Zero;
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address, get_contract_address};

    const ONE_DAY_SECONDS: u64 = 86400;

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        earns_token: ContractAddress,
        contract4: ContractAddress,
        earnscape_treasury: ContractAddress,
        deployment_time: u64,
        closing_time: u64,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        TokensTransferred: TokensTransferred,
    }

    #[derive(Drop, starknet::Event)]
    struct TokensTransferred {
        #[key]
        to: ContractAddress,
        amount: u256,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        earns_token: ContractAddress,
        earnscape_treasury: ContractAddress,
    ) {
        self.ownable.initializer(owner);
        self.earns_token.write(earns_token);
        self.earnscape_treasury.write(earnscape_treasury);
        let now = get_block_timestamp();
        self.deployment_time.write(now);
        self.closing_time.write(now + ONE_DAY_SECONDS); // 1440 minutes = 86400 seconds = 1 day
    }

    #[abi(embed_v0)]
    impl EscrowImpl of super::IEscrow<ContractState> {
        // Read contract4 address (BulkVesting)
        fn contract4(self: @ContractState) -> ContractAddress {
            self.contract4.read()
        }

        // Read earns token address
        fn earns_token(self: @ContractState) -> ContractAddress {
            self.earns_token.read()
        }

        // Read treasury address
        fn earnscape_treasury(self: @ContractState) -> ContractAddress {
            self.earnscape_treasury.read()
        }

        fn set_contract4(ref self: ContractState, contract4: ContractAddress) {
            self.ownable.assert_only_owner();
            self.contract4.write(contract4);
        }

        fn transfer_to(ref self: ContractState, to: ContractAddress, amount: u256) {
            self.ownable.assert_only_owner();
            let earns_token = self.earns_token.read();
            let contract = IERC20Dispatcher { contract_address: earns_token };
            let balance = contract.balance_of(get_contract_address());
            assert(balance >= amount, 'Insufficient balance');
            contract.transfer(to, amount);
            self.emit(TokensTransferred { to, amount });
        }

        fn transfer_from(
            ref self: ContractState, from: ContractAddress, to: ContractAddress, amount: u256,
        ) {
            self.ownable.assert_only_owner();
            let earns_token = self.earns_token.read();
            let contract = IERC20Dispatcher { contract_address: earns_token };
            let allowance = contract.allowance(from, get_contract_address());
            assert(allowance >= amount, 'Allowance exceeded');
            contract.transfer_from(from, to, amount);
            self.emit(TokensTransferred { to, amount });
        }

        fn transfer_all(ref self: ContractState) {
            self.ownable.assert_only_owner();
            let earns_token = self.earns_token.read();
            let contract = IERC20Dispatcher { contract_address: earns_token };
            let balance = contract.balance_of(get_contract_address());
            let treasury = self.earnscape_treasury.read();
            contract.transfer(treasury, balance);
            self.emit(TokensTransferred { to: treasury, amount: balance });
        }

        fn withdraw_to_contract4(ref self: ContractState, amount: u256) {
            let caller = get_caller_address();
            let contract4 = self.contract4.read();
            assert(contract4.is_non_zero(), 'Contract 4 not set');
            assert(caller == contract4, 'Only Contract 4');

            let earns_token = self.earns_token.read();
            let contract = IERC20Dispatcher { contract_address: earns_token };
            let balance = contract.balance_of(get_contract_address());
            assert(balance >= amount, 'Insufficient balance');
            contract.transfer(contract4, amount);
            self.emit(TokensTransferred { to: contract4, amount });
        }

        fn get_deployment_time(self: @ContractState) -> u64 {
            self.deployment_time.read()
        }

        fn get_closing_time(self: @ContractState) -> u64 {
            self.closing_time.read()
        }
    }
}

#[starknet::interface]
trait IEscrow<TContractState> {
    fn contract4(self: @TContractState) -> starknet::ContractAddress;
    fn earns_token(self: @TContractState) -> starknet::ContractAddress;
    fn earnscape_treasury(self: @TContractState) -> starknet::ContractAddress;
    fn set_contract4(ref self: TContractState, contract4: starknet::ContractAddress);
    fn transfer_to(ref self: TContractState, to: starknet::ContractAddress, amount: u256);
    fn transfer_from(
        ref self: TContractState,
        from: starknet::ContractAddress,
        to: starknet::ContractAddress,
        amount: u256,
    );
    fn transfer_all(ref self: TContractState);
    fn withdraw_to_contract4(ref self: TContractState, amount: u256);
    fn get_deployment_time(self: @TContractState) -> u64;
    fn get_closing_time(self: @TContractState) -> u64;
}
