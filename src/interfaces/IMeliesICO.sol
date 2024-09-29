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
    // Custom Errors
    error InvalidTimeRange();
    error InvalidTokenPrice();
    error InvalidCap();
    error InvalidPurchaseLimits();
    error InvalidVestingDuration();
    error InvalidTgeReleasePercentage();
    error NoEthSent();
    error NoEthToWithdraw();
    error BelowMinimumPurchase();
    error ExceedsMaximumPurchase();
    error RoundCapExceeded();
    error NoTokensSent();
    error InvalidBeneficiaryAddress();
    error TokenAmountMustBeGreaterThanZero();
    error UsdcAmountMustBeGreaterThanZero();
    error ClaimingNotEnabled();
    error NoTokensAvailableToClaim();
    error IcoNotEndedYet();
    error EthTransferFailed();
    error RefundNotAvailable();
    error NoAllocationToRefund();
    error IcoAlreadyEnded();
    error NoActiveRound();
    error InvalidEthUsdPrice();
    error SlippageToleranceTooHigh();
    error RoundNotFinished();
    error SoftCapNotReached();
    error CannotModifyPastOrCurrentRound();
    error InvalidRoundParameters();
    error NotWhitelisted();
    error CannotRecoverMeliesTokens();
    error InsufficientTokenBalance();
    error CannotRecoverUsdcTokens();

    // Events
    /**
     * @dev Emitted when addresses are added to the whitelist for a specific round
     * @param roundId ID of the sale round
     * @param addresses Addresses added to the whitelist
     */
    event AddedToWhitelist(uint256 indexed roundId, address[] addresses);

    /**
     * @dev Emitted when addresses are removed from the whitelist for a specific round
     * @param roundId ID of the sale round
     * @param addresses Addresses removed from the whitelist
     */
    event RemovedFromWhitelist(uint256 indexed roundId, address[] addresses);

    /**
     * @dev Emitted when tokens are purchased.
     * @param buyer The address of the token buyer
     * @param usdcAmount The amount of USDC spent
     * @param tokenAmount The amount of tokens purchased
     */
    event TokensPurchased(
        address indexed buyer,
        uint256 usdcAmount,
        uint256 tokenAmount
    );

    /**
     * @dev Emitted when USDC is withdrawn by the admin.
     * @param admin The address of the admin who withdrew the USDC
     * @param amount The amount of USDC withdrawn
     */
    event UsdcWithdrawn(address indexed admin, uint256 amount);

    /**
     * @dev Emitted when a refund is processed.
     * @param buyer The address of the buyer receiving the refund
     * @param usdcAmount The amount of USDC refunded
     */
    event Refunded(address indexed buyer, uint256 usdcAmount);

    /**
     * @dev Emitted when the Uniswap router address is updated.
     * @param newRouterAddress The new address of the Uniswap router
     */
    event UniswapRouterUpdated(address newRouterAddress);

    /**
     * @dev Emitted when the slippage tolerance is updated.
     * @param newSlippageTolerance The new slippage tolerance value
     */
    event SlippageToleranceUpdated(uint256 newSlippageTolerance);

    /**
     * @dev Emitted when ETH is deposited into the contract.
     * @param depositor The address of the depositor
     * @param amount The amount of ETH deposited
     */
    event EthDeposited(address indexed depositor, uint256 amount);

    /**
     * @dev Emitted when ETH is withdrawn by the admin.
     * @param admin The address of the admin who withdrew the ETH
     * @param amount The amount of ETH withdrawn
     */
    event EthWithdrawn(address indexed admin, uint256 amount);

    /**
     * @dev Emitted when a new allocation is added or an existing one is updated.
     * @param beneficiary The address of the beneficiary
     * @param amount The amount of tokens allocated
     * @param startTime The start time of the vesting period
     * @param cliffDuration The duration of the cliff period
     * @param vestingDuration The duration of the vesting period
     * @param roundId The ID of the sale round
     */
    event AllocationAdded(
        address indexed beneficiary,
        uint256 amount,
        uint256 startTime,
        uint256 cliffDuration,
        uint256 vestingDuration,
        uint256 roundId
    );

    /**
     * @dev Emitted when tokens are claimed by a beneficiary.
     * @param beneficiary The address of the beneficiary claiming tokens
     * @param amount The amount of tokens claimed
     */
    event TokensClaimed(address indexed beneficiary, uint256 amount);

    /**
     * @dev Emitted when the end time of the current round is updated.
     * @param roundId The ID of the updated round
     * @param newEndTime The new end time for the round
     */
    event CurrentRoundEndTimeUpdated(uint256 roundId, uint256 newEndTime);

    /**
     * @dev Emitted when a future round's parameters are updated.
     * @param roundId The ID of the updated round
     */
    event FutureRoundUpdated(uint256 roundId);

    /**
     * @dev Emitted when funds are withdrawn for a specific round.
     * @param roundId The ID of the round
     * @param amount The amount of funds withdrawn
     */
    event RoundFundsWithdrawn(uint256 roundId, uint256 amount);

    /**
     * @dev Emitted when refunds become available for a specific round.
     * @param roundId The ID of the round
     */
    event RefundsAvailableForRound(uint256 roundId);

    /**
     * @dev Emitted when the ICO is ended.
     * @param claimingEnabled Whether token claiming is enabled after the ICO ends
     */
    event IcoEnded(bool claimingEnabled);

    /**
     * @dev Emitted when tokens are recovered by the admin.
     * @param token The address of the token recovered
     * @param recipient The address of the recipient
     * @param amount The amount of tokens recovered
     */
    event TokensRecovered(
        address indexed token,
        address indexed recipient,
        uint256 amount
    );

    // Structs
    /**
     * @dev Struct representing a sale round in the ICO.
     * @param startTime The start time of the sale round
     * @param endTime The end time of the sale round
     * @param tokenPrice The price of tokens in USDC (6 decimals)
     * @param maxCap The maximum amount of USDC to be raised in this round
     * @param softCap The minimum amount of USDC to be raised for the round to be considered successful
     * @param minPurchase The minimum purchase amount in USDC
     * @param maxPurchase The maximum purchase amount in USDC
     * @param totalRaised The total amount of USDC raised in this round
     * @param isFinish Whether the round has finished
     * @param cliffDuration The duration of the cliff period for token vesting
     * @param vestingDuration The total duration of the vesting period
     * @param lockDuration The duration of the lock period for tokens
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
        bool isFinish;
        uint256 cliffDuration;
        uint256 vestingDuration;
        uint256 tgeReleasePercentage;
        uint256 lockDuration;
    }

    /**
     * @dev Struct representing a token allocation for a beneficiary.
     * @param totalUsdcAmount The total amount of USDC invested
     * @param totalTokenAmount The total amount of tokens allocated
     * @param claimedAmount The amount of tokens already claimed
     * @param cliffDuration The duration of the cliff period for this allocation
     * @param vestingDuration The total duration of the vesting period for this allocation
     * @param lastClaimTimestamp The timestamp of the last claim for this allocation
     */
    struct Allocation {
        uint256 totalUsdcAmount;
        uint256 totalTokenAmount;
        uint256 claimedAmount;
        uint256 cliffDuration;
        uint256 vestingDuration;
        uint256 lastClaimTimestamp;
    }

    // Functions
    /**
     * @dev Updates the slippage tolerance for token swaps.
     * @param _newSlippageTolerance New slippage tolerance value (max 10%)
     */
    function updateSlippageTolerance(uint256 _newSlippageTolerance) external;

    /**
     * @dev Adds a new sale round to the ICO.
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
     * @param _lockDuration Lock duration for token vesting
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
        uint256 _tgeReleasePercentage,
        uint256 _lockDuration
    ) external;

    /**
     * @dev Allows users to buy tokens with ETH.
     */
    function buyWithEth() external payable;

    /**
     * @dev Allows users to buy tokens with USDC.
     * @param amount Amount of USDC to use for purchase
     */
    function buyWithUsdc(uint256 amount) external;

    /**
     * @dev Allows admins to add purchases made with fiat currency.
     * @param buyer Address of the buyer
     * @param usdcAmount Amount of USDC equivalent purchased
     */
    function addFiatPurchase(address buyer, uint256 usdcAmount) external;

    /**
     * @dev Allows users to claim their vested tokens.
     */
    function claimTokens() external;

    /**
     * @dev Allows admins to withdraw raised USDC after ICO ends.
     */
    function withdrawUsdc() external;

    /**
     * @dev Allows admins to withdraw any ETH in the contract after ICO ends.
     */
    function withdrawEth() external;

    /**
     * @dev Allows users to get a refund if ICO ends without enabling claims.
     */
    function refund() external;

    /**
     * @dev Allows admins to end the ICO.
     */
    function endIco() external;

    /**
     * @dev Calculates the claimable amount for a specific allocation.
     * @param _beneficiary Address of the beneficiary
     * @param _roundId ID of the sale round
     * @return claimableAmount Claimable token amount
     * @return tgeReleaseAmount TGE release amount
     * @return newLastClaimTimestamp New last claim timestamp
     */
    function getClaimableAmount(
        address _beneficiary,
        uint256 _roundId
    )
        external
        view
        returns (
            uint256 claimableAmount,
            uint256 tgeReleaseAmount,
            uint256 newLastClaimTimestamp
        );

    /**
     * @dev Returns the allocation details for a specific beneficiary and round.
     * @param _beneficiary Address of the beneficiary
     * @param _roundId ID of the sale round
     * @return The Allocation struct for the specified beneficiary and round
     */
    function getAllocationDetails(
        address _beneficiary,
        uint256 _roundId
    ) external view returns (Allocation memory);

    /**
     * @dev Allows admins to update the end time of the current round.
     * @param _newEndTime The new end time for the current round
     */
    function updateCurrentRoundEndTime(uint256 _newEndTime) external;

    /**
     * @dev Allows admins to update parameters of a future round.
     * @param _roundId ID of the round to update
     * @param _startTime New start time of the round
     * @param _endTime New end time of the round
     * @param _tokenPrice New token price in USDC (6 decimals)
     * @param _maxCap New maximum USDC to be raised in this round
     * @param _softCap New minimum USDC to be raised for the round to be considered successful
     * @param _minPurchase New minimum purchase amount in USDC
     * @param _maxPurchase New maximum purchase amount in USDC
     * @param _cliffDuration New cliff duration for token vesting
     * @param _vestingDuration New total vesting duration
     * @param _tgeReleasePercentage New TGE release percentage
     * @param _lockDuration New lock duration for token vesting
     */
    function updateFutureRound(
        uint256 _roundId,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _tokenPrice,
        uint256 _maxCap,
        uint256 _softCap,
        uint256 _minPurchase,
        uint256 _maxPurchase,
        uint256 _cliffDuration,
        uint256 _vestingDuration,
        uint256 _tgeReleasePercentage,
        uint256 _lockDuration
    ) external;

    /**
     * @dev Allows admins to withdraw funds raised in a specific round.
     * @param _roundId ID of the round to withdraw funds from
     */
    function withdrawRoundFunds(uint256 _roundId) external;

    /**
     * @dev Allows users to request a refund for a specific round if its soft cap wasn't reached.
     * @param _roundId ID of the round to request a refund from
     */
    function refundForRound(uint256 _roundId) external;

    /**
     * @dev Allows admins to recover any ERC20 tokens accidentally sent to the contract
     * @param _token Address of the ERC20 token to recover
     * @param _amount Amount of tokens to recover
     */
    function recoverTokens(address _token, uint256 _amount) external;
}
