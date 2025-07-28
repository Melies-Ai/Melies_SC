// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IMeliesTokenDistributor
 * @dev Interface for the Melies token distributor contract.
 * This interface defines the external functions, events, and structs
 * for managing token distribution and vesting schedules.
 *
 * @author Melies Team
 */
interface IMeliesTokenDistributor {
    // ============ STRUCTS ============

    /**
     * @dev Struct representing a token allocation
     * @param totalAmount Total amount of tokens allocated
     * @param claimedAmount Amount of tokens already claimed
     * @param cliffMonthDuration Duration of the cliff period in months
     * @param vestingMonthDuration Duration of the vesting period in months
     * @param beneficiary Address of the token beneficiary
     * @param allocationName Name of the allocation
     * @param tgeReleasePercentage TGE release percentage in basis points
     * @param lastClaimTimestamp Timestamp of last claim
     * @param bypassTgeRestriction Whether TGE restrictions are bypassed
     */
    struct Allocation {
        uint256 totalAmount;
        uint256 claimedAmount;
        uint256 cliffMonthDuration;
        uint256 vestingMonthDuration;
        address beneficiary;
        string allocationName;
        uint256 tgeReleasePercentage;
        uint256 lastClaimTimestamp;
        bool bypassTgeRestriction;
    }

    // ============ EVENTS ============

    /**
     * @dev Emitted when a new allocation is added
     * @param beneficiary Address of the beneficiary
     * @param amount Amount of tokens allocated
     * @param cliffMonthDuration Cliff duration in months
     * @param vestingMonthDuration Vesting duration in months
     * @param allocationName Name of the allocation
     * @param bypassTgeRestriction Whether TGE restrictions are bypassed
     */
    event AllocationAdded(
        address indexed beneficiary,
        uint256 amount,
        uint256 cliffMonthDuration,
        uint256 vestingMonthDuration,
        string allocationName,
        bool bypassTgeRestriction
    );

    /**
     * @dev Emitted when an allocation is updated
     * @param beneficiary Address of the beneficiary
     * @param oldAmount Previous amount
     * @param newAmount New amount
     * @param oldvestingMonthDuration Previous vesting duration
     * @param newvestingMonthDuration New vesting duration
     * @param allocationName Name of the allocation
     */
    event AllocationUpdated(
        address indexed beneficiary,
        uint256 oldAmount,
        uint256 newAmount,
        uint256 oldvestingMonthDuration,
        uint256 newvestingMonthDuration,
        string allocationName
    );

    /**
     * @dev Emitted when tokens are claimed
     * @param beneficiary Address of the beneficiary
     * @param amount Amount of tokens claimed
     * @param allocationName Name of the allocation
     */
    event TokensClaimed(address indexed beneficiary, uint256 amount, string allocationName);

    /**
     * @dev Emitted when tokens are burned due to early claiming
     * @param beneficiary Address of the beneficiary
     * @param amount Amount of tokens burned
     * @param allocationName Name of the allocation
     * @param haircutPercentage Percentage of tokens burned
     */
    event TokensBurned(address indexed beneficiary, uint256 amount, string allocationName, uint256 haircutPercentage);

    /**
     * @dev Emitted when unsold tokens are distributed
     * @param totalUnsoldTokens Total unsold tokens
     * @param communityAmount Amount distributed to community
     * @param liquidityAmount Amount distributed to liquidity
     * @param aiSystemsAmount Amount distributed to AI systems
     */
    event UnsoldTokensDistributed(
        uint256 totalUnsoldTokens, uint256 communityAmount, uint256 liquidityAmount, uint256 aiSystemsAmount
    );

    /**
     * @dev Emitted when TGE timestamp is set
     * @param tgeTimestamp The TGE timestamp
     */
    event TgeTimestampSet(uint256 tgeTimestamp);

    /**
     * @dev Emitted when token allocation amount is modified
     * @param beneficiary Address of the beneficiary
     * @param oldAmount Previous amount
     * @param newAmount New amount
     * @param allocationName Name of the allocation
     */
    event TokenAllocationAmountModified(
        address indexed beneficiary, uint256 oldAmount, uint256 newAmount, string allocationName
    );

    // ============ ERRORS ============

