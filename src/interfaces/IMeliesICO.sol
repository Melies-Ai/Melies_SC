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
    enum purchaseMethod {
        USDC,
        USDT,
        FIAT
    }

    /**
     * @dev Struct representing a sale round
     * @param startTime Start time of the round
     * @param endTime End time of the round
     * @param tokenPrice Token price in USDC (6 decimals)
     * @param maxCap Maximum USDC to be raised in this round (6 decimals)
     * @param softCap Minimum USDC to be raised for the round to be considered successful (6 decimals)
     * @param minPurchase Minimum purchase amount in USDC (6 decimals)
     * @param maxPurchase Maximum purchase amount in USDC (6 decimals)
     * @param totalRaised Total amount of USDC raised in this round (6 decimals)
     * @param totalRaisedUsdc Total amount of USDC raised in this round (6 decimals)
     * @param totalRaisedUsdt Total amount of USDT raised in this round (6 decimals)
     * @param isFinish Whether the round is finished
     * @param cliffDuration Duration of the cliff period for token vesting
     * @param vestingDuration Total duration of the vesting period
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
        uint256 totalRaised;
        uint256 totalRaisedUsdc;
        uint256 totalRaisedUsdt;
        bool isFinish;
        uint256 cliffDuration;
        uint256 vestingDuration;
        uint256 tgeReleasePercentage;
    }

    /**
     * @dev Struct representing an allocation for a beneficiary
     * @param totalTokenAmount Total amount of tokens allocated
     * @param totalUsdcAmount Total amount of USDC allocated
     * @param totalUsdtAmount Total amount of USDT allocated
     * @param claimedAmount Amount of tokens claimed
     * @param lastClaimTimestamp Last claim timestamp
     */
    struct Allocation {
        uint256 totalTokenAmount;
        uint256 totalUsdcAmount;
        uint256 totalUsdtAmount;
        uint256 claimedAmount;
        uint256 lastClaimTimestamp;
    }

    // Events
    /**
     * @dev Emitted when the slippage tolerance is updated
     * @param newSlippageTolerance The new slippage tolerance value
     */
    event SlippageToleranceUpdated(uint256 newSlippageTolerance);

    /**
     * @dev Emitted when tokens are purchased
     * @param buyer Address of the token buyer
     * @param usdAmount Amount of USD spent on the purchase
     * @param tokenAmount Amount of tokens purchased
     */
    event TokensPurchased(
        address indexed buyer,
        uint256 usdAmount,
        uint256 tokenAmount
    );

    /**
     * @dev Emitted when a new allocation is added
     * @param beneficiary Address of the token beneficiary
     * @param tokenAmount Amount of tokens allocated
     * @param tgeTimestamp Timestamp for the Token Generation Event
     * @param cliffDuration Duration of the cliff period
     * @param vestingDuration Total duration of the vesting period
     * @param roundId ID of the sale round
     */
    event AllocationAdded(
        address indexed beneficiary,
        uint256 tokenAmount,
        uint256 tgeTimestamp,
        uint256 cliffDuration,
        uint256 vestingDuration,
        uint256 roundId
    );

    /**
     * @dev Emitted when funds are withdrawn from a round
     * @param roundId ID of the round
     * @param usdcAmount Amount of USDC withdrawn
     * @param usdtAmount Amount of USDT withdrawn
     */
    event RoundFundsWithdrawn(
        uint256 indexed roundId,
        uint256 usdcAmount,
        uint256 usdtAmount
    );

    /**
     * @dev Emitted when the ICO is ended
     * @param claimEnabled Whether token claiming is enabled
     */
    event IcoEnded(bool claimEnabled);

    /**
     * @dev Emitted when refunds become available for a round
     * @param roundId ID of the round
     */
    event RefundsAvailableForRound(uint256 indexed roundId);

    /**
     * @dev Emitted when a refund is processed
     * @param user Address of the user receiving the refund
     * @param usdcAmount Amount of USDC refunded
     * @param usdtAmount Amount of USDT refunded
     */
    event Refunded(
        address indexed user,
        uint256 usdcAmount,
        uint256 usdtAmount
    );

    /**
     * @dev Emitted when USDC is withdrawn
     * @param recipient Address receiving the withdrawn USDC
     * @param amount Amount of USDC withdrawn
     */
    event UsdcWithdrawn(address indexed recipient, uint256 amount);

    /**
     * @dev Emitted when USDT is withdrawn
     * @param recipient Address receiving the withdrawn USDT
     * @param amount Amount of USDT withdrawn
     */
    event UsdtWithdrawn(address indexed recipient, uint256 amount);

    /**
     * @dev Emitted when ETH is withdrawn
     * @param recipient Address receiving the withdrawn ETH
     * @param amount Amount of ETH withdrawn
     */
    event EthWithdrawn(address indexed recipient, uint256 amount);

    /**
     * @dev Emitted when tokens are recovered
     * @param token Address of the recovered token
     * @param recipient Address receiving the recovered tokens
     * @param amount Amount of tokens recovered
     */
    event TokensRecovered(
        address indexed token,
        address indexed recipient,
        uint256 amount
    );

    /**
     * @dev Emitted when tokens are claimed
     * @param beneficiary Address of the beneficiary claiming tokens
     * @param amount Amount of tokens claimed
     */
    event TokensClaimed(address indexed beneficiary, uint256 amount);

    /**
     * @dev Emitted when addresses are added to the whitelist
     * @param roundId ID of the sale round
     * @param addresses Array of addresses added to the whitelist
     */
    event AddedToWhitelist(uint256 indexed roundId, address[] addresses);

    /**
     * @dev Emitted when addresses are removed from the whitelist
     * @param roundId ID of the sale round
     * @param addresses Array of addresses removed from the whitelist
     */
    event RemovedFromWhitelist(uint256 indexed roundId, address[] addresses);

    /**
     * @dev Emitted when a future round is updated
     * @param roundId ID of the updated round
     */
    event FutureRoundUpdated(uint256 indexed roundId);

    /**
     * @dev Emitted when cliff and vesting are adjusted
     * @param roundId ID of the round
     * @param newCliffDuration New cliff duration
     * @param newVestingDuration New vesting duration
     */
    event CliffAndVestingAdjusted(
        uint256 indexed roundId,
        uint256 newCliffDuration,
        uint256 newVestingDuration
    );

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
    error RoundCapExceeded();
    error NoTokensSent();
    error UsdcAmountMustBeGreaterThanZero();
    error UsdtAmountMustBeGreaterThanZero();
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
    error CannotRecoverUsdtTokens();
    error InsufficientTokenBalance();
    error ClaimingNotEnabled();
    error NoTokensAvailableToClaim();
    error NoEthToWithdraw();
    error EthTransferFailed();
    error NoActiveRound();
    error InvalidEthUsdPrice();

    // Functions
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
     * @param _cliffDuration Cliff duration for token vesting
     * @param _vestingDuration Total vesting duration
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
        uint256 _cliffDuration,
        uint256 _vestingDuration,
        uint256 _tgeReleasePercentage
    ) external;

    /**
     * @dev Allows admins to update parameters of a future round
     * @param _roundId ID of the round to update
     * @param _maxCap New maximum USD to be raised in this round
     * @param _maxPurchase New maximum purchase amount in USD
     */
    function updateFutureRound(
        uint256 _roundId,
        uint256 _maxCap,
        uint256 _maxPurchase
    ) external;

    /**
     * @dev Adds addresses to the whitelist for a specific round
     * @param _roundId ID of the sale round
     * @param _addresses Addresses to be added to the whitelist
     */
    function addToWhitelist(
        uint256 _roundId,
        address[] calldata _addresses
    ) external;

    /**
     * @dev Removes addresses from the whitelist for a specific round
     * @param _roundId ID of the sale round
     * @param _addresses Addresses to be removed from the whitelist
     */
    function removeFromWhitelist(
        uint256 _roundId,
        address[] calldata _addresses
    ) external;

    /**
     * @dev Allows users to buy tokens with ETH
     */
    function buyWithEth() external payable;

    /**
     * @dev Allows users to buy tokens with USDC
     * @param _amount Amount of USDC to spend on token purchase
     */
    function buyWithUsdc(uint256 _amount) external;

    /**
     * @dev Allows users to buy tokens with USDT
     * @param _amount Amount of USDT to spend on token purchase
     */
    function buyWithUsdt(uint256 _amount) external;

    /**
     * @dev Allows admins to add purchases made with fiat currency
     * @param _buyer Address of the token buyer
     * @param _usdAmount Amount of USD equivalent purchased
     */
    function addFiatPurchase(address _buyer, uint256 _usdAmount) external;

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
     * @dev Allows admins to withdraw raised USDT after ICO ends
     */
    function withdrawUsdt() external;

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
     * @dev Allows users to claim their tokens
     */
    function claimTokens() external;

    /**
     * @dev Allows admin to adjust cliff or vesting of a round (as part of DAO vote area)
     * @param _roundId ID of the round to adjust
     * @param _newCliffDuration New cliff duration
     * @param _newVestingDuration New vesting duration
     */
    function adjustCliffAndVesting(
        uint256 _roundId,
        uint256 _newCliffDuration,
        uint256 _newVestingDuration
    ) external;

    /**
     * @dev Calculates the claimable amount for a specific allocation.
     * @param _beneficiary Address of the beneficiary
     * @param _roundId ID of the sale round
     * @return claimableAmount Claimable token amount
     */
    function getClaimableAmount(
        address _beneficiary,
        uint256 _roundId
    ) external view returns (uint256 claimableAmount);

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
     * @dev Retrieves the allocation details for a specific beneficiary and round
     * @param _beneficiary Address of the beneficiary
     * @param _roundId ID of the sale round
     * @return The Allocation struct for the specified beneficiary and round
     */
    function getAllocationDetails(
        address _beneficiary,
        uint256 _roundId
    ) external view returns (Allocation memory);
}
