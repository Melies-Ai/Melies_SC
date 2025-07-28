// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IMeliesICO
 * @dev Interface for the Melies Initial Coin Offering (ICO) contract.
 * This interface defines the external functions, events, and structs
 * for managing the ICO process, including token purchases, allocations,
 * and vesting schedules.
 */
interface IMeliesICO {
    /**
     * @dev Struct representing a sale round
     * @param startTime Start time of the round
     * @param endTime End time of the round
     * @param tokenPrice Token price in USDC (6 decimals)
     * @param maxCap Maximum USDC to be raised in this round (6 decimals)
     * @param softCap Minimum USDC to be raised for the round to be considered successful (6 decimals)
     * @param minPurchase Minimum purchase amount in USDC (6 decimals)
     * @param maxPurchase Maximum purchase amount in USDC (6 decimals)
     * @param totalUsdcRaised Total amount of USDC raised in this round (6 decimals)
     * @param isFinish Whether the round is finished
     * @param cliffMonthDuration Duration of the cliff period for token vesting (in months)
     * @param vestingMonthDuration Total duration of the vesting period (in months)
     * @param tgeReleasePercentage TGE release percentage
     */
    struct SaleRound {
        uint256 startTime;
        uint256 endTime;
        uint256 tokenPrice;
        uint256 maxCap;
        uint256 softCap;
        uint256 minPurchase;
        uint256 maxPurchase;
        uint256 totalUsdcRaised;
        bool isFinish;
        uint256 cliffMonthDuration;
        uint256 vestingMonthDuration;
        uint256 tgeReleasePercentage;
    }

    // Events
    event SlippageToleranceUpdated(uint256 newSlippageTolerance);
    event TokensPurchased(address indexed buyer, uint256 usdAmount, uint256 tokenAmount);
    event AllocationAdded(
        address indexed beneficiary,
        uint256 tokenAmount,
        uint256 cliffMonthDuration,
        uint256 vestingMonthDuration,
        uint256 roundId
    );
    event RoundFundsWithdrawn(uint256 indexed roundId, uint256 usdcAmount);
    event IcoEnded(bool claimEnabled);
    event RefundsAvailableForRound(uint256 indexed roundId);
    event Refunded(address indexed user, uint256 usdcAmount);
    event UsdcWithdrawn(address indexed recipient, uint256 amount);
    event EthWithdrawn(address indexed recipient, uint256 amount);
    event TokensRecovered(address indexed token, address indexed recipient, uint256 amount);
    event AddedToWhitelist(uint256 indexed roundId, address[] addresses);
    event RemovedFromWhitelist(uint256 indexed roundId, address[] addresses);
    event FutureRoundUpdated(uint256 indexed roundId);

    // Errors
    error SlippageToleranceTooHigh();
    error InvalidTimeRange();
    error InvalidTokenPrice();
    error InvalidCap();
    error InvalidPurchaseLimits();
    error InvalidVestingDuration();
    error InvalidCliffOrVestingDuration();
    error InvalidCliffOrVestingAdjustment();
    error InvalidTgeReleasePercentage();
    error CannotModifyPastOrCurrentRound();
    error NoEthSent();
    error IcoAlreadyEnded();
    error NotWhitelisted();
    error BelowMinimumPurchase();
    error ExceedsMaximumPurchase();
    error ExceedsWalletContributionLimit();
    error RoundCapExceeded();
    error NoTokensSent();
    error UsdcAmountMustBeGreaterThanZero();
    error UsdAmountMustBeGreaterThanZero();
    error InvalidBeneficiaryAddress();
    error TokenAmountMustBeGreaterThanZero();
    error UsdAmountCannotBeZero();
    error RoundNotFinished();
    error SoftCapNotReached();
    error IcoNotEndedYet();
    error RefundNotAvailable();
    error NoAllocationToRefund();
    error CannotRecoverMeliesTokens();
    error CannotRecoverUsdcTokens();
    error InsufficientTokenBalance();
    error NoEthToWithdraw();
    error EthTransferFailed();
    error NoActiveRound();
    error InvalidEthUsdPrice();
    error InvalidRoundId();
    error InvalidBuyer();

    /**
     * @dev Updates the slippage tolerance for ETH to USDC swaps
     * @param _newSlippageTolerance New slippage tolerance value (max 10%)
     */
    function updateSlippageTolerance(uint256 _newSlippageTolerance) external;

