// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";


interface IEarnscapeEscrow {
    function withdrawToContract4(uint256 amount) external;
}

contract EarnscapeBulkVesting is Ownable {

    IERC20 public token;
    IEarnscapeEscrow public EarnscapeEscrow;

    address public earnStarkManager;
    uint256 public totalAmountVested;

    uint256 private  cliffPeriod = 0 minutes;
    uint256 public  slicedPeriod = 1 minutes;

    struct Category {
        string name;
        uint256 supply;
        uint256 remainingSupply;
        uint256 vestingDuration;
    }

    struct UserData {
        string name;
        address userAddress;
        uint256 amount;
        uint256 vestingTime;
    }

    struct VestingSchedule {
        address beneficiary;
        uint256 cliff;
        uint256 start;
        uint256 duration;
        uint256 slicePeriodSeconds;
        uint256 amountTotal;
        uint256 released;
    }

    struct VestingDetail {
        uint256 index;
        VestingSchedule schedule;
    }

    mapping(uint256 => Category) private categories;
    mapping(uint256 => UserData[]) private categoryUsers;
    mapping(address => mapping(uint256 => VestingSchedule)) private vestedUserDetail;
    mapping(address => uint256) private holdersVestingCount;

    event UserAdded(uint256 indexed categoryId, string name, address userAddress, uint256 amount);
    event VestingScheduleCreated(address indexed beneficiary, uint256 start, uint256 cliff, uint256 duration, uint256 slicePeriodSeconds, uint256 amount);
    event SupplyUpdated(uint256 indexed categoryId, uint256 additionalSupply);
    event TokensReleasedImmediately(uint256 indexed categoryId, address recipient, uint256 amount);

    constructor(address _earnStarkManager,address _EarnscapeEscrowAddress, address _earnTokenAddress) Ownable(msg.sender) {
        earnStarkManager = _earnStarkManager;
        EarnscapeEscrow = IEarnscapeEscrow(_EarnscapeEscrowAddress);
        token = IERC20(_earnTokenAddress);
        _initializeCategories();
    }

    function _initializeCategories() internal {
        categories[0] = Category("Seed Investors", 2500000  * 10**18, 2500000 * 10**18, 5 minutes);  // for testing change to 50% (66666667)
        categories[1] = Category("Private Investors", 2500000 * 10**18, 2500000 * 10**18, 5 minutes);
        categories[2] = Category("KOL Investors", 1600000 * 10**18, 1600000 * 10**18, 5 minutes);
        categories[3] = Category("Public Sale", 2000000 * 10**18, 2000000 * 10**18, 0);
        categories[4] = Category("Ecosystem Rewards", 201333333 * 10**18, 201333333 * 10**18, 5 minutes);
        categories[5] = Category("Airdrops", 50000000 * 10**18, 50000000 * 10**18, 5 minutes);
        categories[6] = Category("Development Reserve", 200000000 * 10**18, 200000000 * 10**18, 5 minutes);
        categories[7] = Category("Liquidity & Market Making", 150000000 * 10**18, 150000000 * 10**18, 0);
        categories[8] = Category("Team & Advisors", 200000000 * 10**18, 200000000 * 10**18, 5 minutes);
    }

    function addUserData(
        uint256 categoryId,
        string[] memory names,
        address[] memory userAddresses,
        uint256[] memory amounts
    ) public onlyOwner {
        require(names.length == userAddresses.length && userAddresses.length == amounts.length, "Array length mismatch");

        for (uint256 i = 0; i < userAddresses.length; i++) {
            if (categories[categoryId].remainingSupply < amounts[i]) {
                uint256 neededAmount = amounts[i] - categories[categoryId].remainingSupply;
               if (categoryId == 0 || categoryId == 1 || categoryId == 2) {
                    IEarnscapeEscrow(EarnscapeEscrow).withdrawToContract4(neededAmount);
                    categories[categoryId].supply += neededAmount;
                    categories[categoryId].remainingSupply += neededAmount;
                } else {
                    revert("Insufficient category supply and withdraw not allowed for this category");
                }
               // also add needamount in supply to track tsupply distributed.
            }

            require(categories[categoryId].remainingSupply >= amounts[i], "Insufficient category supply");
            categories[categoryId].remainingSupply -= amounts[i];
            categoryUsers[categoryId].push(UserData(names[i], userAddresses[i], amounts[i], categories[categoryId].vestingDuration));
            emit UserAdded(categoryId, names[i], userAddresses[i], amounts[i]);
            // Create vesting schedule for the user
            createVestingSchedule(
                userAddresses[i],
                block.timestamp,
                cliffPeriod,
                categories[categoryId].vestingDuration,
                slicedPeriod,
                amounts[i]
            );
        }
    }

    function createVestingSchedule(
        address _beneficiary,
        uint256 _start,
        uint256 _cliff,
        uint256 _duration,
        uint256 _slicePeriodSeconds,
        uint256 _amount
    ) internal {
        require(_duration >= _cliff, "TokenVesting: duration must be >= cliff");
        uint256 cliff = _start + _cliff;
        uint256 currentVestingIndex = holdersVestingCount[_beneficiary]++;
        vestedUserDetail[_beneficiary][currentVestingIndex] = VestingSchedule(
            _beneficiary,
            cliff,
            _start,
            _duration,
            _slicePeriodSeconds,
            _amount,
            0
        );
        totalAmountVested += _amount;
        emit VestingScheduleCreated(_beneficiary, _start, _cliff, _duration, _slicePeriodSeconds, _amount);
    }

    function calculateReleaseableAmount(address beneficiary) public view returns (uint256 totalReleasable, uint256 totalRemaining) {
        uint256 vestingCount = holdersVestingCount[beneficiary];
        for (uint256 i = 0; i < vestingCount; i++) {
            VestingSchedule storage vestingSchedule = vestedUserDetail[beneficiary][i];
            (uint256 releasable, uint256 remaining) = _computeReleasableAmount(vestingSchedule);

            totalReleasable += releasable;
            totalRemaining += remaining;
        }
        return (totalReleasable, totalRemaining);
    }

    function _computeReleasableAmount(VestingSchedule memory vestingSchedule) internal view returns (uint256 releasable, uint256 remaining) {
        uint256 currentTime = getCurrentTime();
        uint256 totalVested = 0;
        if (currentTime < vestingSchedule.cliff) {
            return (0, vestingSchedule.amountTotal - vestingSchedule.released);
        } else if (currentTime >= vestingSchedule.start + vestingSchedule.duration) {
            releasable = vestingSchedule.amountTotal - vestingSchedule.released;
            return (releasable, 0);
        } else {
            uint256 timeFromStart = currentTime - vestingSchedule.start;
            uint256 secondsPerSlice = vestingSchedule.slicePeriodSeconds;
            uint256 vestedSlicePeriods = timeFromStart / secondsPerSlice;
            uint256 vestedSeconds = vestedSlicePeriods * secondsPerSlice;

            totalVested = (vestingSchedule.amountTotal * vestedSeconds) / vestingSchedule.duration;
        }
        releasable = totalVested - vestingSchedule.released;
        remaining = vestingSchedule.amountTotal - totalVested;
        return (releasable, remaining);
    }

    function getUserVestingDetails(address beneficiary) public view returns (VestingDetail[] memory) {
        uint256 vestingCount = holdersVestingCount[beneficiary];
        require(vestingCount > 0, "TokenVesting: no vesting schedules found for the beneficiary");

        VestingDetail[] memory details = new VestingDetail[](vestingCount);
        for (uint256 i = 0; i < vestingCount; i++) {
            details[i] = VestingDetail({
                index: i,
                schedule: vestedUserDetail[beneficiary][i]
            });
        }
        return details;
    }

    function getCategoryDetails(uint256 categoryId) public view returns (Category memory) {
        return categories[categoryId];
    }

    function getCategoryUsers(uint256 categoryId) public view returns (UserData[] memory) {
        return categoryUsers[categoryId];
    }

    function getCurrentTime() internal view virtual returns (uint256) {
        return block.timestamp;
    }

    function updateCategorySupply(uint256 categoryId, uint256 additionalSupply) public onlyOwner {
        categories[categoryId].remainingSupply += additionalSupply;
        emit SupplyUpdated(categoryId, additionalSupply);
    }

    function releaseImmediately(uint256 categoryId, address recipient) public onlyOwner {
        require(categoryId == 3 || categoryId == 7, "Only Public Sale or Liquidity & Market Making categories allowed");
        uint256 amount = categories[categoryId].remainingSupply;
        require(amount > 0, "No remaining supply to release");
        categories[categoryId].remainingSupply = 0;
        require(token.transfer(recipient, amount), "Token transfer failed");
        emit TokensReleasedImmediately(categoryId, recipient, amount);
    }

    function releaseVestedAmount(address beneficiary) public onlyOwner {
        (uint256 releasable, ) = calculateReleaseableAmount(beneficiary);
        require(releasable > 0, "No releasable amount available");

        uint256 remainingAmount = releasable;
        uint256 vestingCount = holdersVestingCount[beneficiary];

        for (uint256 i = 0; i < vestingCount && remainingAmount > 0; i++) {
            VestingSchedule storage vestingSchedule = vestedUserDetail[beneficiary][i];
            (uint256 releasableAmount, ) = _computeReleasableAmount(vestingSchedule);

            if (releasableAmount > 0) {
                uint256 releaseAmount = releasableAmount > remainingAmount ? remainingAmount : releasableAmount;
                vestingSchedule.released += releaseAmount;
                remainingAmount -= releaseAmount;
                require(token.transfer(beneficiary, releaseAmount), "Token transfer failed");
            }
        }
    }

    function recoverStuckToken(IERC20 _tokenAddress, uint256 _amount) public onlyOwner {
        uint256 balance = IERC20(_tokenAddress).balanceOf(address(this));
        require(balance >= _amount, "Insufficient balance to recover");
        require(IERC20(_tokenAddress).transfer(owner(), _amount), "Token transfer failed");
    }
}