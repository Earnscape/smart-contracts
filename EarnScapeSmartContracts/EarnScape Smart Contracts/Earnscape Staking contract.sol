// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IEarnscapeVesting {
    function updateEarnBalance(address user, uint256 amount) external;
    function getEarnBalance(address beneficiary) external view returns (uint256);
    function updatestEarnBalance(address user, uint256 amount) external;
    function getstEarnBalance(address beneficiary) external view returns (uint256);
    function releaseVestedAmount(address _receiver,address beneficiary) external ;
    function stEarnTransfer(address sender,uint256 amount) external;
    function calculateReleaseableAmount(address beneficiary) external view returns (uint256 totalReleasable, uint256 totalRemaining);
}
interface Istearn{
    function burn(address user,uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
}
contract EarnscapeStaking is ReentrancyGuard, Ownable {

    uint256 public constant DEFAULT_TAX = 5000; // 50%
    uint256 public constant RESHUFFLE_TAX_DEFAULT = 2500; // 25%
    uint256 public constant MAX_LEVEL = 5;

    // Contract Addresses
    IERC20 public  earnToken;
    IERC20 public  stEarnToken;
    Istearn public  stEarnContract;
    IEarnscapeVesting public EarnscapeVesting;

    address public EarnStarkManager;

    // Structs
    struct UserData {
        mapping(string => uint256) levels;
        mapping(string => uint256) stakedAmounts;
        mapping(string => address) stakedTokens;
        string[] categories;
    }

    struct StearnUserData {
        mapping(string => uint256) levels;
        mapping(string => uint256) stakedAmounts;
        mapping(string => address) stakedTokens;
        string[] categories;
    }

    // Mappings
    mapping(address => UserData) private userDatas;
    mapping(address => StearnUserData) private stearnUserDatas;
    mapping(string => uint256[MAX_LEVEL]) public levelCosts;
    mapping(address =>mapping(address => bool) ) private  isStakedWithStEarn;
    mapping(address =>mapping(address => bool) ) private isStakedWithEarn;
    mapping(address => mapping(address => uint256)) private stEarnStakedAmount;
    mapping(address => mapping(address => uint256)) private EarnStakedAmount;
    mapping(address=>uint256) private UserPendingStEarnTax ;

    // Events
    event UnstakeError(string message, string reason);
    event ReshuffleError(string reason, string details);
    event TransferredAllTokens(address indexed newContract);
    event LevelCostsUpdated(string category, uint256[MAX_LEVEL] newCosts);
    event Unstaked(address indexed user, uint256 amount, uint256 taxAmount);
    event Reshuffled(address indexed user, uint256 amount, uint256 taxAmount);
    event StearnBalanceAdjusted(address indexed user, uint256 adjustedBalance);
    event Staked(address indexed user, uint256 amount, string category, uint256 level);
    event DebugEvent(string description, address indexed user, uint256 value1, uint256 value2, uint256 value3);
    
    event DebugLog(string message, uint256  user, uint256 value);
    event DebugLog1(string message, address indexed   user, uint256 value);
    event DebugLog2(string message, uint256 taxamount);

    event UnstakeData(address user, uint256 totalAmount, uint256 totalTaxAmount);
    event EarnTaxCalculation(address user, string category, uint256 stakedAmount, uint256 taxAmount);
    event StearnTaxCalculation(address user, string category, uint256 stakedAmount, uint256 taxAmount);
    event TransferAmounts(address user, uint256 netAmount, uint256 totalTaxAmount);
    event StearnUnstakeStatus(address user, uint256 stEarnStaked, uint256 releasable, bool success);
    event StearnBurn(address user, uint256 amount);
    event UserDataReset(address user);
    event ReshuffleData(address user, uint256 indexed staked, uint256 indexed tax);
    event DebugStake(string category, uint256 currentEarnLevel, uint256 currentStEarnLevel, uint256 totalRequiredAmount);


    constructor(IERC20 _earnToken, address _stearn, address _EarnStarkManager) Ownable(msg.sender) {
        require(address(_earnToken) != address(0), "Invalid token address");
        require(_EarnStarkManager != address(0), "Invalid EarnStarkManager address");

        earnToken = _earnToken;
        EarnStarkManager = _EarnStarkManager;
        stEarnContract = Istearn(_stearn);
        stEarnToken = IERC20(_stearn);

        _setDefaultLevelCosts();
    }

    modifier onlyContract7() {
        require(_msgSender() == address(EarnscapeVesting), "Only contract 3 can call this function");
        _;
    }

    // Internal Functions
    function _isValidCategory(string memory category) internal pure returns (bool) {
        return (
            keccak256(abi.encodePacked(category)) == keccak256(abi.encodePacked("T")) ||
            keccak256(abi.encodePacked(category)) == keccak256(abi.encodePacked("R")) ||
            keccak256(abi.encodePacked(category)) == keccak256(abi.encodePacked("A")) ||
            keccak256(abi.encodePacked(category)) == keccak256(abi.encodePacked("V")) ||
            keccak256(abi.encodePacked(category)) == keccak256(abi.encodePacked("E")) ||
            keccak256(abi.encodePacked(category)) == keccak256(abi.encodePacked("L"))
        );
    }

    function _setDefaultLevelCosts() internal {
        uint256[5] memory defaultCosts = [
            uint256(100 * (10**18)),
            uint256(200 * (10**18)),
            uint256(400 * (10**18)),
            uint256(800 * (10**18)),
            uint256(1600 * (10**18))
        ];
        string[6] memory categories = ["T", "R", "A", "V", "E", "L"];

        for (uint8 i = 0; i < categories.length; i++) {
            levelCosts[categories[i]] = defaultCosts;
        }
    }

    function _adjustStearnBalance(address user) internal {
        // Get the releasable amount and remaining balance from the vesting contract
        (,uint256 locked ) = IEarnscapeVesting(EarnscapeVesting).calculateReleaseableAmount(user);

        // Get the user's current stEarn balance
        uint256 stEarnBalance = IEarnscapeVesting(EarnscapeVesting).getstEarnBalance(user);
        if (stEarnBalance > locked) {
            uint256 excess = stEarnBalance - locked;
            IEarnscapeVesting(EarnscapeVesting).updatestEarnBalance(user, locked);
            Istearn(stEarnContract).burn(address(EarnscapeVesting), excess);
        }

        // Log the adjustment for transparency
        emit StearnBalanceAdjusted(user, locked);
    }

    function stake(string memory category, uint256[] memory levels) external nonReentrant {
        require(_isValidCategory(category), "Invalid category");

        // Check user's Earn balance and stEarn balance
        uint256 userEarnBalance = earnToken.balanceOf(msg.sender);
        uint256 userStEarnBalance = IEarnscapeVesting(EarnscapeVesting).getstEarnBalance(msg.sender);
        _adjustStearnBalance(msg.sender);
        userStEarnBalance = IEarnscapeVesting(EarnscapeVesting).getstEarnBalance(msg.sender);
        require(
            (userEarnBalance > 0) || (userStEarnBalance > 0),
            "No Earn or stEarn tokens to stake"
        );

        // Ensure staking with stEarn is skipped if all amount is releasable
        (, uint256 locked) = IEarnscapeVesting(EarnscapeVesting).calculateReleaseableAmount(msg.sender);
        if (locked == 0 && userStEarnBalance > 0) {
            revert("Cannot able to stake!");
        }
        
        // Determine which struct to use based on the token used for staking
        if (userStEarnBalance >= userEarnBalance) {
            _stakeStearn(category, levels, userStEarnBalance);
        } else {
            _stakeEarn(category, levels, userEarnBalance);
        }
    }

    function _stakeEarn(string memory category, uint256[] memory levels, uint256 userEarnBalance) internal {
        UserData storage userData = userDatas[msg.sender];
        StearnUserData storage stearnUserData = stearnUserDatas[msg.sender]; // Cross-check with stEarn data
        uint256 totalRequiredAmount = 0;

        for (uint256 i = 0; i < levels.length; i++) {
            uint256 level = levels[i];
            require(level > 0 && level <= MAX_LEVEL, "Invalid level");

            // Allow staking with $EARNS only for levels not already staked with stEarn
            require(
                stearnUserData.levels[category] < level,
                "Cannot stake with Earn: level already staked with stEarn"
            );

            uint256 requiredAmount = levelCosts[category][level - 1];
            totalRequiredAmount += requiredAmount;

            userData.levels[category] = level;

            // Add category if not already present
            if (!_categoryExists(userData.categories, category)) {
                userData.categories.push(category);
            }

            // Update staked amounts
            userData.stakedAmounts[category] += requiredAmount;
            userData.stakedTokens[category] = address(earnToken);
        }

        require(userEarnBalance >= totalRequiredAmount, "Insufficient $EARNS balance");
        earnToken.transferFrom(msg.sender, address(this), totalRequiredAmount);

        isStakedWithEarn[msg.sender][address(earnToken)] = true;
        EarnStakedAmount[msg.sender][address(earnToken)] += totalRequiredAmount;

        emit Staked(msg.sender, totalRequiredAmount, category, levels[levels.length - 1]);
    }

    function _stakeStearn(string memory category, uint256[] memory levels, uint256 userStEarnBalance) internal {
        StearnUserData storage stearnUserData = stearnUserDatas[msg.sender];
        UserData storage userData = userDatas[msg.sender]; // Cross-check with $EARNS data
        uint256 totalRequiredAmount = 0;

        for (uint256 i = 0; i < levels.length; i++) {
            uint256 level = levels[i];
            require(level > 0 && level <= MAX_LEVEL, "Invalid level");

            // Allow staking with stEarn only for levels not already staked with Earn
            require(
                userData.levels[category] < level,
                "Cannot stake with stEarn: level already staked with Earn"
            );

            uint256 requiredAmount = levelCosts[category][level - 1];
            totalRequiredAmount += requiredAmount;

            stearnUserData.levels[category] = level;

            // Add category if not already present
            if (!_categoryExists(stearnUserData.categories, category)) {
                stearnUserData.categories.push(category);
            }

            // Update staked amounts
            stearnUserData.stakedAmounts[category] += requiredAmount;
            stearnUserData.stakedTokens[category] = address(stEarnToken);
        }

        require(userStEarnBalance >= totalRequiredAmount, "Insufficient stEarn balance");
        IEarnscapeVesting(EarnscapeVesting).stEarnTransfer(msg.sender, totalRequiredAmount);

        isStakedWithStEarn[msg.sender][address(stEarnToken)] = true;
        stEarnStakedAmount[msg.sender][address(stEarnToken)] += totalRequiredAmount;

        emit Staked(msg.sender, totalRequiredAmount, category, levels[levels.length - 1]);
    }

    function _categoryExists(string[] storage categories, string memory category) internal view returns (bool) {
        for (uint256 i = 0; i < categories.length; i++) {
            if (keccak256(abi.encodePacked(categories[i])) == keccak256(abi.encodePacked(category))) {
                return true;
            }
        }
        return false;
    }

    function _getPerkForLevel(uint256 level) internal pure returns (uint256) {
        if (level == 1) return 4500; // 45.00% perk for Level 1
        if (level == 2) return 4000; // 40.00% perk for Level 2
        if (level == 3) return 3250; // 32.50% perk for Level 3
        if (level == 4) return 1500; // 15.00% perk for Level 4
        if (level == 5) return 250;  // 2.50% perk for Level 5
        return 0; // No perk for levels below 1
    }

    /// @notice Detects if the user holds both A and any other category, and returns the A-level perk.
    function _detectMixedRate(address user)
        internal
        view
        returns (bool mixed, uint256 mixedRate)
    {
        // pull data
        (string[] memory categories,, uint256[] memory stakedAmounts, ) = getUserData(user);

        bool hasA;
        bool hasOther;
        for (uint i = 0; i < categories.length; i++) {
            if (stakedAmounts[i] == 0) continue;
            if (keccak256(bytes(categories[i])) == keccak256(bytes("A"))) {
                hasA = true;
            } else {
                hasOther = true;
            }
        }

        mixed = hasA && hasOther;
        if (mixed) {
            uint256 lvlA = userDatas[user].levels["A"];
            mixedRate = _getPerkForLevel(lvlA);
        }
    }

     /// @dev returns (mixedFlag, mixedRate) based on stEarn data
    function _detectMixedRateStearn(address user)
        internal
        view
        returns (bool mixed, uint256 mixedRate)
    {
        StearnUserData storage sData = stearnUserDatas[user];

        bool hasA;
        bool hasOther;
        for (uint i = 0; i < sData.categories.length; i++) {
            string memory cat = sData.categories[i];
            // only consider truly staked categories
            if (sData.stakedAmounts[cat] == 0) continue;

            if (keccak256(bytes(cat)) == keccak256(bytes("A"))) {
                hasA = true;
            } else {
                hasOther = true;
            }
        }

        mixed = hasA && hasOther;
        if (mixed) {
            // use the user's A level from StearnUserData
            uint256 lvlA = sData.levels["A"];
            mixedRate = _getPerkForLevel(lvlA);
        }
    }

    function unstake() external nonReentrant {
        uint256 totalAmount = 0;
        uint256 totalTaxAmount = 0;

        bool hasEarnData = false;
        bool hasStearnData = false;

        // Adjust Stearn balances before processing
        _adjustStearnBalance(msg.sender);

        // Get user Earn data
        (
            string[] memory categories,
            uint256[] memory levels,
            uint256[] memory stakedAmounts,
            
        ) = getUserData(msg.sender);

        // *** MIXED TAX LOGIC ADDED HERE ***
        (bool mixed, uint256 mixedRate) = _detectMixedRate(msg.sender);
        // *** END MIXED TAX LOGIC ***

        // Process Earn data
        for (uint256 i = 0; i < categories.length; i++) {
            string memory category = categories[i];
            uint256 stakedAmount = stakedAmounts[i];
            if (stakedAmount == 0) continue;

            uint256 categoryTaxAmount;
            if (mixed) {
                // *** APPLY MIXED RATE TO ALL ***
                categoryTaxAmount = _calculateTax(stakedAmount, mixedRate);
            } else if (
                keccak256(bytes(category)) == keccak256(bytes("A"))
            ) {
                categoryTaxAmount = _handleCategoryATax(category, stakedAmount, levels[i]);
            } else {
                categoryTaxAmount = _handleOtherCategoryTax(stakedAmount);
            }

            totalTaxAmount += categoryTaxAmount;
            totalAmount += stakedAmount;
            hasEarnData = true;
            emit EarnTaxCalculation(msg.sender, category, stakedAmount, categoryTaxAmount);
        }

        uint256 netAmount = totalAmount - totalTaxAmount;

        if (hasEarnData) {
            EarnStakedAmount[msg.sender][address(earnToken)] = 0;
            isStakedWithEarn[msg.sender][address(earnToken)] = false;
            earnToken.transfer(EarnStarkManager, totalTaxAmount);
            earnToken.transfer(msg.sender, netAmount);
            emit TransferAmounts(msg.sender, netAmount, totalTaxAmount);
        }

        uint256 stEarnStaked = stEarnStakedAmount[msg.sender][address(stEarnToken)];
        if (stEarnStaked > 0) {
            hasStearnData = true;
            // step A: get stearn-specific mixed flag & rate
           (bool mixedStearn, uint256 mixedRateStearn) = _detectMixedRateStearn(msg.sender);
            (bool successStearnUnstake, ) = _safeUnstakeStearn(
                msg.sender,
                stEarnStaked,
                mixedStearn,
                mixedRateStearn
            );

            if (successStearnUnstake) {
                _resetStearnUserData(msg.sender);
            } else {
                emit DebugLog1("Stearn unstake failed", msg.sender, stEarnStaked);
            }
        }

        if (!hasEarnData && !hasStearnData) {
            revert("No Earn or Stearn staking data found");
        }

        // Reset general user data and emit final event
        _resetUserData(msg.sender);
        emit Unstaked(msg.sender, totalAmount, totalTaxAmount);
    }

    function _handleCategoryATax(string memory category, uint256 stakedAmount, uint256 level) internal returns (uint256) {
        uint256 totalStakedInCategoryA = 0;

        // Calculate total staked amount for Category A based on the user data retrieved
        UserData storage userData = userDatas[msg.sender];

        for (uint256 j = 0; j < userData.categories.length; j++) {
            if (keccak256(abi.encodePacked(userData.categories[j])) == keccak256(abi.encodePacked("A"))) {
                totalStakedInCategoryA += userData.stakedAmounts[userData.categories[j]]; // Using stakedAmounts from UserData
            }
        }

        // Apply perk reduction for Category A
        uint256 perkReduction = _getPerkForLevel(level);
        uint256 adjustedAmount = (totalStakedInCategoryA * (10000 - perkReduction)) / 10000;

        // Calculate the tax amount for Category A
        uint256 taxAmountA = totalStakedInCategoryA - adjustedAmount;
        emit EarnTaxCalculation(msg.sender, category, stakedAmount, taxAmountA);

        return taxAmountA;
    }

    function _handleOtherCategoryTax(uint256 stakedAmount) internal pure returns (uint256) {
        // Calculate tax for other categories using default tax logic
        uint256 taxAmount = _calculateTax(stakedAmount, DEFAULT_TAX );
        return taxAmount;
    }

    function _safeUnstakeStearn(
        address user,
        uint256 /*stEarnBalance*/,
        bool mixed,
        uint256 mixedRate
    ) internal returns (bool, uint256) {
        // 1) same releasable/remaining check
        (uint256 releasable, uint256 remaining) = IEarnscapeVesting(EarnscapeVesting).calculateReleaseableAmount(user);
        if (releasable == 0 || remaining > 0) {
            // if (releasable < stEarnStaked) {
            return (false, 0);
        }

        // 2) pull the on‐chain staked amount exactly as before
        uint256 stEarnStaked = stEarnStakedAmount[user][address(stEarnToken)];
        StearnUserData storage stearnUserData = stearnUserDatas[user];
        uint256 totalStearnTaxAmount = 0;
        for (uint256 i = 0; i < stearnUserData.categories.length; i++) {
            string memory category = stearnUserData.categories[i];
            uint256 stakedAmount = stearnUserData.stakedAmounts[category];

            if (stearnUserData.stakedTokens[category] == address(stEarnToken)) {
                uint256 taxAmount;

                if (mixed) {
                    // *** MIXED‐RATE BRANCH ***
                    taxAmount = _calculateTax(stakedAmount, mixedRate);

                } else if (
                    keccak256(abi.encodePacked(category)) == keccak256(abi.encodePacked("A"))
                ) {
                    // Category A only —
                    uint256 level = stearnUserData.levels[category];
                    uint256 perkReduction = _getPerkForLevel(level);
                    uint256 adjustedAmount = (stakedAmount *(10000 - perkReduction)) / 10000;
                    taxAmount = stakedAmount - adjustedAmount;

                } else {
                    // Other categories at default tax
                    taxAmount = _calculateTax(stakedAmount, DEFAULT_TAX);
                }

                emit StearnTaxCalculation(user, category, stakedAmount, taxAmount);
                totalStearnTaxAmount += taxAmount;
            }
        }

        // 3) burn exactly the releasable portion, as before
        if (stEarnToken.balanceOf(address(this)) >= stEarnStaked) {
            Istearn(stEarnContract).burn(address(this), stEarnStaked);
        }

        // 4) record pending tax, clear flags exactly as before
        UserPendingStEarnTax[user] += totalStearnTaxAmount;
        stEarnStakedAmount[user][address(stEarnToken)] = 0;
        isStakedWithStEarn[user][address(stEarnToken)] = false;

        return (true, releasable);
    }

    function reshuffle() external nonReentrant {
        _adjustStearnBalance(msg.sender);
        (string[] memory categories, uint256[] memory levels, uint256[] memory stakedAmounts, ) = getUserData(msg.sender);

        // *** MIXED TAX LOGIC FOR RESHUFFLE ***
        (bool mixed2, uint256 mixedRate2) = _detectMixedRate(msg.sender);
        // *** END MIXED TAX LOGIC ***

        uint256 totalAmt;
        uint256 totalTax;
        bool hasEarn2;
        for (uint i = 0; i < categories.length; i++) {
            uint256 amt = stakedAmounts[i];
            if (amt == 0) continue;
            uint256 taxAmt;
            if (mixed2) {
                taxAmt = _calculateTax(amt, (mixedRate2/2));
            } else if (keccak256(bytes(categories[i])) == keccak256(bytes("A"))) {
                taxAmt = _handleCategoryAReshuffle(categories[i], amt, levels[i]);
            } else {
                taxAmt = _handleOtherCategoryReshuffle(amt);
            }
            totalAmt += amt;
            totalTax += taxAmt;
            hasEarn2 = true;
            emit EarnTaxCalculation(msg.sender, categories[i], amt, taxAmt);
        }

        if (hasEarn2) {
            EarnStakedAmount[msg.sender][address(earnToken)] = 0;
            isStakedWithEarn[msg.sender][address(earnToken)] = false;
            earnToken.transfer(EarnStarkManager, totalTax);
            earnToken.transfer(msg.sender, totalAmt - totalTax);
            emit TransferAmounts(msg.sender, totalAmt - totalTax, totalTax);
        }

        // pull the stearn‐data mixed flag/rate
        (bool mixedStearn, uint256 mixedRateStearn) = _detectMixedRateStearn(msg.sender);
        _processStEarnReshuffle(msg.sender, mixedStearn, mixedRateStearn);

        if (!hasEarn2 && stEarnStakedAmount[msg.sender][address(stEarnToken)] == 0) {
            revert("No Earn or Stearn staking data found");
        }

        _resetUserData(msg.sender);
        emit ReshuffleData(msg.sender, totalAmt, totalTax);
    }

    function _processStEarnReshuffle(address user, bool mixed2, uint256 mixedRate2) internal {
        uint256 stEarnBalance = stEarnStakedAmount[user][address(stEarnToken)];
        if (stEarnBalance == 0) return;
        (bool success,) = _safeReshuffleStearn(user,stEarnBalance, mixed2, mixedRate2);
        if (success) _resetStearnUserData(user);
    }

    function _handleCategoryAReshuffle(string memory category, uint256 stakedAmount, uint256 level) internal returns (uint256) {
        uint256 totalStakedInCategoryA = 0;

        // Calculate total staked amount for Category A based on the user data retrieved
        UserData storage userData = userDatas[msg.sender];

        for (uint256 j = 0; j < userData.categories.length; j++) {
            if (keccak256(abi.encodePacked(userData.categories[j])) == keccak256(abi.encodePacked("A"))) {
                totalStakedInCategoryA += userData.stakedAmounts[userData.categories[j]]; // Using stakedAmounts from UserData
            }
        }

        // Apply perk reduction for Category A
        uint256 perkReduction = _getPerkForLevel(level);
        uint256 adjustedAmount = (totalStakedInCategoryA * (10000 - perkReduction)) / 10000;

        // Calculate the tax amount for Category A
        uint256 taxAmountA = totalStakedInCategoryA - adjustedAmount;
        emit EarnTaxCalculation(msg.sender, category, stakedAmount, taxAmountA);

        return taxAmountA;
    }

    function _handleOtherCategoryReshuffle(uint256 stakedAmount) internal pure returns (uint256) {
        // Calculate tax for other categories using default tax logic
        uint256 taxAmount = _calculateTax(stakedAmount, RESHUFFLE_TAX_DEFAULT);
        return taxAmount;
    }

    function _safeReshuffleStearn(address user,uint256 /*stEarnBalance*/,bool mixed,uint256 mixedRate) internal returns (bool, uint256) {
        // 1) same releasable/remaining check
        (uint256 releasable, uint256 remaining) = IEarnscapeVesting(EarnscapeVesting)
            .calculateReleaseableAmount(user);
        if (releasable == 0 || remaining > 0) {
            return (false, 0);
        }
        StearnUserData storage stearnUserData = stearnUserDatas[user];
        // 2) read the on-chain staked amount once
        uint256 stEarnStaked = stEarnStakedAmount[user][address(stEarnToken)];

        uint256 totalStearnTaxAmount = 0;
        for (uint256 i = 0; i < stearnUserData.categories.length; i++) {
            string memory category = stearnUserData.categories[i];
            uint256 stakedAmount = stearnUserData.stakedAmounts[category];

            // only tax what was staked via stEarn
            if (stearnUserData.stakedTokens[category] == address(stEarnToken)) {
                uint256 taxAmount;

                if (mixed) {
                    // *** MIXED-RATE BRANCH ***
                    taxAmount = _calculateTax(stakedAmount, (mixedRate/2));

                } else if (
                    keccak256(abi.encodePacked(category)) ==
                    keccak256(abi.encodePacked("A"))
                ) {
                    // Category A only — **exactly** your old logic
                    uint256 level = stearnUserData.levels[category];
                    uint256 perkReduction = _getPerkForLevel(level);
                    uint256 adjustedAmount = (stakedAmount *
                        (10000 - perkReduction)) / 10000;
                    taxAmount = stakedAmount - adjustedAmount;

                } else {
                    // all other categories at reshuffle default
                    taxAmount = _calculateTax(stakedAmount, RESHUFFLE_TAX_DEFAULT);
                }

                totalStearnTaxAmount += taxAmount;
            }
        }

        // 3) burn exactly the releasable portion, as before
        if (stEarnToken.balanceOf(address(this)) >= stEarnStaked) {
            Istearn(stEarnContract).burn(address(this), stEarnStaked);
        }

        // 4) record pending tax, clear stake flags
        UserPendingStEarnTax[user] += totalStearnTaxAmount;
        stEarnStakedAmount[user][address(stEarnToken)] = 0;
        isStakedWithStEarn[user][address(stEarnToken)] = false;

        return (true, releasable);
    }

    function transferAllTokens(address newContract) external onlyOwner nonReentrant {
        require(newContract != address(0), "Invalid address");
        uint256 balance = earnToken.balanceOf(address(this));
        earnToken.transfer(newContract, balance);
        emit TransferredAllTokens(newContract);
    }

    function readLevel(address user, string memory category) external view returns (uint256) {
        UserData storage userData = userDatas[user];
        return userData.levels[category];
    }

    function getUserData(address user)
        public 
        view
        returns (
            string[] memory categories,
            uint256[] memory levels,
            uint256[] memory stakedAmounts,
            address[] memory stakedTokens
        )
    {
        UserData storage userData = userDatas[user];
        categories = userData.categories;

        levels = new uint256[](categories.length);
        stakedAmounts = new uint256[](categories.length);
        stakedTokens = new address[](categories.length);
        for (uint256 i = 0; i < categories.length; i++) {
            levels[i] = userData.levels[categories[i]];
            stakedAmounts[i] = userData.stakedAmounts[categories[i]];
            stakedTokens[i] = userData.stakedTokens[categories[i]];
        }
    }

    function getUserStEarnData(address user)
        external
        view
        returns (
            string[] memory categories,
            uint256[] memory levels,
            uint256[] memory stakedAmounts,
            address[] memory stakedTokens
        )
    {
        StearnUserData storage stearnUserData = stearnUserDatas[user];
        categories = stearnUserData.categories;
        levels = new uint256[](categories.length);
        stakedAmounts = new uint256[](categories.length);
        stakedTokens = new address[](categories.length);
        for (uint256 i = 0; i < categories.length; i++) {
            levels[i] = stearnUserData.levels[categories[i]];
            stakedAmounts[i] = stearnUserData.stakedAmounts[categories[i]];
            stakedTokens[i] = stearnUserData.stakedTokens[categories[i]];
        }
    }

    function _calculateTax(uint256 amount, uint256 taxRate) internal pure returns (uint256) {
        return (amount * taxRate) / 10000;
    }

    function _resetUserData(address user) internal {
        UserData storage userData = userDatas[user];
        for (uint256 i = 0; i < userData.categories.length; i++) {
            string memory category = userData.categories[i];
            userData.levels[category] = 0;
            userData.stakedAmounts[category] = 0;
        }
        delete userData.categories;
    }

    function _resetStearnUserData(address user) internal {
        StearnUserData storage stearnUserData = stearnUserDatas[user];
        for (uint256 i = 0; i < stearnUserData.categories.length; i++) {
            string memory category = stearnUserData.categories[i];
            stearnUserData.levels[category] = 0;
            stearnUserData.stakedAmounts[category] = 0;
        }
        delete stearnUserData.categories;
    }

    function setEarnStarkManager(address newContract) external onlyOwner {
        require(newContract != address(0), "Invalid contract address");
        EarnStarkManager = newContract;
    }

    function setLevelCosts(string memory category, uint256[MAX_LEVEL] memory newCosts) external onlyOwner {
        require(_isValidCategory(category), "Invalid category");
        levelCosts[category] = newCosts;

        emit LevelCostsUpdated(category, newCosts);
    }

    function setVestingContract(address _contract) external onlyOwner {
        EarnscapeVesting = IEarnscapeVesting(_contract);
    }

    function checkIsStakedWithStEarn(address user, address token) external view returns (bool) {
        return isStakedWithStEarn[user][token];
    }

    function checkIsStakedWithEarn(address user, address token) external view returns (bool) {
        return isStakedWithEarn[user][token];
    }

    function getStEarnStakedAmount(address user, address token) external view returns (uint256) {
        return stEarnStakedAmount[user][token];
    }

    function getEarnStakedAmount(address user, address token) external view returns (uint256) {
        return EarnStakedAmount[user][token];
    }

    function getLevelCosts(string memory category) external view returns (uint256[MAX_LEVEL] memory) {
        return levelCosts[category];
    }

    function calculateUserStearnTax(address user) public view returns (uint256 totalTaxAmount, uint256 totalStakedAmount){

        StearnUserData storage stearnUserData = stearnUserDatas[user];

        // **** MIXED DETECTION ****
        bool hasA;
        bool hasOther;
        for (uint256 i = 0; i < stearnUserData.categories.length; i++) {
            string memory cat = stearnUserData.categories[i];
            // only consider categories where stEarn was actually staked
            if (stearnUserData.stakedTokens[cat] != address(stEarnToken)) continue;

            if (keccak256(bytes(cat)) == keccak256(bytes("A"))) {
                hasA = true;
            } else {
                hasOther = true;
            }
        }
        bool mixed = hasA && hasOther;
        uint256 mixedRate = mixed
            ? _getPerkForLevel(stearnUserData.levels["A"])
            : 0;
        // **** END MIXED DETECTION ****

        totalTaxAmount   = 0;
        totalStakedAmount = 0;

        for (uint256 i = 0; i < stearnUserData.categories.length; i++) {
            string memory category = stearnUserData.categories[i];
            uint256 stakedAmount   = stearnUserData.stakedAmounts[category];

            // only tax what was staked via stEarn
            if (stearnUserData.stakedTokens[category] != address(stEarnToken)) {
                continue;
            }
            if (stakedAmount == 0) {
                continue;
            }

            uint256 taxAmount;
            if (mixed) {
                // unified mixed rate across all categories
                taxAmount = (stakedAmount * mixedRate) / 10_000;

            } else if (
                keccak256(bytes(category)) == keccak256(bytes("A"))
            ) {
                // pure Category A
                uint256 lvl           = stearnUserData.levels[category];
                uint256 perkReduction = _getPerkForLevel(lvl);
                uint256 adjusted      = (stakedAmount * (10_000 - perkReduction)) / 10_000;
                taxAmount             = stakedAmount - adjusted;

            } else {
                // default for all others
                taxAmount = _calculateTax(stakedAmount, DEFAULT_TAX);
            }

            totalTaxAmount   += taxAmount;
            totalStakedAmount += stakedAmount;
        }
    }

    function getUserPendingStEarnTax(address user) external view returns (uint256) {
        return UserPendingStEarnTax[user];
    }

    function _updateUserPendingStEarnTax(address user, uint256 newTaxAmount) external onlyContract7{
        UserPendingStEarnTax[user] = newTaxAmount;
    }

    function getLevelCost(string memory category, uint256 level) public view returns (uint256) {
        return levelCosts[category][level];
    }

}