    error InvalidBeneficiary();
    error InvalidAmount();
    error InvalidStartTime();
    error InvalidDuration();
    error CannotAddAllocationAfterTge();
    error NoTokensAvailable();
    error MustWaitUntilTge();
    error AllocationAlreadyExists();
    error InvalidTgeReleasePercentage();
    error UnsoldTokensAlreadyDistributed();
    error AllocationNotFound();
    error TgeTimestampAlreadySet();
    error TgeTimestampNotSet();
    error CallerIsNotAdminOrIco();
    error CannotModifyAfterTge();
    error TokenSupplyExceeded();

    // ============ FUNCTIONS ============

    /**
     * @dev Sets the TGE timestamp (one-time only, admin only)
     * @param _tgeTimestamp The TGE timestamp to set
     *
     * Requirements:
     * - Caller must have ADMIN_ROLE
     * - TGE timestamp must not already be set
     * - TGE timestamp must be valid
     *
     * Emits a {TgeTimestampSet} event.
     */
    function setTgeTimestamp(uint256 _tgeTimestamp) external;

    /**
     * @dev Modifies the total amount for a token allocation (admin only, before TGE)
     * @param allocationIndex Index of the token allocation to modify
     * @param newAmount New total amount for the allocation
     *
     * Requirements:
     * - Caller must have ADMIN_ROLE
     * - Allocation must exist
     * - New amount must be greater than 0
     * - Cannot modify after TGE
     *
     * Emits a {TokenAllocationAmountModified} event.
     */
    function modifyTokenAllocationAmount(uint256 allocationIndex, uint256 newAmount) external;

    /**
     * @dev Calculates haircut percentage for early claiming based on allocation type
     * @param allocationName Name of the allocation (Seed, Private Sale, Public Sale)
     * @param monthsPassed Number of months passed since TGE
     * @return haircutPercentage Percentage of tokens to burn (in basis points, 10000 = 100%)
     */
    function calculateHaircutPercentage(string memory allocationName, uint256 monthsPassed)
        external
        pure
        returns (uint256);

    /**
     * @dev Claims vested tokens for a specific allocation (normal vesting schedule, no haircut)
     * @param allocationIndex Index of the allocation
     * @param isRoundAllocation Whether this is a round allocation (true) or token allocation (false)
     *
     * Requirements:
     * - Caller must be the beneficiary
     * - There must be tokens available to claim
     *
     * Emits a {TokensClaimed} event.
     */
    function claimTokens(uint256 allocationIndex, bool isRoundAllocation) external;

    /**
     * @dev Claims all tokens (including unvested) with haircut penalty for early claiming
     * @param allocationIndex Index of the allocation
     * @param isRoundAllocation Whether this is a round allocation (true) or token allocation (false)
     *
     * Requirements:
     * - Caller must be the beneficiary
     * - There must be tokens available to claim
     * - TGE must have occurred
     *
     * Emits a {TokensClaimed} event and potentially a {TokensBurned} event.
     */
    function claimAllTokensWithHaircut(uint256 allocationIndex, bool isRoundAllocation) external;

    /**
     * @dev Adds a new allocation (admin only) for off-chain deals
     * @param beneficiary Address of the beneficiary
     * @param amount Total amount of tokens
     * @param cliffMonths Cliff period in months
     * @param vestingMonths Vesting period in months
     * @param allocationName Name of the allocation
     * @param tgeReleasePercentage TGE release percentage (in basis points, 10000 = 100%)
     * @param bypassTgeRestriction Allow claiming TGE tokens before TGE (for off-chain platforms)
     *
     * Requirements:
     * - Caller must have ADMIN_ROLE or ICO_ROLE
     * - Cannot add allocation after TGE
     * - All parameters must be valid
     *
     * Emits an {AllocationAdded} event.
     */
    function addAllocation(
        address beneficiary,
        uint256 amount,
        uint256 cliffMonths,
        uint256 vestingMonths,
        string memory allocationName,
        uint256 tgeReleasePercentage,
        bool bypassTgeRestriction
    ) external;

    /**
     * @dev Distributes unsold tokens to Community Fund (50%), Liquidity (25%), and AI Systems (25%)
     *
     * Requirements:
     * - Caller must have ADMIN_ROLE
     * - TGE timestamp must be set
     * - Can only be called after TGE
     * - Can only be called once
     *
     * Emits an {UnsoldTokensDistributed} event.
     */
    function distributeUnsoldTokens() external;

