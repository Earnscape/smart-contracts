// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20Errors, IERC721Errors, IERC1155Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract stEarn is ERC20, ERC20Burnable, Ownable {

    address public vesting;
    address public stakingContract;
    constructor()
        ERC20("stEarn", "stEarn")
        Ownable(msg.sender)
    {}

    modifier onlyContracts() {
        require(msg.sender == vesting || msg.sender == stakingContract, "You are not allowed to call this function");
        _;
    }

    function mint(address to, uint256 amount) public onlyContracts() {
        _mint(to, amount);
    }

    function burn(address _user,uint256 amount) public  onlyContracts() {
        _burn(_user, amount);
    }

    // Function to set the vesting address; restricted to owner
    function setVestingAddress(address _vesting) external onlyOwner {
        vesting = _vesting;
    }

    // Function to set the staking contract address; restricted to owner
    function setStakingContractAddress(address _stakingContract) external onlyOwner {
        stakingContract = _stakingContract;
    }

    /**
     * @dev Override _transfer function with the following logic:
     * - Users can only transfer tokens to Vesting not Bulk-Vesting, stakingContract, or the burn address (0x0).
     * - The stEarn contract itself (i.e., during minting) can transfer tokens to any user.
     */
    function _transfer(address sender, address recipient, uint256 amount) internal override {
        // Allow transfers if the sender is the contract itself (on minting) and recipient is any user
        if (sender == address(this)) {
            super._transfer(sender, recipient, amount);
        }
        // Allow users to transfer tokens only to Vesting Contract, stakingContract, or the burn address (0x0)
        else if (recipient == vesting || recipient == stakingContract || recipient == address(0)) {
            super._transfer(sender, recipient, amount);
        } else {
            revert("Transfers are only allowed to Vesting, stakingContract, or the burn address");
        }
    }
}