// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts for Cairo ^0.20.0

#[starknet::contract]
mod StEarnToken {
    use core::num::traits::Zero;
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::token::erc20::ERC20Component;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_caller_address, get_contract_address};

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: ERC20Component, storage: erc20, event: ERC20Event);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl ERC20Impl = ERC20Component::ERC20Impl<ContractState>;
    #[abi(embed_v0)]
    impl ERC20CamelOnlyImpl = ERC20Component::ERC20CamelOnlyImpl<ContractState>;
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        vesting_contract: ContractAddress,
        staking_contract: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        ERC20Event: ERC20Component::Event,
        VestingAddressUpdated: VestingAddressUpdated,
        StakingAddressUpdated: StakingAddressUpdated,
    }

    #[derive(Drop, starknet::Event)]
    struct VestingAddressUpdated {
        old_address: ContractAddress,
        new_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct StakingAddressUpdated {
        old_address: ContractAddress,
        new_address: ContractAddress,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.erc20.initializer("stEarn", "stEarn");
        self.ownable.initializer(owner);
    }

    #[abi(embed_v0)]
    impl StEarnImpl of super::IStEarnToken<ContractState> {
        // Read vesting contract address
        fn vesting_contract(self: @ContractState) -> ContractAddress {
            self.vesting_contract.read()
        }

        // Read staking contract address
        fn staking_contract(self: @ContractState) -> ContractAddress {
            self.staking_contract.read()
        }

        fn set_vesting_address(ref self: ContractState, vesting: ContractAddress) {
            self.ownable.assert_only_owner();
            let old_address = self.vesting_contract.read();
            self.vesting_contract.write(vesting);
            self.emit(VestingAddressUpdated { old_address, new_address: vesting });
        }

        fn set_staking_contract_address(
            ref self: ContractState, staking_contract: ContractAddress,
        ) {
            self.ownable.assert_only_owner();
            let old_address = self.staking_contract.read();
            self.staking_contract.write(staking_contract);
            self
                .emit(
                    StakingAddressUpdated {
                        old_address: old_address, new_address: staking_contract,
                    },
                );
        }

        fn mint(ref self: ContractState, to: ContractAddress, amount: u256) {
            // Only callable by vesting or staking contract
            let caller = get_caller_address();
            let vesting_addr = self.vesting_contract.read();
            let staking_addr = self.staking_contract.read();
            assert(
                vesting_addr.is_non_zero() && staking_addr.is_non_zero(),
                'Contracts not configured',
            );
            assert(caller == vesting_addr || caller == staking_addr, 'Not allowed to call');

            self.erc20.mint(to, amount);
        }

        fn burn(ref self: ContractState, user: ContractAddress, amount: u256) {
            // Only callable by vesting or staking contract
            let caller = get_caller_address();
            let vesting_addr = self.vesting_contract.read();
            let staking_addr = self.staking_contract.read();
            assert(
                vesting_addr.is_non_zero() && staking_addr.is_non_zero(),
                'Contracts not configured',
            );
            assert(caller == vesting_addr || caller == staking_addr, 'Not allowed to call');

            self.erc20.burn(user, amount);
        }
    }

    // Custom transfer hook to restrict transfers
    // Users can only transfer tokens to vesting (NOT bulk vesting), stakingContract, or burn
    // address (0x0)
    // The contract itself (during minting) can transfer to any user
    impl ERC20HooksImpl of ERC20Component::ERC20HooksTrait<ContractState> {
        fn before_update(
            ref self: ERC20Component::ComponentState<ContractState>,
            from: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) {
            let contract_state = ERC20Component::HasComponent::get_contract(@self);
            let contract_address = get_contract_address();
            let vesting = contract_state.vesting_contract.read();
            let staking_contract = contract_state.staking_contract.read();
            let zero_address: ContractAddress = 0.try_into().unwrap();

            // Allow transfers if sender is the contract itself (during minting)
            if from == contract_address {
                return;
            }

            // Allow minting (from zero address)
            if from == zero_address {
                return;
            }

            // Allow transfer to vesting, staking_contract, or burn (to zero)
            if recipient == vesting || recipient == staking_contract || recipient == zero_address {
                return;
            }

            // Otherwise, revert
            panic!("Transfers only allowed to vesting, stakingContract, or burn address");
        }

        fn after_update(
            ref self: ERC20Component::ComponentState<ContractState>,
            from: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) {}
    }
}

#[starknet::interface]
trait IStEarnToken<TContractState> {
    fn vesting_contract(self: @TContractState) -> starknet::ContractAddress;
    fn staking_contract(self: @TContractState) -> starknet::ContractAddress;
    fn set_vesting_address(ref self: TContractState, vesting: starknet::ContractAddress);
    fn set_staking_contract_address(
        ref self: TContractState, staking_contract: starknet::ContractAddress,
    );
    fn mint(ref self: TContractState, to: starknet::ContractAddress, amount: u256);
    fn burn(ref self: TContractState, user: starknet::ContractAddress, amount: u256);
}