    /**
     * @dev Calculates claimable tokens for an allocation
     * @param allocationIndex Index of the allocation
     * @param isRoundAllocation Whether this is a round allocation (true) or token allocation (false)
     * @return Amount of tokens that can be claimed
     */
    function getClaimableAmount(uint256 allocationIndex, bool isRoundAllocation) external view returns (uint256);

    // ============ VIEW FUNCTIONS ============

    /**
     * @dev Gets all token allocations for a beneficiary
     * @param beneficiary Address of the beneficiary
     * @return Array of allocation indices
     */
    function getTokenAllocationsForBeneficiary(address beneficiary) external view returns (uint256[] memory);

    /**
     * @dev Gets all round allocations for a beneficiary
     * @param beneficiary Address of the beneficiary
     * @return Array of allocation indices
     */
    function getRoundAllocationsForBeneficiary(address beneficiary) external view returns (uint256[] memory);

    /**
     * @dev Gets token allocation index for a specific beneficiary and allocation name
     * @param beneficiary Address of the beneficiary
     * @param allocationName Name of the allocation
     * @return allocationIndex Index of the allocation (returns type(uint256).max if not found)
     */
    function getTokenAllocationIndex(address beneficiary, string memory allocationName)
        external
        view
        returns (uint256);

    /**
     * @dev Gets round allocation index for a specific beneficiary and allocation name
     * @param beneficiary Address of the beneficiary
     * @param allocationName Name of the allocation
     * @return allocationIndex Index of the allocation (returns type(uint256).max if not found)
     */
    function getRoundAllocationIndex(address beneficiary, string memory allocationName)
        external
        view
        returns (uint256);

    /**
     * @dev Gets total number of token allocations
     * @return Total number of token allocations in the contract
     */
    function getTokenAllocationsCount() external view returns (uint256);

    /**
     * @dev Gets total number of round allocations
     * @return Total number of round allocations in the contract
     */
    function getRoundAllocationsCount() external view returns (uint256);

    /**
     * @dev Gets the total tokens sold in ICO rounds
     * @return Total tokens sold
     */
    function getTotalTokensSold() external view returns (uint256);

    /**
     * @dev Gets the total unsold tokens
     * @return Total unsold tokens
     */
    function getUnsoldTokens() external view returns (uint256);

    /**
     * @dev Checks if unsold tokens have been distributed
     * @return True if unsold tokens have been distributed
     */
    function isUnsoldTokensDistributed() external view returns (bool);

    /**
     * @dev Gets the sales performance percentage
     * @return Sales performance as a percentage (0-100)
     */
    function getSalesPerformance() external view returns (uint256);

    /**
     * @dev Gets the total amount from all admin allocations (off-chain sales)
     * @return Total amount from admin allocations
     */
    function getTotalSalesAllocations() external view returns (uint256);

    /**
     * @dev Gets the total tokens burned due to vesting haircuts
     * @return Total tokens burned
     */
    function getTotalTokensBurned() external view returns (uint256);

    /**
     * @dev Gets the tokens sold in Seed round
     * @return Tokens sold in Seed round
     */
    function getSeedTokensSold() external view returns (uint256);

    /**
     * @dev Gets the tokens sold in Private Sale round
     * @return Tokens sold in Private Sale round
     */
    function getPrivateSaleTokensSold() external view returns (uint256);

    /**
     * @dev Gets the tokens sold in Public Sale round
     * @return Tokens sold in Public Sale round
     */
    function getPublicSaleTokensSold() external view returns (uint256);

    /**
     * @dev Checks if TGE timestamp has been set
     * @return True if TGE timestamp has been set
     */
    function isTgeTimestampSet() external view returns (bool);

    /**
     * @dev Checks if a token allocation has TGE bypass enabled
     * @param allocationIndex Index of the allocation
     * @return True if allocation can bypass TGE restrictions
     */
    function hasTokenTgeBypass(uint256 allocationIndex) external view returns (bool);

    /**
     * @dev Checks if a round allocation has TGE bypass enabled
     * @param allocationIndex Index of the allocation
     * @return True if allocation can bypass TGE restrictions
     */
    function hasRoundTgeBypass(uint256 allocationIndex) external view returns (bool);

