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

    Melies public meliesToken;
    uint256 public immutable tgeTimestamp;

    struct Allocation {
        uint256 totalAmount;
        uint256 claimedAmount;
        uint256 startTime;
        uint256 duration;
        address beneficiary;
        string allocationName;
        uint256 tgeReleasePercentage;
        uint256 lastClaimTimestamp;
    }

    Allocation[] public allocations;

    // Events
    event AllocationAdded(
        address indexed beneficiary,
        uint256 amount,
        uint256 startTime,
        uint256 duration,
        string allocationName
    );
    event TokensClaimed(
        address indexed beneficiary,
        uint256 amount,
        string allocationName
    );

    // Errors
    error InvalidBeneficiary();
    error InvalidAmount();
    error InvalidStartTime();
    error InvalidDuration();
    error NoTokensAvailable();
    error AllocationAlreadyExists();
    error InvalidTgeReleasePercentage();

    /**
     * @dev Constructor
     * @param _meliesToken Address of the Melies token contract
     * @param _tgeTimestamp TGE timestamp
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
        uint256 _tgeTimestamp,
        address admin,
        address communityAddress,
        address treasuryAddress,
        address partnersAddress,
        address teamAddress,
        address liquidityAddress,
        address aiSystemsAddress
    ) {
        meliesToken = Melies(_meliesToken);
        tgeTimestamp = _tgeTimestamp;

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
     * @dev Claims tokens for a specific allocation
     * @param allocationIndex Index of the allocation
     */
    function claimTokens(uint256 allocationIndex) external nonReentrant {
        Allocation storage allocation = allocations[allocationIndex];

        if (allocation.beneficiary != msg.sender) revert InvalidBeneficiary();

        uint256 claimableAmount = getClaimableAmount(allocationIndex);
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
        addAllocation(communityAddress, 200_000_000e8, 0, 48, "Community", 208);

        // Treasury: 100M tokens, no cliff, 48 months vesting, 5.00% TGE
        addAllocation(treasuryAddress, 100_000_000e8, 0, 48, "Treasury", 500);

        // Partners & Advisors: 100M tokens, no cliff, 18 months vesting, 10.00% TGE
        addAllocation(partnersAddress, 100_000_000e8, 0, 18, "Partners", 1000);

        // Team: 100M tokens, 12 months cliff, 20 months vesting, 0.00% TGE
        addAllocation(teamAddress, 100_000_000e8, 12, 20, "Team", 0);

        // Liquidity: 100M tokens, available at TGE, 100.00% TGE
        addAllocation(
            liquidityAddress,
            100_000_000e8,
            0,
            1,
            "Liquidity",
            10000
        );

        // AI Systems: 100M tokens, no cliff, 18 months vesting, 10.00% TGE
        addAllocation(
            aiSystemsAddress,
            100_000_000e8,
            0,
            18,
            "AI Systems",
            1000
        );
    }

    /**
     * @dev Adds a new allocation
     * @param beneficiary Address of the beneficiary
     * @param amount Total amount of tokens
     * @param cliffMonths Cliff period in months
     * @param vestingMonths Vesting period in months
     * @param allocationName Name of the allocation
     * @param tgeReleasePercentage TGE release percentage
     */
    function addAllocation(
        address beneficiary,
        uint256 amount,
        uint256 cliffMonths,
        uint256 vestingMonths,
        string memory allocationName,
        uint256 tgeReleasePercentage
    ) internal {
        if (beneficiary == address(0)) revert InvalidBeneficiary();
        if (amount == 0) revert InvalidAmount();
        if (vestingMonths == 0) revert InvalidDuration();
        if (tgeReleasePercentage > 10000) revert InvalidTgeReleasePercentage();

        // Check for existing allocation with same beneficiary and name
        for (uint i = 0; i < allocations.length; i++) {
            if (
                allocations[i].beneficiary == beneficiary &&
                keccak256(bytes(allocations[i].allocationName)) ==
                keccak256(bytes(allocationName))
            ) {
                revert AllocationAlreadyExists();
            }
        }

        uint256 startTime = tgeTimestamp + (cliffMonths * 30 days);
        uint256 duration = vestingMonths * 30 days;

        allocations.push(
            Allocation({
                totalAmount: amount,
                claimedAmount: 0,
                startTime: startTime,
                duration: duration,
                beneficiary: beneficiary,
                allocationName: allocationName,
                tgeReleasePercentage: tgeReleasePercentage,
                lastClaimTimestamp: 0
            })
        );

        emit AllocationAdded(
            beneficiary,
            amount * 1e8,
            startTime,
            duration,
            allocationName
        );
    }

    /**
     * @dev Calculates claimable tokens for an allocation
     * @param allocationIndex Index of the allocation
     * @return Amount of tokens that can be claimed
     */
    function getClaimableAmount(
        uint256 allocationIndex
    ) public view returns (uint256) {
        Allocation memory allocation = allocations[allocationIndex];

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

        // If TGE is not yet reached, no tokens are claimable
        if (block.timestamp < tgeTimestamp) {
            return 0;
        }

        // If cliff is not yet reached, only TGE release is claimable
        if (block.timestamp < allocation.startTime) {
            // If TGE has not been claimed yet, claim TGE
            if (allocation.lastClaimTimestamp == 0) {
                return tgeReleaseAmount;
            }
            // If TGE has already been claimed, no tokens are claimable
            return 0;
        }

        // Calculate monthly vesting
        uint256 totalClaimableAmount;
        uint256 vestingMonths = allocation.duration / 30 days;

        // Calculate months since cliff
        uint256 timeSinceCliff = block.timestamp - allocation.startTime;
        uint256 fullMonthsPassed = 1 + (timeSinceCliff / 30 days);

        if (vestingMonths == 0) {
            vestingMonths = 1;
        }

        if (fullMonthsPassed >= vestingMonths) {
            totalClaimableAmount = allocation.totalAmount;
        } else {
            totalClaimableAmount =
                tgeReleaseAmount +
                (vestingAmount * fullMonthsPassed) /
                vestingMonths;
        }

        // Calculate claimable amount (actual total - already claimed)
        if (allocation.claimedAmount >= totalClaimableAmount) {
            return 0;
        }

        return totalClaimableAmount - allocation.claimedAmount;
    }

    /**
     * @dev Gets all allocations for a beneficiary
     * @param beneficiary Address of the beneficiary
     * @return Array of allocation indices
     */
    function getAllocationsForBeneficiary(
        address beneficiary
    ) external view returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < allocations.length; i++) {
            if (allocations[i].beneficiary == beneficiary) {
                count++;
            }
        }

        uint256[] memory beneficiaryAllocations = new uint256[](count);
        uint256 currentIndex = 0;
        for (uint256 i = 0; i < allocations.length; i++) {
            if (allocations[i].beneficiary == beneficiary) {
                beneficiaryAllocations[currentIndex] = i;
                currentIndex++;
            }
        }

        return beneficiaryAllocations;
    }
}
