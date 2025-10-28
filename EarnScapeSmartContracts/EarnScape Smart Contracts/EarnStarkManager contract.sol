// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IEarnscapeVesting {
    function depositEarn(address beneficiary, uint256 amount) external;
}

contract EarnStarkManager is Ownable {
    IERC20 public earns;
    IEarnscapeVesting public vesting;
    constructor(address _earns) Ownable(msg.sender) {
        earns = IERC20(_earns);
    }

    // Transfer specified amount of EARNS
    function transferEarns(address recipient, uint256 amount) external onlyOwner {
        require(earns.balanceOf(address(this)) >= amount, "Insufficient earns balance");
        earns.transfer(recipient, amount);
    }

    // transfer STARK from the contract
    function transferSTARK(address recipient,uint256 amount) external onlyOwner {
        require(address(this).balance >= amount, "Insufficient STARK balance");
        payable(recipient).transfer(amount);
    }

    // Read current EARNS balance
    function getEARNSBalance() external view  returns (uint256) {
        return earns.balanceOf(address(this));
    }

    // Read current STARK balance
    function getSTARKBalance() external view  returns (uint256) {
        return address(this).balance;
    }

    function earnDepositToVesting(address _receiver, uint256 _amount) public onlyOwner {
        require(earns.balanceOf(address(this)) >= _amount, "Insufficient earns balance");
        earns.transfer(address(vesting), _amount);
        IEarnscapeVesting(vesting).depositEarn(_receiver,_amount);
    }

    // Function to set the vesting address(not bulk-vesting); restricted to owner
    function setVestingAddress(address _vesting) external onlyOwner {
        vesting = IEarnscapeVesting(_vesting);
    }

    receive() external payable {}
}