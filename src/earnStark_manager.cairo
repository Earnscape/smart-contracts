// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts for Cairo ^0.20.0

#[starknet::contract]
mod EarnSTARKManager {
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_contract_address};

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    // Interface for Vesting Contract
    #[starknet::interface]
    trait IEarnscapeVesting<TContractState> {
        fn deposit_earn(ref self: TContractState, beneficiary: ContractAddress, amount: u256);
    }

    // ETH token contract address on Starknet
    const ETH_TOKEN_ADDRESS: felt252 =
        0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        earns: ContractAddress,
        vesting: ContractAddress // Individual Vesting contract, NOT bulk vesting
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, earns: ContractAddress) {
        self.ownable.initializer(owner);
        self.earns.write(earns);
    }

    #[abi(embed_v0)]
    impl EarnSTARKManagerImpl of super::IEarnSTARKManager<ContractState> {
        // Read vesting contract address
        fn vesting(self: @ContractState) -> ContractAddress {
            self.vesting.read()
        }

        // Transfer specified amount of EARNS tokens
        fn transfer_earns(ref self: ContractState, recipient: ContractAddress, amount: u256) {
            self.ownable.assert_only_owner();
            let earns_addr = self.earns.read();
            let earns_token = IERC20Dispatcher { contract_address: earns_addr };
            let balance = earns_token.balance_of(get_contract_address());
            assert(balance >= amount, 'Insufficient earns balance');
            earns_token.transfer(recipient, amount);
        }

        // Transfer ETH from the contract (native token on Starknet)
        fn transfer_eth(ref self: ContractState, recipient: ContractAddress, amount: u256) {
            self.ownable.assert_only_owner();
            // Note: Starknet uses ETH as native token, not XDC
            // Native ETH transfers require a different approach in Cairo
            // This would typically use the ETH token contract on Starknet
            let eth_token = IERC20Dispatcher {
                contract_address: ETH_TOKEN_ADDRESS.try_into().unwrap(),
            };
            let balance = eth_token.balance_of(get_contract_address());
            assert(balance >= amount, 'Insufficient ETH balance');
            eth_token.transfer(recipient, amount);
        }

        // Read current EARNS balance
        fn get_earns_balance(self: @ContractState) -> u256 {
            let earns_addr = self.earns.read();
            let earns_token = IERC20Dispatcher { contract_address: earns_addr };
            earns_token.balance_of(get_contract_address())
        }

        // Read current ETH balance
        fn get_eth_balance(self: @ContractState) -> u256 {
            let eth_token = IERC20Dispatcher {
                contract_address: ETH_TOKEN_ADDRESS.try_into().unwrap(),
            };
            eth_token.balance_of(get_contract_address())
        }

        // Deposit EARNS to vesting contract
        fn earn_deposit_to_vesting(
            ref self: ContractState, receiver: ContractAddress, amount: u256,
        ) {
            self.ownable.assert_only_owner();
            let earns_addr = self.earns.read();
            let vesting_addr = self.vesting.read();

            // Transfer EARNS to vesting contract
            let earns_token = IERC20Dispatcher { contract_address: earns_addr };
            let balance = earns_token.balance_of(get_contract_address());
            assert(balance >= amount, 'Insufficient earns balance');
            earns_token.transfer(vesting_addr, amount);

            // Call vesting contract's depositEarn function
            let vesting = IEarnscapeVestingDispatcher { contract_address: vesting_addr };
            vesting.deposit_earn(receiver, amount);
        }

        // Set vesting contract address (individual vesting, NOT bulk vesting)
        fn set_vesting_address(ref self: ContractState, vesting: ContractAddress) {
            self.ownable.assert_only_owner();
            self.vesting.write(vesting);
        }
    }
}

#[starknet::interface]
trait IEarnSTARKManager<TContractState> {
    fn vesting(self: @TContractState) -> starknet::ContractAddress;
    fn transfer_earns(ref self: TContractState, recipient: starknet::ContractAddress, amount: u256);
    fn transfer_eth(ref self: TContractState, recipient: starknet::ContractAddress, amount: u256);
    fn get_earns_balance(self: @TContractState) -> u256;
    fn get_eth_balance(self: @TContractState) -> u256;
    fn earn_deposit_to_vesting(
        ref self: TContractState, receiver: starknet::ContractAddress, amount: u256,
    );
    fn set_vesting_address(ref self: TContractState, vesting: starknet::ContractAddress);
}
