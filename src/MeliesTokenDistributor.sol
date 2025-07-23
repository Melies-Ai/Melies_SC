// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./Melies.sol";

/**
 * @title MeliesTokenDistributor
 * @dev Manages token distribution and vesting for different allocations
 */
contract MeliesTokenDistributor is AccessControl, ReentrancyGuard {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant ICO_ROLE = keccak256("ICO_ROLE");

    Melies public meliesToken;
    uint256 public tgeTimestamp;

    // Total tokens allocated for ICO sales (Seed + Private Sale + Public Sale)
    uint256 public constant TOTAL_ICO_TOKENS = 300_000_000e8; // 300M tokens

    // Track tokens sold per round (for informational purposes only)
    uint256 public seedTokensSold;
    uint256 public privateSaleTokensSold;
    uint256 public publicSaleTokensSold;

    uint256 public totalTokensSold;
    bool public unsoldTokensDistributed;
    uint256 public totalTokensBurned; // Track total burned tokens
    bool public tgeTimestampSet; // Track if TGE timestamp has been set

    struct Allocation {
        uint256 totalAmount;
        uint256 claimedAmount;
        uint256 cliffMonthDuration; // Duration in months
        uint256 vestingMonthDuration; // Duration in months
        address beneficiary;
        string allocationName;
        uint256 tgeReleasePercentage;
        uint256 lastClaimTimestamp;
        bool bypassTgeRestriction; // Allow claiming TGE tokens before TGE (admin only)
    }

    Allocation[] public tokenAllocations; // Community, Treasury, Partners, Team, Liquidity, AI Systems
    Allocation[] public roundAllocations; // ICO rounds (Seed, Private Sale, Public Sale) and off-chain deals (IDO, IEO, platform deals)

    // Mapping to track allocation indices by beneficiary and name
    mapping(address => mapping(string => uint256))
        private tokenAllocationIndices;
    mapping(address => mapping(string => uint256))
        private roundAllocationIndices;
    mapping(address => mapping(string => bool)) private tokenAllocationExists;
    mapping(address => mapping(string => bool)) private roundAllocationExists;

    // Events
    event AllocationAdded(
        address indexed beneficiary,
        uint256 amount,
        uint256 cliffMonthDuration,
        uint256 vestingMonthDuration,
        string allocationName,
        bool bypassTgeRestriction
    );
    event AllocationUpdated(
        address indexed beneficiary,
        uint256 oldAmount,
        uint256 newAmount,
        uint256 oldvestingMonthDuration,
        uint256 newvestingMonthDuration,
        string allocationName
    );
    event TokensClaimed(
        address indexed beneficiary,
        uint256 amount,
        string allocationName
    );
    event TokensBurned(
        address indexed beneficiary,
        uint256 amount,
        string allocationName,
        uint256 haircutPercentage
    );
    event UnsoldTokensDistributed(
        uint256 totalUnsoldTokens,
        uint256 communityAmount,
        uint256 liquidityAmount,
        uint256 aiSystemsAmount
    );
    event TgeTimestampSet(uint256 tgeTimestamp);
    event TokenAllocationAmountModified(
        address indexed beneficiary,
        uint256 oldAmount,
        uint256 newAmount,
        string allocationName
    );

    // Errors
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

    /**
     * @dev Constructor
     * @param _meliesToken Address of the Melies token contract
     * @param admin Address of the admin
     * @param communityAddress Address for community fund
     * @param treasuryAddress Address for treasury
     * @param partnersAddress Address for partners & advisors
     * @param teamAddress Address for team
     * @param liquidityAddress Address for liquidity
     * @param aiSystemsAddress Address for AI systems
     */
    constructor(
        address _meliesToken,
        address admin,
        address communityAddress,
        address treasuryAddress,
        address partnersAddress,
        address teamAddress,
        address liquidityAddress,
        address aiSystemsAddress
    ) {
        meliesToken = Melies(_meliesToken);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);

        setupInitialAllocations(
            communityAddress,
            treasuryAddress,
            partnersAddress,
            teamAddress,
            liquidityAddress,
            aiSystemsAddress
        );
    }

    /**
     * @dev Sets the TGE timestamp (one-time only, admin only)
     * @param _tgeTimestamp The TGE timestamp to set
     */
    function setTgeTimestamp(
        uint256 _tgeTimestamp
    ) external onlyRole(ADMIN_ROLE) {
        if (tgeTimestampSet) revert TgeTimestampAlreadySet();
        if (_tgeTimestamp == 0 || _tgeTimestamp < block.timestamp)
            revert InvalidStartTime();

        tgeTimestamp = _tgeTimestamp;
        tgeTimestampSet = true;

        emit TgeTimestampSet(_tgeTimestamp);
    }

    /**
     * @dev Modifies the total amount for a token allocation (admin only, before TGE)
     * @param allocationIndex Index of the token allocation to modify
     * @param newAmount New total amount for the allocation
     */
    function modifyTokenAllocationAmount(
        uint256 allocationIndex,
        uint256 newAmount
    ) external onlyRole(ADMIN_ROLE) {
        if (tgeTimestampSet && block.timestamp >= tgeTimestamp) {
            revert CannotModifyAfterTge();
        }
        if (allocationIndex >= tokenAllocations.length) {
            revert AllocationNotFound();
        }
        if (newAmount == 0) revert InvalidAmount();

        Allocation storage allocation = tokenAllocations[allocationIndex];
        uint256 oldAmount = allocation.totalAmount;

        allocation.totalAmount = newAmount;

        emit TokenAllocationAmountModified(
            allocation.beneficiary,
            oldAmount,
            newAmount,
            allocation.allocationName
        );
    }

    /**
     * @dev Calculates haircut percentage for early claiming based on allocation type
     * @param allocationName Name of the allocation (Seed, Private Sale, Public Sale)
     * @param monthsPassed Number of months passed since TGE
     * @return haircutPercentage Percentage of tokens to burn (in basis points, 10000 = 100%)
     */
    function calculateHaircutPercentage(
        string memory allocationName,
        uint256 monthsPassed
    ) public pure returns (uint256) {
        bytes32 nameHash = keccak256(bytes(allocationName));
        bytes32 seedHash = keccak256(bytes("Seed"));
        bytes32 privateHash = keccak256(bytes("Private Sale"));
        bytes32 publicHash = keccak256(bytes("Public Sale"));

        if (nameHash == seedHash) {
            return _calculateSeedHaircut(monthsPassed);
        } else if (nameHash == privateHash) {
            return _calculatePrivateSaleHaircut(monthsPassed);
        } else if (nameHash == publicHash) {
            return _calculatePublicSaleHaircut(monthsPassed);
        }

        // No haircut for other allocations
        return 0;
    }

    /**
     * @dev Calculates haircut for Seed round
     * @param monthsPassed Number of months passed since TGE
     * @return haircutPercentage Percentage to burn (in basis points)
     */
    function _calculateSeedHaircut(
        uint256 monthsPassed
    ) internal pure returns (uint256) {
        if (monthsPassed == 0) return 9000; // TGE: 90%
        if (monthsPassed >= 8) return 0; // Month 8+: 0%

        // Linear decrease: 90% at month 1, 0% at month 8
        // Each month reduces by 12.857% (9000 / 7 = ~1286 basis points)
        uint256 reductionPerMonth = 1286;
        uint256 reduction = reductionPerMonth * (monthsPassed - 1);

        if (reduction >= 9000) return 0;
        return 9000 - reduction;
    }

    /**
     * @dev Calculates haircut for Private Sale round
     * @param monthsPassed Number of months passed since TGE
     * @return haircutPercentage Percentage to burn (in basis points)
     */
    function _calculatePrivateSaleHaircut(
        uint256 monthsPassed
    ) internal pure returns (uint256) {
        if (monthsPassed == 0) return 9000; // TGE: 90%
        if (monthsPassed >= 10) return 0; // Month 10+: 0%

        // Linear decrease: 90% at month 1, 0% at month 10
        // Each month reduces by 10% (1000 basis points)
        uint256 reduction = 1000 * (monthsPassed - 1);

        if (reduction >= 9000) return 0;
        return 9000 - reduction;
    }

    /**
     * @dev Calculates haircut for Public Sale round
     * @param monthsPassed Number of months passed since TGE
     * @return haircutPercentage Percentage to burn (in basis points)
     */
    function _calculatePublicSaleHaircut(
        uint256 monthsPassed
    ) internal pure returns (uint256) {
        if (monthsPassed == 0) return 9000; // TGE: 90%
        if (monthsPassed >= 11) return 0; // Month 11+: 0%

        // Linear decrease: 90% at month 1, 0% at month 11
        // Each month reduces by 9% (900 basis points)
        uint256 reduction = 900 * (monthsPassed - 1);

        if (reduction >= 9000) return 0;
        return 9000 - reduction;
    }

    /**
     * @dev Claims vested tokens for a specific allocation (normal vesting schedule, no haircut)
     * @param allocationIndex Index of the allocation
     * @param isRoundAllocation Whether this is a round allocation (true) or token allocation (false)
     */
    function claimTokens(
        uint256 allocationIndex,
        bool isRoundAllocation
    ) external nonReentrant {
        Allocation storage allocation = isRoundAllocation
            ? roundAllocations[allocationIndex]
            : tokenAllocations[allocationIndex];

        if (allocation.beneficiary != msg.sender) revert InvalidBeneficiary();

        uint256 claimableAmount = getClaimableAmount(
            allocationIndex,
            isRoundAllocation
        );
        if (claimableAmount == 0) revert NoTokensAvailable();

        allocation.lastClaimTimestamp = block.timestamp;
        allocation.claimedAmount += claimableAmount;

        meliesToken.mint(allocation.beneficiary, claimableAmount);

        emit TokensClaimed(
            allocation.beneficiary,
            claimableAmount,
            allocation.allocationName
        );
    }

    /**
     * @dev Claims all tokens (including unvested) with haircut penalty for early claiming
     * @param allocationIndex Index of the allocation
     * @param isRoundAllocation Whether this is a round allocation (true) or token allocation (false)
     */
    function claimAllTokensWithHaircut(
        uint256 allocationIndex,
        bool isRoundAllocation
    ) external nonReentrant {
        Allocation storage allocation = isRoundAllocation
            ? roundAllocations[allocationIndex]
            : tokenAllocations[allocationIndex];

        if (allocation.beneficiary != msg.sender) revert InvalidBeneficiary();

        // Calculate total remaining tokens (including unvested)
        uint256 remainingTokens = allocation.totalAmount -
            allocation.claimedAmount;
        if (remainingTokens == 0) revert NoTokensAvailable();

        // Calculate months passed since TGE for haircut calculation
        uint256 monthsPassed = 0;
        if (!tgeTimestampSet) revert TgeTimestampNotSet();
        if (block.timestamp >= tgeTimestamp) {
            monthsPassed = (block.timestamp - tgeTimestamp) / 30 days;
        } else {
            revert MustWaitUntilTge();
        }

        // Calculate haircut percentage
        uint256 haircutPercentage = calculateHaircutPercentage(
            allocation.allocationName,
            monthsPassed
        );

        // Calculate amounts to burn and mint
        uint256 burnAmount = 0;
        uint256 mintAmount = remainingTokens;

        if (haircutPercentage > 0) {
            burnAmount = (remainingTokens * haircutPercentage) / 10000;
            mintAmount = remainingTokens - burnAmount;

            // Update total burned tokens
            totalTokensBurned += burnAmount;

            // Mint burn amount to distributor, then burn it
            if (burnAmount > 0) {
                meliesToken.mint(address(this), burnAmount);
                meliesToken.burn(address(this), burnAmount);
            }

            // Emit burn event
            emit TokensBurned(
                allocation.beneficiary,
                burnAmount,
                allocation.allocationName,
                haircutPercentage
            );
        }

        allocation.lastClaimTimestamp = block.timestamp;
        allocation.claimedAmount = allocation.totalAmount; // Mark all tokens as claimed

        // Mint the amount after haircut to beneficiary
        if (mintAmount > 0) {
            meliesToken.mint(allocation.beneficiary, mintAmount);
        }

        emit TokensClaimed(
            allocation.beneficiary,
            mintAmount,
            allocation.allocationName
        );
    }

    /**
     * @dev Sets up initial allocations
     * @param communityAddress Address for community fund
     * @param treasuryAddress Address for treasury
     * @param partnersAddress Address for partners & advisors
     * @param teamAddress Address for team
     * @param liquidityAddress Address for liquidity
     * @param aiSystemsAddress Address for AI systems
     */
    function setupInitialAllocations(
        address communityAddress,
        address treasuryAddress,
        address partnersAddress,
        address teamAddress,
        address liquidityAddress,
        address aiSystemsAddress
    ) internal {
        // Community Fund: 200M tokens, no cliff, 48 months vesting, 2.08% TGE
        _createTokenAllocation(
            communityAddress,
            200_000_000e8,
            0,
            48,
            "Community",
            208,
            false // No bypass for TGE restrictions
        );

        // Treasury: 100M tokens, no cliff, 48 months vesting, 5.00% TGE
        _createTokenAllocation(
            treasuryAddress,
            100_000_000e8,
            0,
            48,
            "Treasury",
            500,
            false // No bypass for TGE restrictions
        );

        // Partners & Advisors: 100M tokens, no cliff, 18 months vesting, 10.00% TGE
        _createTokenAllocation(
            partnersAddress,
            100_000_000e8,
            0,
            18,
            "Partners",
            1000,
            false // No bypass for TGE restrictions
        );

        // Team: 100M tokens, 12 months cliff, 20 months vesting, 0.00% TGE
        _createTokenAllocation(
            teamAddress,
            100_000_000e8,
            12,
            20,
            "Team",
            0,
            false // No bypass for TGE restrictions
        );

        // Liquidity: 100M tokens, available at TGE, 100.00% TGE
        _createTokenAllocation(
            liquidityAddress,
            100_000_000e8,
            0,
            1,
            "Liquidity",
            10000,
            false // No bypass for TGE restrictions
        );

        // AI Systems: 100M tokens, no cliff, 18 months vesting, 10.00% TGE
        _createTokenAllocation(
            aiSystemsAddress,
            100_000_000e8,
            0,
            18,
            "AI Systems",
            1000,
            false // No bypass for TGE restrictions
        );
    }

    /**
     * @dev Validates that the total allocation doesn't exceed ICO token limit
     * @param amount Amount to be added
     */
    function _validateTokenSupply(uint256 amount) internal view {
        // Check if adding this amount would exceed the total ICO tokens
        if (totalTokensSold + amount > TOTAL_ICO_TOKENS) {
            revert TokenSupplyExceeded();
        }
    }

    /**
     * @dev Updates round-specific token sold counters
     * @param allocationName Name of the allocation
     * @param amount Amount to be added
     */
    function _updateRoundCounters(
        string memory allocationName,
        uint256 amount
    ) internal {
        bytes32 nameHash = keccak256(bytes(allocationName));
        bytes32 seedHash = keccak256(bytes("Seed"));
        bytes32 privateHash = keccak256(bytes("Private Sale"));
        bytes32 publicHash = keccak256(bytes("Public Sale"));

        if (nameHash == seedHash) {
            seedTokensSold += amount;
        } else if (nameHash == privateHash) {
            privateSaleTokensSold += amount;
        } else if (nameHash == publicHash) {
            publicSaleTokensSold += amount;
        }
    }

    /**
     * @dev Adds a new allocation (admin only) for off-chain deals
     * from admin : off-chain deals (fiat payments, IDO, IEO, platform deals, etc.)
     * from ICO : ICO rounds investors (Seed, Private Sale, Public Sale)
     * @param beneficiary Address of the beneficiary
     * @param amount Total amount of tokens
     * @param cliffMonths Cliff period in months
     * @param vestingMonths Vesting period in months
     * @param allocationName Name of the allocation
     * @param tgeReleasePercentage TGE release percentage (in basis points, 10000 = 100%)
     * @param bypassTgeRestriction Allow claiming TGE tokens before TGE (for off-chain platforms)
     */
    function addAllocation(
        address beneficiary,
        uint256 amount,
        uint256 cliffMonths,
        uint256 vestingMonths,
        string memory allocationName,
        uint256 tgeReleasePercentage,
        bool bypassTgeRestriction
    ) public {
        if (!hasRole(ADMIN_ROLE, msg.sender) && !hasRole(ICO_ROLE, msg.sender))
            revert CallerIsNotAdminOrIco();
        if (tgeTimestampSet && block.timestamp > tgeTimestamp) {
            revert CannotAddAllocationAfterTge();
        }

        // Validate token supply limits
        _validateTokenSupply(amount);

        // Update round-specific counters
        _updateRoundCounters(allocationName, amount);

        // All admin allocations count as sales
        totalTokensSold += amount;

        _createRoundAllocation(
            beneficiary,
            amount,
            cliffMonths,
            vestingMonths,
            allocationName,
            tgeReleasePercentage,
            bypassTgeRestriction
        );
    }

    /**
     * @dev Distributes unsold tokens to Community Fund (50%), Liquidity (25%), and AI Systems (25%)
     * Unsold tokens = TOTAL_ICO_TOKENS (300M) - totalTokensSold (actual sales from ICO + off-chain)
     * Can only be called once by ICO contract after TGE
     */
    function distributeUnsoldTokens() external onlyRole(ADMIN_ROLE) {
        // Prevent multiple calls
        if (unsoldTokensDistributed) revert UnsoldTokensAlreadyDistributed();

        // Ensure TGE timestamp is set
        if (!tgeTimestampSet) revert TgeTimestampNotSet();

        // Ensure function can only be called after TGE (when ICO rounds should be finished)
        if (block.timestamp < tgeTimestamp) {
            revert MustWaitUntilTge();
        }

        uint256 unsoldTokens = TOTAL_ICO_TOKENS - totalTokensSold;
        if (unsoldTokens == 0) {
            // Mark as distributed even if no tokens to distribute
            unsoldTokensDistributed = true;
            return;
        }

        // Calculate distribution amounts
        uint256 communityAmount = (unsoldTokens * 50) / 100; // 50%
        uint256 liquidityAmount = (unsoldTokens * 25) / 100; // 25%
        uint256 aiSystemsAmount = (unsoldTokens * 25) / 100; // 25%

        // Update existing allocations
        _updateAllocationAmount("Community", communityAmount);
        _updateAllocationAmount("Liquidity", liquidityAmount);
        _updateAllocationAmount("AI Systems", aiSystemsAmount);

        // Update vesting periods based on token sales performance
        _updateDynamicVestingPeriods();

        // Mark as distributed to prevent multiple calls
        unsoldTokensDistributed = true;

        emit UnsoldTokensDistributed(
            unsoldTokens,
            communityAmount,
            liquidityAmount,
            aiSystemsAmount
        );
    }

    /**
     * @dev Updates dynamic vesting periods for Community Fund and AI Systems based on token sales
     */
    function _updateDynamicVestingPeriods() internal {
        uint256 salesPerformance = (totalTokensSold * 100) / TOTAL_ICO_TOKENS;

        uint256 communityVestingMonths;
        uint256 aiSystemsVestingMonths;

        if (salesPerformance >= 100) {
            // Full token sold
            communityVestingMonths = 48;
            aiSystemsVestingMonths = 18;
        } else if (salesPerformance >= 50) {
            // Total token sold / 2
            communityVestingMonths = 66;
            aiSystemsVestingMonths = 25;
        } else if (salesPerformance >= 25) {
            // Total token sold / 4
            communityVestingMonths = 75;
            aiSystemsVestingMonths = 28;
        } else {
            // Total token sold / 20 (less than 25%)
            communityVestingMonths = 82;
            aiSystemsVestingMonths = 31;
        }

        // Update vesting periods
        _updateAllocationVesting("Community", communityVestingMonths);
        _updateAllocationVesting("AI Systems", aiSystemsVestingMonths);
    }

    /**
     * @dev Updates the amount of tokens for an existing allocation
     * @param allocationName Name of the allocation to update
     * @param additionalAmount Additional amount to add to the allocation
     */
    function _updateAllocationAmount(
        string memory allocationName,
        uint256 additionalAmount
    ) internal {
        for (uint256 i = 0; i < tokenAllocations.length; i++) {
            if (
                keccak256(bytes(tokenAllocations[i].allocationName)) ==
                keccak256(bytes(allocationName))
            ) {
                uint256 oldAmount = tokenAllocations[i].totalAmount;
                tokenAllocations[i].totalAmount += additionalAmount;

                emit AllocationUpdated(
                    tokenAllocations[i].beneficiary,
                    oldAmount,
                    tokenAllocations[i].totalAmount,
                    tokenAllocations[i].vestingMonthDuration,
                    tokenAllocations[i].vestingMonthDuration,
                    allocationName
                );
                return;
            }
        }
        revert AllocationNotFound();
    }

    /**
     * @dev Updates the vesting period for an existing allocation
     * @param allocationName Name of the allocation to update
     * @param vestingMonths New vesting period in months
     */
    function _updateAllocationVesting(
        string memory allocationName,
        uint256 vestingMonths
    ) internal {
        for (uint256 i = 0; i < tokenAllocations.length; i++) {
            if (
                keccak256(bytes(tokenAllocations[i].allocationName)) ==
                keccak256(bytes(allocationName))
            ) {
                uint256 oldvestingMonthDuration = tokenAllocations[i]
                    .vestingMonthDuration;
                tokenAllocations[i].vestingMonthDuration = vestingMonths; // Store in months

                emit AllocationUpdated(
                    tokenAllocations[i].beneficiary,
                    tokenAllocations[i].totalAmount,
                    tokenAllocations[i].totalAmount,
                    oldvestingMonthDuration,
                    tokenAllocations[i].vestingMonthDuration,
                    allocationName
                );
                return;
            }
        }
        revert AllocationNotFound();
    }

    /**
     * @dev Internal function to create or update a token allocation (initial allocations)
     * @param beneficiary Address of the beneficiary
     * @param amount Total amount of tokens
     * @param cliffMonths Cliff period in months
     * @param vestingMonths Vesting period in months
     * @param allocationName Name of the allocation
     * @param tgeReleasePercentage TGE release percentage (in basis points, 10000 = 100%)
     * @param bypassTgeRestriction Allow claiming TGE tokens before TGE (for off-chain platforms)
     */
    function _createTokenAllocation(
        address beneficiary,
        uint256 amount,
        uint256 cliffMonths,
        uint256 vestingMonths,
        string memory allocationName,
        uint256 tgeReleasePercentage,
        bool bypassTgeRestriction
    ) internal {
        if (beneficiary == address(0)) revert InvalidBeneficiary();
        if (amount == 0) revert InvalidAmount();
        if (vestingMonths == 0) revert InvalidDuration();
        if (tgeReleasePercentage > 10000) revert InvalidTgeReleasePercentage();

        // Store durations in months (no conversion needed)
        uint256 cliffMonthDuration = cliffMonths;
        uint256 vestingMonthDuration = vestingMonths;

        // Check for existing allocation with same beneficiary and name
        if (tokenAllocationExists[beneficiary][allocationName]) {
            // Update existing allocation
            uint256 index = tokenAllocationIndices[beneficiary][allocationName];
            tokenAllocations[index].totalAmount += amount;
            emit AllocationAdded(
                beneficiary,
                amount,
                cliffMonthDuration,
                vestingMonthDuration,
                allocationName,
                bypassTgeRestriction
            );
            return;
        }

        // Create new allocation
        uint256 newIndex = tokenAllocations.length;
        tokenAllocations.push(
            Allocation({
                totalAmount: amount,
                claimedAmount: 0,
                cliffMonthDuration: cliffMonthDuration,
                vestingMonthDuration: vestingMonthDuration,
                beneficiary: beneficiary,
                allocationName: allocationName,
                tgeReleasePercentage: tgeReleasePercentage,
                lastClaimTimestamp: 0,
                bypassTgeRestriction: bypassTgeRestriction
            })
        );

        // Update mappings
        tokenAllocationIndices[beneficiary][allocationName] = newIndex;
        tokenAllocationExists[beneficiary][allocationName] = true;

        emit AllocationAdded(
            beneficiary,
            amount,
            cliffMonthDuration,
            vestingMonthDuration,
            allocationName,
            bypassTgeRestriction
        );
    }

    /**
     * @dev Internal function to create or update a round allocation (ICO and admin allocations)
     * @param beneficiary Address of the beneficiary
     * @param amount Total amount of tokens
     * @param cliffMonths Cliff period in months
     * @param vestingMonths Vesting period in months
     * @param allocationName Name of the allocation
     * @param tgeReleasePercentage TGE release percentage (in basis points, 10000 = 100%)
     * @param bypassTgeRestriction Allow claiming TGE tokens before TGE (for off-chain platforms)
     */
    function _createRoundAllocation(
        address beneficiary,
        uint256 amount,
        uint256 cliffMonths,
        uint256 vestingMonths,
        string memory allocationName,
        uint256 tgeReleasePercentage,
        bool bypassTgeRestriction
    ) internal {
        if (beneficiary == address(0)) revert InvalidBeneficiary();
        if (amount == 0) revert InvalidAmount();
        if (vestingMonths == 0) revert InvalidDuration();
        if (tgeReleasePercentage > 10000) revert InvalidTgeReleasePercentage();

        // Store durations in months (no conversion needed)
        uint256 cliffMonthDuration = cliffMonths;
        uint256 vestingMonthDuration = vestingMonths;

        // Check for existing allocation with same beneficiary and name
        if (roundAllocationExists[beneficiary][allocationName]) {
            // Update existing allocation
            uint256 index = roundAllocationIndices[beneficiary][allocationName];
            roundAllocations[index].totalAmount += amount;
            emit AllocationAdded(
                beneficiary,
                amount,
                cliffMonthDuration,
                vestingMonthDuration,
                allocationName,
                bypassTgeRestriction
            );
            return;
        }

        // Create new allocation
        uint256 newIndex = roundAllocations.length;
        roundAllocations.push(
            Allocation({
                totalAmount: amount,
                claimedAmount: 0,
                cliffMonthDuration: cliffMonthDuration,
                vestingMonthDuration: vestingMonthDuration,
                beneficiary: beneficiary,
                allocationName: allocationName,
                tgeReleasePercentage: tgeReleasePercentage,
                lastClaimTimestamp: 0,
                bypassTgeRestriction: bypassTgeRestriction
            })
        );

        // Update mappings
        roundAllocationIndices[beneficiary][allocationName] = newIndex;
        roundAllocationExists[beneficiary][allocationName] = true;

        emit AllocationAdded(
            beneficiary,
            amount,
            cliffMonthDuration,
            vestingMonthDuration,
            allocationName,
            bypassTgeRestriction
        );
    }

    /**
     * @dev Calculates claimable tokens for an allocation
     * @param allocationIndex Index of the allocation
     * @param isRoundAllocation Whether this is a round allocation (true) or token allocation (false)
     * @return Amount of tokens that can be claimed
     */
    function getClaimableAmount(
        uint256 allocationIndex,
        bool isRoundAllocation
    ) public view returns (uint256) {
        Allocation memory allocation = isRoundAllocation
            ? roundAllocations[allocationIndex]
            : tokenAllocations[allocationIndex];

        // If no tokens are allocated or all tokens are claimed, return 0
        if (
            allocation.totalAmount == 0 ||
            allocation.claimedAmount >= allocation.totalAmount
        ) {
            return 0;
        }

        // Calculate TGE release amount
        uint256 tgeReleaseAmount = (allocation.totalAmount *
            allocation.tgeReleasePercentage) / 10000;
        uint256 vestingAmount = allocation.totalAmount - tgeReleaseAmount;

        // Check if TGE tokens can be claimed
        bool canClaimTge = false;
        if (!tgeTimestampSet) {
            // If TGE timestamp is not set, no tokens can be claimed
            canClaimTge = false;
        } else if (allocation.bypassTgeRestriction) {
            // Admin allocations with bypass can claim TGE tokens anytime after TGE is set
            canClaimTge = true;
        } else {
            // Normal allocations can only claim TGE tokens after TGE timestamp
            canClaimTge = block.timestamp >= tgeTimestamp;
        }

        // If TGE is not yet claimable and no bypass, no tokens are claimable
        if (!canClaimTge) {
            return 0;
        }

        // Calculate actual start time by adding TGE timestamp to cliff duration (convert months to seconds)
        uint256 actualStartTime = tgeTimestamp +
            (allocation.cliffMonthDuration * 30 days);

        // If cliff is not yet reached, only TGE release is claimable
        if (block.timestamp < actualStartTime) {
            // If TGE has not been claimed yet, claim TGE
            if (allocation.lastClaimTimestamp == 0) {
                return tgeReleaseAmount;
            }
            // If TGE has already been claimed, no tokens are claimable
            return 0;
        }

        // Calculate monthly vesting
        uint256 totalClaimableAmount;
        uint256 vestingMonths = allocation.vestingMonthDuration;

        // Calculate months since cliff
        uint256 timeSinceCliff = block.timestamp - actualStartTime;
        uint256 fullMonthsPassed = timeSinceCliff / (30 days);

        // Handle different vesting scenarios
        if (vestingMonths == 0) {
            // 0 month vesting: all tokens available immediately after cliff
            totalClaimableAmount = allocation.totalAmount;
        } else if (fullMonthsPassed >= vestingMonths) {
            // Vesting period completed: all tokens available
            totalClaimableAmount = allocation.totalAmount;
        } else {
            // Calculate vested amount based on months passed
            uint256 monthsIncludingCurrent = fullMonthsPassed;
            totalClaimableAmount =
                tgeReleaseAmount +
                (vestingAmount * monthsIncludingCurrent) /
                vestingMonths;
        }

        // Calculate claimable amount (actual total - already claimed)
        if (allocation.claimedAmount >= totalClaimableAmount) {
            return 0;
        }

        return totalClaimableAmount - allocation.claimedAmount;
    }

    /**
     * @dev Gets all token allocations for a beneficiary
     * @param beneficiary Address of the beneficiary
     * @return Array of allocation indices
     */
    function getTokenAllocationsForBeneficiary(
        address beneficiary
    ) external view returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < tokenAllocations.length; i++) {
            if (tokenAllocations[i].beneficiary == beneficiary) {
                count++;
            }
        }

        uint256[] memory beneficiaryAllocations = new uint256[](count);
        uint256 currentIndex = 0;
        for (uint256 i = 0; i < tokenAllocations.length; i++) {
            if (tokenAllocations[i].beneficiary == beneficiary) {
                beneficiaryAllocations[currentIndex] = i;
                currentIndex++;
            }
        }

        return beneficiaryAllocations;
    }

    /**
     * @dev Gets all round allocations for a beneficiary
     * @param beneficiary Address of the beneficiary
     * @return Array of allocation indices
     */
    function getRoundAllocationsForBeneficiary(
        address beneficiary
    ) external view returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < roundAllocations.length; i++) {
            if (roundAllocations[i].beneficiary == beneficiary) {
                count++;
            }
        }

        uint256[] memory beneficiaryAllocations = new uint256[](count);
        uint256 currentIndex = 0;
        for (uint256 i = 0; i < roundAllocations.length; i++) {
            if (roundAllocations[i].beneficiary == beneficiary) {
                beneficiaryAllocations[currentIndex] = i;
                currentIndex++;
            }
        }

        return beneficiaryAllocations;
    }

    /**
     * @dev Gets token allocation index for a specific beneficiary and allocation name
     * @param beneficiary Address of the beneficiary
     * @param allocationName Name of the allocation
     * @return allocationIndex Index of the allocation (returns type(uint256).max if not found)
     */
    function getTokenAllocationIndex(
        address beneficiary,
        string memory allocationName
    ) external view returns (uint256) {
        for (uint256 i = 0; i < tokenAllocations.length; i++) {
            if (
                tokenAllocations[i].beneficiary == beneficiary &&
                keccak256(bytes(tokenAllocations[i].allocationName)) ==
                keccak256(bytes(allocationName))
            ) {
                return i;
            }
        }
        return type(uint256).max; // Not found
    }

    /**
     * @dev Gets round allocation index for a specific beneficiary and allocation name
     * @param beneficiary Address of the beneficiary
     * @param allocationName Name of the allocation
     * @return allocationIndex Index of the allocation (returns type(uint256).max if not found)
     */
    function getRoundAllocationIndex(
        address beneficiary,
        string memory allocationName
    ) external view returns (uint256) {
        for (uint256 i = 0; i < roundAllocations.length; i++) {
            if (
                roundAllocations[i].beneficiary == beneficiary &&
                keccak256(bytes(roundAllocations[i].allocationName)) ==
                keccak256(bytes(allocationName))
            ) {
                return i;
            }
        }
        return type(uint256).max; // Not found
    }

    /**
     * @dev Gets total number of token allocations
     * @return Total number of token allocations in the contract
     */
    function getTokenAllocationsCount() external view returns (uint256) {
        return tokenAllocations.length;
    }

    /**
     * @dev Gets total number of round allocations
     * @return Total number of round allocations in the contract
     */
    function getRoundAllocationsCount() external view returns (uint256) {
        return roundAllocations.length;
    }

    /**
     * @dev Gets the total tokens sold in ICO rounds
     * @return Total tokens sold
     */
    function getTotalTokensSold() external view returns (uint256) {
        return totalTokensSold;
    }

    /**
     * @dev Gets the total unsold tokens
     * @return Total unsold tokens
     */
    function getUnsoldTokens() external view returns (uint256) {
        return TOTAL_ICO_TOKENS - totalTokensSold;
    }

    /**
     * @dev Checks if unsold tokens have been distributed
     * @return True if unsold tokens have been distributed
     */
    function isUnsoldTokensDistributed() external view returns (bool) {
        return unsoldTokensDistributed;
    }

    /**
     * @dev Gets the sales performance percentage
     * @return Sales performance as a percentage (0-100)
     */
    function getSalesPerformance() external view returns (uint256) {
        return (totalTokensSold * 100) / TOTAL_ICO_TOKENS;
    }

    /**
     * @dev Gets the total amount from all admin allocations (off-chain sales)
     * This should equal totalTokensSold and represents actual tokens sold
     * @return Total amount from admin allocations
     */
    function getTotalSalesAllocations() external view returns (uint256) {
        return totalTokensSold;
    }

    /**
     * @dev Gets the total tokens burned due to vesting haircuts
     * @return Total tokens burned
     */
    function getTotalTokensBurned() external view returns (uint256) {
        return totalTokensBurned;
    }

    /**
     * @dev Gets the tokens sold in Seed round
     * @return Tokens sold in Seed round
     */
    function getSeedTokensSold() external view returns (uint256) {
        return seedTokensSold;
    }

    /**
     * @dev Gets the tokens sold in Private Sale round
     * @return Tokens sold in Private Sale round
     */
    function getPrivateSaleTokensSold() external view returns (uint256) {
        return privateSaleTokensSold;
    }

    /**
     * @dev Gets the tokens sold in Public Sale round
     * @return Tokens sold in Public Sale round
     */
    function getPublicSaleTokensSold() external view returns (uint256) {
        return publicSaleTokensSold;
    }

    /**
     * @dev Checks if TGE timestamp has been set
     * @return True if TGE timestamp has been set
     */
    function isTgeTimestampSet() external view returns (bool) {
        return tgeTimestampSet;
    }

    /**
     * @dev Checks if a token allocation has TGE bypass enabled
     * @param allocationIndex Index of the allocation
     * @return True if allocation can bypass TGE restrictions
     */
    function hasTokenTgeBypass(
        uint256 allocationIndex
    ) external view returns (bool) {
        if (allocationIndex >= tokenAllocations.length) {
            return false;
        }
        return tokenAllocations[allocationIndex].bypassTgeRestriction;
    }

    /**
     * @dev Checks if a round allocation has TGE bypass enabled
     * @param allocationIndex Index of the allocation
     * @return True if allocation can bypass TGE restrictions
     */
    function hasRoundTgeBypass(
        uint256 allocationIndex
    ) external view returns (bool) {
        if (allocationIndex >= roundAllocations.length) {
            return false;
        }
        return roundAllocations[allocationIndex].bypassTgeRestriction;
    }

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
    function getTokenAllocationDetails(
        uint256 allocationIndex
    )
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
        )
    {
        if (allocationIndex >= tokenAllocations.length) {
            return (0, 0, 0, 0, address(0), "", 0, 0, false);
        }

        Allocation memory allocation = tokenAllocations[allocationIndex];
        return (
            allocation.totalAmount,
            allocation.claimedAmount,
            allocation.cliffMonthDuration,
            allocation.vestingMonthDuration,
            allocation.beneficiary,
            allocation.allocationName,
            allocation.tgeReleasePercentage,
            allocation.lastClaimTimestamp,
            allocation.bypassTgeRestriction
        );
    }

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
    function getRoundAllocationDetails(
        uint256 allocationIndex
    )
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
        )
    {
        if (allocationIndex >= roundAllocations.length) {
            return (0, 0, 0, 0, address(0), "", 0, 0, false);
        }

        Allocation memory allocation = roundAllocations[allocationIndex];
        return (
            allocation.totalAmount,
            allocation.claimedAmount,
            allocation.cliffMonthDuration,
            allocation.vestingMonthDuration,
            allocation.beneficiary,
            allocation.allocationName,
            allocation.tgeReleasePercentage,
            allocation.lastClaimTimestamp,
            allocation.bypassTgeRestriction
        );
    }

    /**
     * @dev Gets haircut information for a specific token allocation at current time
     * @param allocationIndex Index of the allocation
     * @return haircutPercentage Current haircut percentage (in basis points)
     * @return monthsPassed Months passed since TGE
     */
    function getTokenHaircutInfo(
        uint256 allocationIndex
    ) external view returns (uint256 haircutPercentage, uint256 monthsPassed) {
        if (allocationIndex >= tokenAllocations.length) {
            return (0, 0);
        }

        Allocation memory allocation = tokenAllocations[allocationIndex];

        monthsPassed = 0;
        if (tgeTimestampSet && block.timestamp >= tgeTimestamp) {
            monthsPassed = (block.timestamp - tgeTimestamp) / 30 days;
        }

        haircutPercentage = calculateHaircutPercentage(
            allocation.allocationName,
            monthsPassed
        );
    }

    /**
     * @dev Gets haircut information for a specific round allocation at current time
     * @param allocationIndex Index of the allocation
     * @return haircutPercentage Current haircut percentage (in basis points)
     * @return monthsPassed Months passed since TGE
     */
    function getRoundHaircutInfo(
        uint256 allocationIndex
    ) external view returns (uint256 haircutPercentage, uint256 monthsPassed) {
        if (allocationIndex >= roundAllocations.length) {
            return (0, 0);
        }

        Allocation memory allocation = roundAllocations[allocationIndex];

        monthsPassed = 0;
        if (tgeTimestampSet && block.timestamp >= tgeTimestamp) {
            monthsPassed = (block.timestamp - tgeTimestamp) / 30 days;
        }

        haircutPercentage = calculateHaircutPercentage(
            allocation.allocationName,
            monthsPassed
        );
    }

    /**
     * @dev Gets the actual start time for a token allocation (TGE + cliff duration)
     * @param allocationIndex Index of the allocation
     * @return actualStartTime The actual start time when vesting begins
     */
    function getTokenActualStartTime(
        uint256 allocationIndex
    ) external view returns (uint256 actualStartTime) {
        if (allocationIndex >= tokenAllocations.length) {
            return 0;
        }

        if (!tgeTimestampSet) {
            return 0;
        }

        Allocation memory allocation = tokenAllocations[allocationIndex];
        return tgeTimestamp + (allocation.cliffMonthDuration * 30 days);
    }

    /**
     * @dev Gets the actual start time for a round allocation (TGE + cliff duration)
     * @param allocationIndex Index of the allocation
     * @return actualStartTime The actual start time when vesting begins
     */
    function getRoundActualStartTime(
        uint256 allocationIndex
    ) external view returns (uint256 actualStartTime) {
        if (allocationIndex >= roundAllocations.length) {
            return 0;
        }

        if (!tgeTimestampSet) {
            return 0;
        }

        Allocation memory allocation = roundAllocations[allocationIndex];
        return tgeTimestamp + (allocation.cliffMonthDuration * 30 days);
    }

    /**
     * @dev Simulates normal token claim for token allocation (vested tokens only, no haircut)
     * @param allocationIndex Index of the allocation
     * @return claimableAmount Amount that can be claimed through normal vesting
     */
    function simulateTokenClaim(
        uint256 allocationIndex
    ) external view returns (uint256 claimableAmount) {
        if (allocationIndex >= tokenAllocations.length) {
            return 0;
        }

        claimableAmount = getClaimableAmount(allocationIndex, false);
    }

    /**
     * @dev Simulates normal token claim for round allocation (vested tokens only, no haircut)
     * @param allocationIndex Index of the allocation
     * @return claimableAmount Amount that can be claimed through normal vesting
     */
    function simulateRoundClaim(
        uint256 allocationIndex
    ) external view returns (uint256 claimableAmount) {
        if (allocationIndex >= roundAllocations.length) {
            return 0;
        }

        claimableAmount = getClaimableAmount(allocationIndex, true);
    }
}