    /**
     * @dev Gets detailed token allocation information
     * @param allocationIndex Index of the allocation
     * @return totalAmount Total amount of tokens
     * @return claimedAmount Amount of tokens already claimed
     * @return cliffMonthDuration Cliff duration in months
     * @return vestingMonthDuration Vesting duration in months
     * @return beneficiary Address of the beneficiary
     * @return allocationName Name of the allocation
     * @return tgeReleasePercentage TGE release percentage
     * @return lastClaimTimestamp Last claim timestamp
     * @return bypassTgeRestriction Whether TGE restrictions are bypassed
     */
    function getTokenAllocationDetails(uint256 allocationIndex)
        external
        view
        returns (
            uint256 totalAmount,
            uint256 claimedAmount,
            uint256 cliffMonthDuration,
            uint256 vestingMonthDuration,
            address beneficiary,
            string memory allocationName,
            uint256 tgeReleasePercentage,
            uint256 lastClaimTimestamp,
            bool bypassTgeRestriction
        );

    /**
     * @dev Gets detailed round allocation information
     * @param allocationIndex Index of the allocation
     * @return totalAmount Total amount of tokens
     * @return claimedAmount Amount of tokens already claimed
     * @return cliffMonthDuration Cliff duration in months
     * @return vestingMonthDuration Vesting duration in months
     * @return beneficiary Address of the beneficiary
     * @return allocationName Name of the allocation
     * @return tgeReleasePercentage TGE release percentage
     * @return lastClaimTimestamp Last claim timestamp
     * @return bypassTgeRestriction Whether TGE restrictions are bypassed
     */
    function getRoundAllocationDetails(uint256 allocationIndex)
        external
        view
        returns (
            uint256 totalAmount,
            uint256 claimedAmount,
            uint256 cliffMonthDuration,
            uint256 vestingMonthDuration,
            address beneficiary,
            string memory allocationName,
            uint256 tgeReleasePercentage,
            uint256 lastClaimTimestamp,
            bool bypassTgeRestriction
        );

    /**
     * @dev Gets haircut information for a specific token allocation at current time
     * @param allocationIndex Index of the allocation
     * @return haircutPercentage Current haircut percentage (in basis points)
     * @return monthsPassed Months passed since TGE
     */
    function getTokenHaircutInfo(uint256 allocationIndex)
        external
        view
        returns (uint256 haircutPercentage, uint256 monthsPassed);

    /**
     * @dev Gets haircut information for a specific round allocation at current time
     * @param allocationIndex Index of the allocation
     * @return haircutPercentage Current haircut percentage (in basis points)
     * @return monthsPassed Months passed since TGE
     */
    function getRoundHaircutInfo(uint256 allocationIndex)
        external
        view
        returns (uint256 haircutPercentage, uint256 monthsPassed);

    /**
     * @dev Gets the actual start time for a token allocation (TGE + cliff duration)
     * @param allocationIndex Index of the allocation
     * @return actualStartTime The actual start time when vesting begins
     */
    function getTokenActualStartTime(uint256 allocationIndex) external view returns (uint256 actualStartTime);

    /**
     * @dev Gets the actual start time for a round allocation (TGE + cliff duration)
     * @param allocationIndex Index of the allocation
     * @return actualStartTime The actual start time when vesting begins
     */
    function getRoundActualStartTime(uint256 allocationIndex) external view returns (uint256 actualStartTime);

    /**
     * @dev Simulates normal token claim for token allocation (vested tokens only, no haircut)
     * @param allocationIndex Index of the allocation
     * @return claimableAmount Amount that can be claimed through normal vesting
     */
    function simulateTokenClaim(uint256 allocationIndex) external view returns (uint256 claimableAmount);

    /**
     * @dev Simulates normal token claim for round allocation (vested tokens only, no haircut)
     * @param allocationIndex Index of the allocation
     * @return claimableAmount Amount that can be claimed through normal vesting
     */
    function simulateRoundClaim(uint256 allocationIndex) external view returns (uint256 claimableAmount);

    /**
     * @dev Returns true if an account has a specific role
     * @param role The role to check
     * @param account The account to check
     * @return True if the account has the role
     */
    function hasRole(bytes32 role, address account) external view returns (bool);
}