    /**
     * @dev Adds a new sale round to the ICO
     * @param _startTime Start time of the round
     * @param _endTime End time of the round
     * @param _tokenPrice Token price in USDC (6 decimals)
     * @param _maxCap Maximum USDC to be raised in this round (6 decimals)
     * @param _softCap Minimum USDC to be raised for the round to be considered successful (6 decimals)
     * @param _minPurchase Minimum purchase amount in USDC (6 decimals)
     * @param _maxPurchase Maximum purchase amount in USDC (6 decimals)
     * @param _cliffMonthDuration Cliff duration for token vesting (in months)
     * @param _vestingMonthDuration Total vesting duration (in months)
     * @param _tgeReleasePercentage TGE release percentage
     */
    function addSaleRound(
        uint256 _startTime,
        uint256 _endTime,
        uint256 _tokenPrice,
        uint256 _maxCap,
        uint256 _softCap,
        uint256 _minPurchase,
        uint256 _maxPurchase,
        uint256 _cliffMonthDuration,
        uint256 _vestingMonthDuration,
        uint256 _tgeReleasePercentage
    ) external;

    /**
     * @dev Adds addresses to the whitelist for a specific round
     * @param _roundId ID of the sale round
     * @param _addresses Addresses to be added to the whitelist
     */
    function addToWhitelist(uint256 _roundId, address[] calldata _addresses) external;

    /**
     * @dev Removes addresses from the whitelist for a specific round
     * @param _roundId ID of the sale round
     * @param _addresses Addresses to be removed from the whitelist
     */
    function removeFromWhitelist(uint256 _roundId, address[] calldata _addresses) external;

    /**
     * @dev Allows users to buy tokens with ETH
     * @param _roundId ID of the sale round
     */
    function buyWithEth(uint8 _roundId) external payable;

    /**
     * @dev Allows users to buy tokens with USDC
     * @param _roundId ID of the sale round
     * @param _amount Amount of USDC to spend on token purchase
     */
    function buyWithUsdc(uint8 _roundId, uint256 _amount) external;

    /**
     * @dev Allows admins to add purchases made with fiat currency
     * @param _buyer Address of the token buyer
     * @param _usdAmount Amount of USD equivalent purchased
     * @param _roundId ID of the sale round
     */
    function addFiatPurchase(address _buyer, uint256 _usdAmount, uint8 _roundId) external;

    /**
     * @dev Allows admins to withdraw funds raised in a specific round
     * @param _roundId ID of the round to withdraw funds from
     */
    function withdrawRoundFunds(uint256 _roundId) external;

    /**
     * @dev Allows admins to end the ICO
     */
    function endIco() external;

    /**
     * @dev Allows users to request a refund if ICO ends without enabling claims
     */
    function refund() external;

    /**
     * @dev Allows users to request a refund for a specific round if its soft cap wasn't reached
     * @param _roundId ID of the round to request a refund from
     */
    function refundForRound(uint256 _roundId) external;

    /**
     * @dev Allows admins to withdraw raised USDC after ICO ends
     */
    function withdrawUsdc() external;

    /**
     * @dev Allows admins to withdraw any ETH in the contract after ICO ends
     */
    function withdrawEth() external;

    /**
     * @dev Allows admins to recover any ERC20 tokens accidentally sent to the contract
     * @param _token Address of the ERC20 token to recover
     * @param _amount Amount of tokens to recover
     */
    function recoverTokens(address _token, uint256 _amount) external;

    /**
     * @dev Retrieves the current active sale round
     * @return The current SaleRound struct
     */
    function getCurrentRound() external view returns (SaleRound memory);

    /**
     * @dev Retrieves the ID of the current active sale round
     * @return The ID of the current round
     */
    function getCurrentRoundId() external view returns (uint256);

    /**
     * @dev Retrieves the user's USDC contribution for a specific round
     * @param _beneficiary Address of the beneficiary
     * @param _roundId ID of the sale round
     * @return The total USDC amount contributed by the user in the specified round
     */
    function getUserRoundContribution(address _beneficiary, uint256 _roundId) external view returns (uint256);

    /**
     * @dev Gets the total contribution amount for a specific wallet in a specific round
     * @param _wallet Address of the wallet to check
     * @param _roundId ID of the round to check
     * @return Total USD amount contributed by the wallet in the round
     */
    function getWalletContribution(address _wallet, uint256 _roundId) external view returns (uint256);

    /**
     * @dev Gets the total tokens sold across all ICO rounds
     * @return Total tokens sold
     */
    function getTotalTokensSold() external view returns (uint256);

    /**
     * @dev Gets the total unsold tokens
     * @return Total unsold tokens
     */
    function getUnsoldTokens() external view returns (uint256);

    /**
     * @dev Gets the sales performance percentage
     * @return Sales performance as a percentage (0-100)
     */
    function getSalesPerformance() external view returns (uint256);

    /**
     * @dev Checks if unsold tokens have been distributed
     * @return True if unsold tokens have been distributed
     */
    function isUnsoldTokensDistributed() external view returns (bool);
}
