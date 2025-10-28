// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20Errors, IERC721Errors, IERC1155Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract EARNS is ERC20, Ownable {
    uint256 private constant TOTAL_SUPPLY = 1000000000 * 10 ** 18;

    address public bulkVesting;
    address public escrow;

    constructor() ERC20("EARNS", "EARN") Ownable(msg.sender) {
        _mint(address(this), TOTAL_SUPPLY);
    }

    function setContracts(address _bulkVesting,address _escrow) external onlyOwner {
        bulkVesting = _bulkVesting;
        escrow = _escrow;
    }

    function finalizeEarn(uint256 soldSupply) external onlyOwner {
        require(soldSupply <= TOTAL_SUPPLY, "Sold supply exceeds total supply");
        uint256 unsoldSupply = TOTAL_SUPPLY - soldSupply;

        if (unsoldSupply > 0) {
            _transfer(address(this), escrow, unsoldSupply);
        }
        _transfer(address(this), bulkVesting, soldSupply);
        renounceOwnership();
    }

}