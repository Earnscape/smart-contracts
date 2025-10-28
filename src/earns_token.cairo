// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts for Cairo ^0.20.0

#[starknet::contract]
mod EarnsToken {
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::token::erc20::{ERC20Component, ERC20HooksEmptyImpl};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_contract_address};

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    // ERC20 Mixin
    #[abi(embed_v0)]
    impl ERC20MixinImpl = ERC20Component::ERC20MixinImpl<ContractState>;
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    // Ownable Mixin
    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        contract4: ContractAddress, // BulkVesting address
        contract5: ContractAddress // Escrow address
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
    }

    const TOTAL_SUPPLY: u256 = 1_000_000_000_000_000_000_000_000_000; // 1 billion * 10^18

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        // Initialize ERC20
        self.erc20.initializer("EARNS", "EARN");

        // Initialize Ownable
        self.ownable.initializer(owner);

        // Mint total supply to contract itself
        let contract_address = get_contract_address();
        self.erc20.mint(contract_address, TOTAL_SUPPLY);
    }

    #[abi(embed_v0)]
    impl EarnsTokenImpl of super::IEarnsToken<ContractState> {
        fn set_contract4_and_contract5(
            ref self: ContractState, _contract4: ContractAddress, _contract5: ContractAddress,
        ) {
            assert(_contract4.is_non_zero() && _contract5.is_non_zero(), 'Invalid addresses');
            assert(_contract4 != _contract5, 'Addresses cannot be the same');
            self.ownable.assert_only_owner();
            self.contract4.write(_contract4);
            self.contract5.write(_contract5);
        }

        fn renounce_ownership_with_transfer(ref self: ContractState, sold_supply: u256) {
            self.ownable.assert_only_owner();

            assert(sold_supply <= TOTAL_SUPPLY, 'Sold supply exceeds total');

            let contract4_addr = self.contract4.read();
            let contract5_addr = self.contract5.read();
            assert(contract4_addr.is_non_zero(), 'Contract4 not set');
            assert(contract5_addr.is_non_zero(), 'Contract5 not set');

            let unsold_supply = TOTAL_SUPPLY - sold_supply;
            let contract_addr = get_contract_address();

            // Transfer unsold supply to contract5 (Escrow)
            if unsold_supply > 0 {
                self.erc20._transfer(contract_addr, contract5_addr, unsold_supply);
            }

            // Transfer sold supply to contract4 (BulkVesting)
            if sold_supply > 0 {
                self.erc20._transfer(contract_addr, contract4_addr, sold_supply);
            }

            // Renounce ownership
            self.ownable.renounce_ownership();
        }

        fn get_contract4(self: @ContractState) -> ContractAddress {
            self.contract4.read()
        }

        fn get_contract5(self: @ContractState) -> ContractAddress {
            self.contract5.read()
        }
    }
}

#[starknet::interface]
trait IEarnsToken<TContractState> {
    fn set_contract4_and_contract5(
        ref self: TContractState,
        _contract4: starknet::ContractAddress,
        _contract5: starknet::ContractAddress,
    );
    fn renounce_ownership_with_transfer(ref self: TContractState, sold_supply: u256);
    fn get_contract4(self: @TContractState) -> starknet::ContractAddress;
    fn get_contract5(self: @TContractState) -> starknet::ContractAddress;
}
