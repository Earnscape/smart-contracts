// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20Errors, IERC721Errors, IERC1155Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract EarnscapeEscrow is Ownable {
    
    IERC20 public earnsToken;
    address public bulkVesting;
    address public earnscapeTreasury;
    uint256 public deploymentTime;
    uint256 public closingTime;

    event TokensTransferred(address indexed to, uint256 amount);

    modifier onlybulkVesting() {
        require(msg.sender == bulkVesting, "Only bulk-Vesting can call this function");
        _;
    }

    constructor(IERC20 _earnsToken, address _earnscapeTreasury) Ownable(msg.sender) {
        earnsToken = _earnsToken;
        earnscapeTreasury = _earnscapeTreasury;
        deploymentTime = block.timestamp;
        closingTime = deploymentTime + 1440 minutes;
    }

    function setbulkVesting(address _bulkVesting) external onlyOwner {
        bulkVesting = _bulkVesting;
    }

    function transferTo(address to, uint256 amount) external onlyOwner {
        require(amount <= earnsToken.balanceOf(address(this)), "Insufficient balance");
        earnsToken.transfer(to, amount);
        emit TokensTransferred(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external onlyOwner {
        require(amount <= earnsToken.allowance(from, address(this)), "Allowance exceeded");
        earnsToken.transferFrom(from, to, amount);
        emit TokensTransferred(to, amount);
    }

    function transferAll() external onlyOwner {
        uint256 balance = earnsToken.balanceOf(address(this));
        earnsToken.transfer(earnscapeTreasury, balance);
        emit TokensTransferred(earnscapeTreasury, balance);
    }

    function withdrawTobulkVesting(uint256 amount) external onlybulkVesting {
        require(amount <= earnsToken.balanceOf(address(this)), "Insufficient balance");
        earnsToken.transfer(bulkVesting, amount);
        emit TokensTransferred(bulkVesting, amount);
    }
}