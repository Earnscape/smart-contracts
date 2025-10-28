// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IstEarn {
    function burn(address user, uint256 amount) external;

    function mint(address to, uint256 amount) external;

    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 value) external returns (bool);

    function approve(address spender, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

interface IEarnscapeStaking {
    function getUserData(address user)
        external
        view
        returns (
            string[] memory categories,
            uint256[] memory levels,
            uint256[] memory stakedAmounts,
            address[] memory stakedTokens
        );

    function getUserStEarnData(address user)
        external
        view
        returns (
            string[] memory categories,
            uint256[] memory levels,
            uint256[] memory stakedAmounts,
            address[] memory stakedTokens
        );

    function getUserPendingStEarnTax(address user)
        external
        view
        returns (uint256);

    function calculateUserStearnTax(address user)
        external
        view
        returns (uint256 totalTaxAmount, uint256 totalStakedAmount);

    function _updateUserPendingStEarnTax(address user, uint256 newTaxAmount)
        external;
}

contract EarnscapeVesting is Ownable {
    IERC20 public earnToken;
    IstEarn public stEarnToken;
    IEarnscapeStaking public stakingContract;

    address public earnStarkManager;
    address public feeRecipient;
    address public merchandiseAdminWallet;

    uint256 public totalAmountVested;
    uint256 public defaultVestingTime;
    uint256 public platformFeePct;

    uint256 public cliffPeriod = 0 minutes;
    uint256 public slicedPeriod = 1 minutes; // for testing

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

    mapping(address => uint256) private Earnbalance;
    mapping(address => uint256) private stearnBalance;
    mapping(address => uint256) private holdersVestingCount;
    mapping(address => mapping(uint256 => VestingSchedule))private vestedUserDetail;

    event TokensLocked(address indexed beneficiary, uint256 amount);
    event PendingEarnDueToStearnUnstake(address user, uint256 amount);
    event SupplyUpdated(uint256 indexed categoryId, uint256 additionalSupply);
    event TipGiven(address indexed giver,address indexed receiver,uint256 amount);
    event PlatformFeeTaken(address indexed from,address indexed to,uint256 feeAmount);
    event UserAdded(uint256 indexed categoryId,string name,address userAddress,uint256 amount);
    event TokensReleasedImmediately(uint256 indexed categoryId,address recipient,uint256 amount);
    event VestingScheduleCreated(address indexed beneficiary,uint256 start,uint256 cliff,uint256 duration,uint256 slicePeriodSeconds,uint256 amount);

    constructor(
        address _tokenAddress,
        address _stEarn,
        address _earnStarkManager,
        address _stakingContractAddress
    ) Ownable(msg.sender) {
        stakingContract = IEarnscapeStaking(_stakingContractAddress);
        earnToken = IERC20(_tokenAddress);
        stEarnToken = IstEarn(_stEarn);
        // defaultVestingTime = 2 minutes;
        defaultVestingTime = 2880 minutes;
        platformFeePct = 40;
        feeRecipient = msg.sender;
        earnStarkManager = _earnStarkManager;
        merchandiseAdminWallet = owner();
    }

    modifier onlyearnStarkManager() {
        require(
            _msgSender() == earnStarkManager,
            "Only earnStarkManager can call this function"
        );
        _;
    }

    modifier onlyAuthorizedUser() {
        require(
            _msgSender() == owner(),
            "Only contract owner can call this function"
        );
        _;
    }

    modifier onlyStakingContract() {
        require(
            msg.sender == address(stakingContract),
            "You are not allowed to call this function"
        );
        _;
    }

    function _adjustStearnBalance(address user) internal {
        (, uint256 locked) = calculateReleaseableAmount(user);
        uint256 stEarnBalance = getstEarnBalance(user);
        if (stEarnBalance > locked) {
            uint256 excess = stEarnBalance - locked;
            stearnBalance[user] = locked;
            IstEarn(stEarnToken).burn(address(this), excess);
        }
    }

    function depositEarn(address beneficiary, uint256 amount) external onlyearnStarkManager {
        require(amount > 0, "Amount must be greater than 0");

        (
             string[] memory categories,
            uint256[] memory levels,
            ,

        ) = IEarnscapeStaking(stakingContract).getUserData(beneficiary);

        uint256 vestingDuration;
        bool isInCategoryV = false;

        // Determine vesting duration based on category and level
        for (uint256 i = 0; i < categories.length; i++) {
            if (
                keccak256(abi.encodePacked(categories[i])) ==
                keccak256(abi.encodePacked("V"))
            ) {
                isInCategoryV = true;
                if (levels[i] == 1) {
                    // vestingDuration = 8 minutes;
                    vestingDuration = 2400 minutes;
                } else if (levels[i] == 2) {
                    // vestingDuration = 6 minutes;
                    vestingDuration = 2057 minutes;
                } else if (levels[i] == 3) {
                    // vestingDuration = 4 minutes;
                    vestingDuration = 1800 minutes;
                } else if (levels[i] == 4) {
                    // vestingDuration = 2 minutes;
                    vestingDuration = 1600 minutes;
                } else if (levels[i] == 5) {
                    vestingDuration = 1440 minutes; // Immediate release for level 5
                }
                break;
            }
        }

        // If user is not in category 'V', apply default vesting time
        if (!isInCategoryV) {
            vestingDuration = defaultVestingTime;
        }

        uint256 start = getCurrentTime();
        Earnbalance[beneficiary] += amount;
        stEarnToken.mint(address(this), amount);
        stearnBalance[beneficiary] += amount;
        createVestingSchedule(
            beneficiary,
            start,
            cliffPeriod,
            vestingDuration,
            slicedPeriod,
            amount
        );
    }

    function setFeeRecipient(address _recipient) external onlyOwner {
        require(_recipient != address(0), "Zero address");
        feeRecipient = _recipient;
    }

    function setPlatformFeePct(uint256 _pct) external onlyOwner {
        require(_pct <= 100, "Pct>100");
        platformFeePct = _pct;
    }

    function updateMerchandiseAdminWallet(address _merchWallet) external onlyOwner {
        merchandiseAdminWallet = _merchWallet;
    }
  
    function giveATip(address receiver, uint256 tipAmount) external {
        require(receiver != address(0), "Invalid receiver address");

        uint256 walletAvail = earnToken.balanceOf(msg.sender);
        uint256 vestingAvail = Earnbalance[msg.sender];
        require(walletAvail + vestingAvail >= tipAmount, "Insufficient total funds");

        // ———————— SKIP FEES FOR MERCHANDISE WALLET ————————
        bool    isMerch    = (receiver == merchandiseAdminWallet);
        uint256 feePct     = isMerch ? 0 : platformFeePct;
        // ————————————————————————————————————————————————

        // 1) Calculate current vesting pools
        (uint256 totalReleasable, uint256 totalRemaining) = calculateReleaseableAmount(msg.sender);
        uint256 feeAmount = (tipAmount * feePct) / 100;

        // 2) Wallet-based fee & net
        uint256 walletFee = walletAvail >= feeAmount ? feeAmount : walletAvail;
        if (walletFee > 0) {
            require(
                earnToken.transferFrom(msg.sender, feeRecipient, walletFee),
                "Fee transfer failed"
            );
        }
        uint256 walletNet = tipAmount <= walletAvail ? tipAmount - walletFee : walletAvail - walletFee;
        if (walletNet > 0) {
            require(
                earnToken.transferFrom(msg.sender, receiver, walletNet),
                "Net transfer failed"
            );
        }

        // 3) Vesting-based fee
        uint256 vestingFee = feeAmount > walletFee ? feeAmount - walletFee : 0;
        if (vestingFee > 0) {
            require(vestingFee <= vestingAvail, "Insufficient vesting for fee");
            stearnBalance[msg.sender] -= vestingFee;
            Earnbalance[msg.sender] -= vestingFee;
            stearnBalance[feeRecipient] += vestingFee;
            Earnbalance[feeRecipient] += vestingFee;
            createVestingSchedule(feeRecipient, block.timestamp, 0, 0, 0, vestingFee);
            _updateVestingAfterTip(msg.sender, vestingFee);
            totalReleasable = totalReleasable > vestingFee ? totalReleasable - vestingFee : 0;
        }

        // 4) Vesting-based net tip
        uint256 vestingNet = tipAmount - walletFee - walletNet - vestingFee;
        if (vestingNet > 0) {
            _processNetTipVesting(msg.sender, receiver, vestingNet, totalReleasable, totalRemaining);
        }

        emit TipGiven(msg.sender, receiver, tipAmount);
    }

    function _processNetTipVesting(
        address sender,
        address receiver,
        uint256 vestingNet,
        uint256 totalReleasable,
        uint256 totalRemaining
    ) internal {
        stearnBalance[sender] -= vestingNet;
        Earnbalance[sender] -= vestingNet;
        stearnBalance[receiver] += vestingNet;
        Earnbalance[receiver] += vestingNet;
        _updateVestingAfterTip(sender, vestingNet);
        uint256 releasableReceiver = vestingNet <= totalReleasable ? vestingNet : totalReleasable;
        uint256 lockedReceiver    = vestingNet - releasableReceiver;
        require(lockedReceiver <= totalRemaining, "Exceeds available remaining vesting");

        if (releasableReceiver > 0) {
            createVestingSchedule(receiver, block.timestamp, 0, 0, 0, releasableReceiver);
        }
        if (lockedReceiver > 0) {
            uint256 vestingDuration;
            if (receiver == merchandiseAdminWallet || receiver == feeRecipient) {
                vestingDuration = 0;
            } else {
                (, vestingDuration) = previewVestingParams(receiver);
            }
            createVestingSchedule(
                receiver,
                block.timestamp,
                cliffPeriod,
                vestingDuration,
                slicedPeriod,
                lockedReceiver
            );
        }
    }

    function _updateVestingAfterTip(address user, uint256 tipDeduction) internal {
        uint256 remainingDeduction = tipDeduction;
        uint256 vestingCount = holdersVestingCount[user];
        for (uint256 i = 0; i < vestingCount && remainingDeduction > 0; i++) {
            VestingSchedule storage sched = vestedUserDetail[user][i];
            uint256 effectiveBalance = sched.amountTotal - sched.released;
            if (effectiveBalance == 0) {
                continue;
            }
            if (remainingDeduction >= effectiveBalance) {
                remainingDeduction -= effectiveBalance;
                sched.amountTotal = sched.released;
            } else {

                uint256 leftover = effectiveBalance - remainingDeduction;
                uint256 originalEnd = sched.start + sched.duration;
                uint256 newDuration = originalEnd > block.timestamp ? originalEnd - block.timestamp : 0;
                sched.start = block.timestamp;
                sched.cliff = 0;
                sched.duration = newDuration;
                sched.amountTotal = sched.released + leftover; 
                sched.released = 0;
                remainingDeduction = 0;
            }
        }
    }

    function previewVestingParams(address beneficiary) public view returns (uint256 start, uint256 vestingDuration){
        // 1) Fetch categories & levels
        ( string[] memory categories,
        uint256[] memory levels,
        , 
        ) = stakingContract.getUserData(beneficiary);

        // 2) Determine vestingDuration exactly as in depositEarn
        bool isInCategoryV = false;
        for (uint256 i = 0; i < categories.length; i++) {
            if (
                keccak256(abi.encodePacked(categories[i])) ==
                keccak256(abi.encodePacked("V"))
            ) {
                isInCategoryV = true;
                 if (levels[i] == 1) {
                    // vestingDuration = 8 minutes;
                    vestingDuration = 2400 minutes;
                } else if (levels[i] == 2) {
                    // vestingDuration = 6 minutes;
                    vestingDuration = 2057 minutes;
                } else if (levels[i] == 3) {
                    // vestingDuration = 4 minutes;
                    vestingDuration = 1800 minutes;
                } else if (levels[i] == 4) {
                    // vestingDuration = 2 minutes;
                    vestingDuration = 1600 minutes;
                } else if (levels[i] == 5) {
                    vestingDuration = 1440 minutes; // Immediate release for level 5
                }
                break;
            }
        }
        if (!isInCategoryV) {
            vestingDuration = defaultVestingTime;
        }
        start = block.timestamp;
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
        emit VestingScheduleCreated(
            _beneficiary,
            _start,
            _cliff,
            _duration,
            _slicePeriodSeconds,
            _amount
        );
    }

    function calculateReleaseableAmount(address beneficiary) public view returns (uint256 totalReleasable, uint256 totalRemaining){
        uint256 vestingCount = holdersVestingCount[beneficiary];
        for (uint256 i = 0; i < vestingCount; i++) {
            VestingSchedule storage vestingSchedule = vestedUserDetail[
                beneficiary
            ][i];
            (uint256 releasable, uint256 remaining) = _computeReleasableAmount(
                vestingSchedule
            );

            totalReleasable += releasable;
            totalRemaining += remaining;
        }
        return (totalReleasable, totalRemaining);
    }

    function _computeReleasableAmount(VestingSchedule memory vestingSchedule)
        internal
        view
        returns (uint256 releasable, uint256 remaining)
    {
        uint256 currentTime = getCurrentTime();
        uint256 totalVested = 0;
        if (currentTime < vestingSchedule.cliff) {
            return (0, vestingSchedule.amountTotal - vestingSchedule.released);
        } else if (
            currentTime >= vestingSchedule.start + vestingSchedule.duration
        ) {
            releasable = vestingSchedule.amountTotal - vestingSchedule.released;
            return (releasable, 0);
        } else {
            uint256 timeFromStart = currentTime - vestingSchedule.start;
            uint256 secondsPerSlice = vestingSchedule.slicePeriodSeconds;
            uint256 vestedSlicePeriods = timeFromStart / secondsPerSlice;
            uint256 vestedSeconds = vestedSlicePeriods * secondsPerSlice;

            totalVested =
                (vestingSchedule.amountTotal * vestedSeconds) /
                vestingSchedule.duration;

        }
        releasable = totalVested - vestingSchedule.released;
        remaining = vestingSchedule.amountTotal - totalVested;
        return (releasable, remaining);
    }

    function getUserVestingDetails(address beneficiary) public view returns (VestingDetail[] memory){
        uint256 vestingCount = holdersVestingCount[beneficiary];

        if (vestingCount == 0) {
            return (new VestingDetail[](0));
        }

        VestingDetail[] memory details = new VestingDetail[](vestingCount);
        for (uint256 i = 0; i < vestingCount; i++) {
            details[i] = VestingDetail({
                index: i,
                schedule: vestedUserDetail[beneficiary][i]
            });
        }
        return details;
    }

    function getCurrentTime() internal view returns (uint256) {
        return block.timestamp;
    }

    function releaseVestedAmount(address beneficiary) external {
        (uint256 rel, ) = calculateReleaseableAmount(beneficiary);
        require(rel > 0, "No releasable amount available");
        _adjustStearnBalance(beneficiary);

        uint256 tax = IEarnscapeStaking(stakingContract).getUserPendingStEarnTax(beneficiary);
        (, uint256 st) = IEarnscapeStaking(stakingContract).calculateUserStearnTax(beneficiary);

        // 1) remove 'tax' from locked vesting
        _updateVestingAfterTip(beneficiary, tax);
        Earnbalance[beneficiary] -= tax;
        // 1b) pay out tax to manager and clear it on the staking side
        if (tax > 0) {
            require(
                earnToken.transfer(earnStarkManager, tax),
                "Tax transfer to manager contract failed"
            );
            IEarnscapeStaking(stakingContract)
                ._updateUserPendingStEarnTax(beneficiary, 0);
        }

        // 2) compute net payout
        uint256 pay = rel > st ? rel - st : 0;
        require(pay > 0, "No claimable amount available after tax deduction.");

        // 3) slice through vesting schedules, emit and deduct Earnbalance
        uint256 cnt = holdersVestingCount[beneficiary];
        for (uint256 i = 0; i < cnt && pay > 0; ) {
            uint256 available = vestedUserDetail[beneficiary][i].amountTotal
                            - vestedUserDetail[beneficiary][i].released;
            if (available == 0) {
                cnt--;
                vestedUserDetail[beneficiary][i] = vestedUserDetail[beneficiary][cnt];
                delete vestedUserDetail[beneficiary][cnt];
                continue;
            }

            uint256 slice = pay < available ? pay : available;
            vestedUserDetail[beneficiary][i].released += slice;
            Earnbalance[beneficiary] -= slice;
            pay -= slice;

            require(
                earnToken.transfer(beneficiary, slice),
                "Token transfer failed"
            );

            if (
                vestedUserDetail[beneficiary][i].released ==
                vestedUserDetail[beneficiary][i].amountTotal
            ) {
                cnt--;
                vestedUserDetail[beneficiary][i] = vestedUserDetail[beneficiary][cnt];
                delete vestedUserDetail[beneficiary][cnt];
                continue;
            }
            i++;
        }

        holdersVestingCount[beneficiary] = cnt;

        emit TokensReleasedImmediately(
            0,
            beneficiary,
            (rel > st ? rel - st : 0) - tax - pay
        );
    }

    function releaseVestedAdmins() external {
        // only the two “admin” wallets may call
        require(
            msg.sender == merchandiseAdminWallet || msg.sender == feeRecipient,
            "Not authorized"
        );

        address beneficiary = msg.sender;

        // burn any extra stEARN so balances line up
        _adjustStearnBalance(beneficiary);

        uint256 vestingCount = holdersVestingCount[beneficiary];
        require(vestingCount > 0, "No vesting schedules");

        // sum & mark all schedules as fully released
        uint256 totalToRelease = 0;
        for (uint256 i = 0; i < vestingCount; i++) {
            VestingSchedule storage sched = vestedUserDetail[beneficiary][i];
            uint256 available = sched.amountTotal - sched.released;
            if (available > 0) {
                totalToRelease += available;
                sched.released = sched.amountTotal;
            }
        }

        // wipe all vesting state
        holdersVestingCount[beneficiary] = 0;
        Earnbalance[beneficiary] = 0;
        stearnBalance[beneficiary] = 0;

        require(totalToRelease > 0, "No vested tokens");
        require(
            earnToken.transfer(beneficiary, totalToRelease),
            "Transfer failed"
        );

        emit TokensReleasedImmediately(
            0,            
            beneficiary,
            totalToRelease
        );
    }

    function forceReleaseVestedAmount(address beneficiary) public {
        (uint256 unlock, uint256 locked) = calculateReleaseableAmount(
            beneficiary
        );
        uint256 totalAmount = unlock + locked;

        _adjustStearnBalance(beneficiary);
        require(totalAmount > 0, "No vested tokens to release");

        uint256 vestingCount = holdersVestingCount[beneficiary];
        require(vestingCount > 0, "No vesting schedules found");

        (, , uint256[] memory stakedAmounts, ) = IEarnscapeStaking(stakingContract).getUserStEarnData(beneficiary);
        bool hasStaked = hasStakedTokens(stakedAmounts);
        require(!hasStaked, "Unstake first to get earns!");

        uint256 taxAmount = IEarnscapeStaking(stakingContract)
            .getUserPendingStEarnTax(beneficiary);

        transferTaxToManager(beneficiary, taxAmount);

        uint256 remainingAmount = processVestingSchedules(
            beneficiary,
            vestingCount,
            totalAmount,
            taxAmount
        );

        holdersVestingCount[beneficiary] = 0;
        emit TokensReleasedImmediately(
            totalAmount - remainingAmount,
            beneficiary,
            totalAmount
        );
    }

    function hasStakedTokens(uint256[] memory stakedAmounts) internal pure returns (bool){
        for (uint256 i = 0; i < stakedAmounts.length; i++) {
            if (stakedAmounts[i] > 0) {
                return true;
            }
        }
        return false;
    }

    function transferTaxToManager(address beneficiary, uint256 taxAmount) internal{
        if (taxAmount > 0) {
            require(
                earnToken.transfer(earnStarkManager, taxAmount),
                "Tax transfer to manager contract failed"
            );
            stakingContract._updateUserPendingStEarnTax(beneficiary, 0);
        }
    }

    function processVestingSchedules(
        address beneficiary,
        uint256 vestingCount,
        uint256 remainingAmount,
        uint256 taxAmount
    ) internal returns (uint256) {
        require(
            remainingAmount >= taxAmount,
            "Insufficient amount to deduct tax"
        );
        remainingAmount -= taxAmount;

        for (uint256 i = 0; i < vestingCount && remainingAmount > 0; i++) {
            VestingSchedule storage vestingSchedule = vestedUserDetail[
                beneficiary
            ][i];

            uint256 unreleasedAmount = vestingSchedule.amountTotal -
                vestingSchedule.released;
            if (unreleasedAmount > 0) {
                uint256 transferAmount = unreleasedAmount > remainingAmount
                    ? remainingAmount
                    : unreleasedAmount;

                vestingSchedule.released += transferAmount;
                remainingAmount -= transferAmount;

                burnAndTransferTokens(beneficiary, transferAmount);
            }

            if (
                vestingSchedule.amountTotal + taxAmount ==
                vestingSchedule.released
            ) {
                delete vestedUserDetail[beneficiary][i];
            }
        }
        return remainingAmount;
    }

    function burnAndTransferTokens(address beneficiary, uint256 amount) internal {
        uint256 balance = stearnBalance[beneficiary];
        uint256 contractBalance = IstEarn(stEarnToken).balanceOf(address(this));

        if (balance > 0 && contractBalance >= balance) {
            IstEarn(stEarnToken).burn(address(this), balance);
            stearnBalance[beneficiary] = 0;
        }
        Earnbalance[beneficiary] = 0;

        require(
            earnToken.transfer(beneficiary, amount),
            "Token transfer failed"
        );
    }

    function updateearnStarkManagerAddress(address _contractaddr) external onlyOwner {
        earnStarkManager = _contractaddr;
    }

    function getEarnBalance(address beneficiary) public view returns (uint256) {
        return Earnbalance[beneficiary];
    }

    function updateEarnBalance(address user, uint256 amount) external onlyStakingContract{
        require(
            Earnbalance[user] >= amount,
            "Insufficient Earn balance to decrease"
        );
        Earnbalance[user] = amount;
    }

    function getstEarnBalance(address beneficiary) public view returns (uint256){
        return stearnBalance[beneficiary];
    }

    function updatestEarnBalance(address user, uint256 amount) external onlyStakingContract{
        require(
            stearnBalance[user] >= amount,
            "Insufficient Earn balance to decrease"
        );
        stearnBalance[user] = amount;
    }

    function stEarnTransfer(address sender, uint256 amount) external {
        if (stearnBalance[sender] >= amount) {
            stearnBalance[sender] -= amount;
            IstEarn(stEarnToken).transfer(msg.sender, amount);
        }
    }

    function updateStakingContract(address _contract) external onlyOwner{
        stakingContract = IEarnscapeStaking(_contract);
    }


}