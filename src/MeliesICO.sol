// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@chainlink/contracts/src/interfaces/feeds/AggregatorV3Interface.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "./Melies.sol";
import "./interfaces/IMeliesICO.sol";

/**
 * @title MeliesICO
 * @dev Manages the Initial Coin Offering (ICO) for the Melies token.
 * Implements multiple sale rounds, token purchase with ETH and USDC, vesting schedules,
 * and admin functions for ICO management.
 */
contract MeliesICO is IMeliesICO, ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    Melies public meliesToken;
    IERC20 public usdcToken;
    IERC20 public usdtToken;
    IUniswapV2Router02 public uniswapRouter;
    AggregatorV3Interface public ethUsdPriceFeed;

    uint256 public slippageTolerance = 0; // 0.5% by default
    uint256 public constant SLIPPAGE_DENOMINATOR = 10_000;

    uint8 public constant PRICE_DECIMALS = 6;
    uint8 public constant USDC_DECIMALS = 6;

    uint256 public tgeTimestamp;

    SaleRound[] public saleRounds;
    mapping(address => mapping(uint256 => Allocation)) public allocations;
    mapping(uint256 => mapping(address => bool)) public whitelist;

    uint256 public totalUsdcRaised;
    bool public icoEnded;
    bool public claimEnabled;

    /**
     * @dev Constructor to initialize the MeliesICO contract
     * @param _meliesToken Address of the Melies token contract
     * @param _usdcToken Address of the USDC token contract
     * @param _usdtToken Address of the USDT token contract
     * @param _uniswapRouter Address of the Uniswap V2 Router
     * @param _ethUsdPriceFeed Address of the Chainlink ETH/USD price feed
     * @param _tgeTimestamp Timestamp for the Token Generation Event (TGE)
     */
    constructor(
        address _meliesToken,
        address _usdcToken,
        address _usdtToken,
        address _uniswapRouter,
        address _ethUsdPriceFeed,
        uint256 _tgeTimestamp
    ) {
        meliesToken = Melies(_meliesToken);
        usdcToken = IERC20(_usdcToken);
        usdtToken = IERC20(_usdtToken);
        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
        ethUsdPriceFeed = AggregatorV3Interface(_ethUsdPriceFeed);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);

        tgeTimestamp = _tgeTimestamp;
    }

    /**
     * @dev Updates the slippage tolerance for ETH to USDC swaps
     * @param _newSlippageTolerance New slippage tolerance value (max 10%)
     */
    function updateSlippageTolerance(
        uint256 _newSlippageTolerance
    ) external onlyRole(ADMIN_ROLE) {
        if (_newSlippageTolerance > 1000) revert SlippageToleranceTooHigh();
        slippageTolerance = _newSlippageTolerance;
        emit SlippageToleranceUpdated(_newSlippageTolerance);
    }

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
    ) external onlyRole(ADMIN_ROLE) {
        if (_startTime >= _endTime) revert InvalidTimeRange();
        if (_tokenPrice == 0) revert InvalidTokenPrice();
        if (_maxCap == 0 || _softCap == 0 || _softCap > _maxCap)
            revert InvalidCap();
        if (_minPurchase > _maxPurchase) revert InvalidPurchaseLimits();
        if (_vestingDuration != 0 && _vestingDuration < 30)
            revert InvalidVestingDuration();
        if (_tgeReleasePercentage > 100) revert InvalidTgeReleasePercentage();

        saleRounds.push(
            SaleRound({
                startTime: _startTime,
                endTime: _endTime,
                tokenPrice: _tokenPrice,
                maxCap: _maxCap,
                softCap: _softCap,
                minPurchase: _minPurchase,
                maxPurchase: _maxPurchase,
                totalRaised: 0,
                isFinish: false,
                cliffDuration: _cliffDuration,
                vestingDuration: _vestingDuration,
                tgeReleasePercentage: _tgeReleasePercentage,
                lockDuration: _lockDuration
            })
        );
    }

    /**
     * @dev Adds addresses to the whitelist for a specific round
     * @param _roundId ID of the sale round
     * @param _addresses Addresses to be added to the whitelist
     */
    function addToWhitelist(
        uint256 _roundId,
        address[] calldata _addresses
    ) external onlyRole(ADMIN_ROLE) {
        for (uint256 i = 0; i < _addresses.length; i++) {
            whitelist[_roundId][_addresses[i]] = true;
        }
        emit AddedToWhitelist(_roundId, _addresses);
    }

    /**
     * @dev Removes addresses from the whitelist for a specific round
     * @param _roundId ID of the sale round
     * @param _addresses Addresses to be removed from the whitelist
     */
    function removeFromWhitelist(
        uint256 _roundId,
        address[] calldata _addresses
    ) external onlyRole(ADMIN_ROLE) {
        for (uint256 i = 0; i < _addresses.length; i++) {
            whitelist[_roundId][_addresses[i]] = false;
        }
        emit RemovedFromWhitelist(_roundId, _addresses);
    }

    /**
     * @dev Fallback function to handle direct ETH transfers
     */
    receive() external payable nonReentrant {
        _buyWithEth();
    }

    /**
     * @dev Allows users to buy tokens with ETH
     */
    function buyWithEth() external payable nonReentrant {
        _buyWithEth();
    }

    /**
     * @dev Internal function to process ETH to token purchases
     */
    function _buyWithEth() internal {
        if (msg.value == 0) revert NoEthSent();

        uint256 ethUsdPrice = getEthUsdPrice();
        uint256 expectedUsdcAmount = (msg.value * 10 ** USDC_DECIMALS) /
            ethUsdPrice;

        uint256 minUsdcAmount = (expectedUsdcAmount *
            (SLIPPAGE_DENOMINATOR - slippageTolerance)) / SLIPPAGE_DENOMINATOR;

        address[] memory path = new address[](2);
        path[0] = uniswapRouter.WETH();
        path[1] = address(usdcToken);

        uint256[] memory amounts = uniswapRouter.swapExactETHForTokens{
            value: msg.value
        }(minUsdcAmount, path, address(this), block.timestamp + 15 minutes);

        _processPurchase(msg.sender, amounts[1]);
    }

    /**
     * @dev Internal function to process token purchases
     * @param buyer Address of the token buyer
     * @param usdcAmount Amount of USDC spent on the purchase
     * @return tokenAmount Amount of tokens purchased
     */
    function _processPurchase(
        address buyer,
        uint256 usdcAmount
    ) internal returns (uint256) {
        if (icoEnded) revert IcoAlreadyEnded();
        uint256 currentRoundId = getCurrentRoundId();
        SaleRound storage round = saleRounds[currentRoundId];

        if (!whitelist[currentRoundId][buyer]) revert NotWhitelisted();

        if (usdcAmount < round.minPurchase) revert BelowMinimumPurchase();
        if (usdcAmount > round.maxPurchase) revert ExceedsMaximumPurchase();
        if (round.totalRaised + usdcAmount > round.maxCap)
            revert RoundCapExceeded();

        //PRICE_DECIMALS cancels out with USDC_DECIMALS (6-6)
        uint256 tokenAmount = (usdcAmount * 10 ** meliesToken.decimals()) /
            round.tokenPrice;

        _addAllocation(
            buyer,
            tokenAmount,
            usdcAmount,
            round.cliffDuration,
            round.vestingDuration,
            currentRoundId
        );

        round.totalRaised += usdcAmount;
        totalUsdcRaised += usdcAmount;

        emit TokensPurchased(buyer, usdcAmount, tokenAmount);

        return tokenAmount;
    }

    /**
     * @dev Allows users to buy tokens with USDC
     * @param amount Amount of USDC to spend on token purchase
     */
    function buyWithUsdc(uint256 amount) external nonReentrant {
        if (amount == 0) revert NoTokensSent();

        usdcToken.safeTransferFrom(msg.sender, address(this), amount);

        _processPurchase(msg.sender, amount);
    }

    /**
     * @dev Allows admins to add purchases made with fiat currency
     * @param buyer Address of the token buyer
     * @param usdcAmount Amount of USDC equivalent purchased
     */
    function addFiatPurchase(
        address buyer,
        uint256 usdcAmount
    ) external onlyRole(ADMIN_ROLE) {
        if (usdcAmount == 0) revert NoTokensSent();

        _processPurchase(buyer, usdcAmount);
    }

    /**
     * @dev Internal function to add token allocation for a buyer
     * @param _beneficiary Address of the token beneficiary
     * @param _tokenAmount Amount of tokens allocated
     * @param _usdcAmount Amount of USDC spent
     * @param _cliffDuration Duration of the cliff period
     * @param _vestingDuration Total duration of the vesting period
     * @param _roundId ID of the sale round
     */
    function _addAllocation(
        address _beneficiary,
        uint256 _tokenAmount,
        uint256 _usdcAmount,
        uint256 _cliffDuration,
        uint256 _vestingDuration,
        uint256 _roundId
    ) internal {
        if (_beneficiary == address(0)) revert InvalidBeneficiaryAddress();
        if (_tokenAmount == 0) revert TokenAmountMustBeGreaterThanZero();
        if (_usdcAmount == 0) revert UsdcAmountMustBeGreaterThanZero();

        Allocation storage allocation = allocations[_beneficiary][_roundId];

        if (allocation.totalTokenAmount == 0) {
            allocation.cliffDuration = _cliffDuration;
            allocation.vestingDuration = _vestingDuration;
        }

        allocation.totalTokenAmount += _tokenAmount;
        allocation.totalUsdcAmount += _usdcAmount;

        emit AllocationAdded(
            _beneficiary,
            _tokenAmount,
            tgeTimestamp,
            _cliffDuration,
            _vestingDuration,
            _roundId
        );
    }

    /**
     * @dev Allows users to claim their tokens
     */
    function claimTokens() external nonReentrant {
        if (!icoEnded) revert IcoNotEndedYet();
        if (!claimEnabled) revert ClaimingNotEnabled();

        uint256 totalClaimableAmount = 0;
        uint256 totalUnlockedAmount = 0;
        for (uint256 i = 0; i < saleRounds.length; i++) {
            Allocation storage allocation = allocations[msg.sender][i];
            SaleRound storage round = saleRounds[i];
            if (allocation.totalTokenAmount > 0) {
                (
                    uint256 claimableAmount,
                    uint256 tgeReleaseAmount,
                    uint256 newLastClaimTimestamp
                ) = getClaimableAmount(msg.sender, i);
                if (claimableAmount > 0) {
                    allocation.claimedAmount += claimableAmount;
                    allocation.lastClaimTimestamp = newLastClaimTimestamp;
                    totalClaimableAmount += claimableAmount;

                    // Calculate remaining lock time for TGE release amount
                    uint256 currentTime = block.timestamp;
                    // currentTime is always greater than tgeTimestamp (else claimableAmount would be 0)
                    uint256 elapsedTime = currentTime - tgeTimestamp;
                    uint256 remainingLockTime = elapsedTime >=
                        round.lockDuration
                        ? 0
                        : round.lockDuration - elapsedTime;

                    // Mint TGE release amount with remaining lock time
                    if (tgeReleaseAmount > 0) {
                        if (remainingLockTime > 0) {
                            meliesToken.mintLocked(
                                msg.sender,
                                tgeReleaseAmount,
                                remainingLockTime
                            );
                        } else {
                            totalUnlockedAmount += tgeReleaseAmount;
                        }
                    }

                    // Add vesting amount to unlocked amount
                    totalUnlockedAmount += (claimableAmount - tgeReleaseAmount);
                }
            }
        }

        if (totalClaimableAmount == 0) revert NoTokensAvailableToClaim();

        if (totalUnlockedAmount > 0) {
            meliesToken.mint(msg.sender, totalUnlockedAmount);
        }

        emit TokensClaimed(msg.sender, totalClaimableAmount);
    }

    /**
     * @dev Allows admins to withdraw raised USDC after ICO ends
     */
    function withdrawUsdc() external onlyRole(ADMIN_ROLE) {
        if (!icoEnded) revert IcoNotEndedYet();

        uint256 amount = usdcToken.balanceOf(address(this));

        usdcToken.safeTransfer(msg.sender, amount);
        emit UsdcWithdrawn(msg.sender, amount);
    }

    /**
     * @dev Allows admins to withdraw any ETH in the contract after ICO ends
     */
    function withdrawEth() external onlyRole(ADMIN_ROLE) {
        if (!icoEnded) revert IcoNotEndedYet();

        uint256 amount = address(this).balance;
        if (amount == 0) revert NoEthToWithdraw();
        (bool success, ) = msg.sender.call{value: amount}("");
        if (!success) revert EthTransferFailed();
        emit EthWithdrawn(msg.sender, amount);
    }

    /**
     * @dev Allows users to request a refund if ICO ends without enabling claims
     */
    function refund() external nonReentrant {
        if (!icoEnded) revert IcoNotEndedYet();
        if (claimEnabled) revert RefundNotAvailable();
        uint256 totalRefundAmount = 0;

        for (uint256 i = 0; i < saleRounds.length; i++) {
            SaleRound storage round = saleRounds[i];
            if (round.isFinish && round.totalRaised < round.softCap) {
                Allocation storage allocation = allocations[msg.sender][i];
                if (allocation.totalUsdcAmount > 0) {
                    totalRefundAmount += allocation.totalUsdcAmount;
                    allocation.totalUsdcAmount = 0;
                    allocation.totalTokenAmount = 0;
                }
            }
        }

        if (totalRefundAmount == 0) revert NoAllocationToRefund();
        usdcToken.safeTransfer(msg.sender, totalRefundAmount);

        emit Refunded(msg.sender, totalRefundAmount);
    }

    /**
     * @dev Allows admins to end the ICO
     */
    function endIco() external onlyRole(ADMIN_ROLE) {
        if (icoEnded) revert IcoAlreadyEnded();
        icoEnded = true;

        bool allRoundsSoftCapReached = true;
        for (uint256 i = 0; i < saleRounds.length; i++) {
            SaleRound storage round = saleRounds[i];
            if (!round.isFinish) {
                round.isFinish = true;
                if (round.totalRaised < round.softCap) {
                    allRoundsSoftCapReached = false;
                    emit RefundsAvailableForRound(i);
                }
            }
        }

        claimEnabled = allRoundsSoftCapReached;
        emit IcoEnded(claimEnabled);
    }

    /**
     * @dev Allows admins to recover any ERC20 tokens accidentally sent to the contract
     * @param _token Address of the ERC20 token to recover
     * @param _amount Amount of tokens to recover
     */
    function recoverTokens(
        address _token,
        uint256 _amount
    ) external onlyRole(ADMIN_ROLE) {
        if (_token == address(meliesToken)) revert CannotRecoverMeliesTokens();
        if (_token == address(usdcToken)) revert CannotRecoverUsdcTokens();

        IERC20 token = IERC20(_token);
        uint256 balance = token.balanceOf(address(this));
        if (_amount > balance) revert InsufficientTokenBalance();

        token.safeTransfer(msg.sender, _amount);
        emit TokensRecovered(_token, msg.sender, _amount);
    }

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
        public
        view
        returns (
            uint256 claimableAmount,
            uint256 tgeReleaseAmount,
            uint256 newLastClaimTimestamp
        )
    {
        Allocation memory allocation = allocations[_beneficiary][_roundId];

        // If no tokens are allocated, no tokens are claimable
        if (allocation.totalTokenAmount == 0) {
            return (0, 0, 0);
        }

        // If all tokens are claimed, no tokens are claimable
        if (allocation.claimedAmount == allocation.totalTokenAmount) {
            return (0, 0, 0);
        }

        SaleRound memory round = saleRounds[_roundId];

        // Calculate TGE release amount
        tgeReleaseAmount =
            (allocation.totalTokenAmount * round.tgeReleasePercentage) /
            100;

        // Calculate vesting amount
        uint256 vestingAmount = allocation.totalTokenAmount - tgeReleaseAmount;

        // If TGE is not yet reached, no tokens are claimable
        if (block.timestamp < tgeTimestamp) {
            return (0, 0, 0);
        }

        // If cliff is not yet reached, only TGE release is claimable
        if (block.timestamp < tgeTimestamp + allocation.cliffDuration) {
            // If TGE has not been claimed yet, claim TGE
            if (allocation.lastClaimTimestamp == 0) {
                return (tgeReleaseAmount, tgeReleaseAmount, block.timestamp);
            }
            // If TGE has already been claimed, no tokens are claimable
            return (0, 0, 0);
        }

        // Calculate monthly vesting months
        uint256 vestingMonths = allocation.vestingDuration / 30 days;
        if (vestingMonths == 0) vestingMonths = 1;

        // Calculate months since cliff
        uint256 timeSinceCliff = block.timestamp -
            (tgeTimestamp + allocation.cliffDuration);
        uint256 fullMonthsPassed = 1 + (timeSinceCliff / 30 days);

        uint256 totalClaimableAmount;
        if (fullMonthsPassed > vestingMonths) {
            totalClaimableAmount = allocation.totalTokenAmount;
        } else {
            totalClaimableAmount =
                tgeReleaseAmount +
                (vestingAmount * fullMonthsPassed) /
                vestingMonths;
        }

        // Calculate claimable amount (actual total - already claimed)
        if (allocation.claimedAmount > totalClaimableAmount) {
            claimableAmount = 0;
        } else {
            claimableAmount = totalClaimableAmount - allocation.claimedAmount;
        }

        // TGE tokens are claimable only once
        if (allocation.lastClaimTimestamp != 0) {
            tgeReleaseAmount = 0;
        }

        // If no tokens are claimable, return 0
        if (claimableAmount == 0) {
            return (0, 0, 0);
        }

        newLastClaimTimestamp = block.timestamp;

        return (claimableAmount, tgeReleaseAmount, newLastClaimTimestamp);
    }

    /**
     * @dev Retrieves the current active sale round
     * @return The current SaleRound struct
     */
    function getCurrentRound() public view returns (SaleRound memory) {
        uint256 roundId = getCurrentRoundId();
        return saleRounds[roundId];
    }

    /**
     * @dev Retrieves the ID of the current active sale round
     * @return The ID of the current round
     */
    function getCurrentRoundId() public view returns (uint256) {
        for (uint i = 0; i < saleRounds.length; i++) {
            if (
                block.timestamp >= saleRounds[i].startTime &&
                block.timestamp < saleRounds[i].endTime &&
                !saleRounds[i].isFinish
            ) {
                return i;
            }
        }
        revert NoActiveRound();
    }

    /**
     * @dev Retrieves the allocation details for a specific beneficiary and round
     * @param _beneficiary Address of the beneficiary
     * @param _roundId ID of the sale round
     * @return The Allocation struct for the specified beneficiary and round
     */
    function getAllocationDetails(
        address _beneficiary,
        uint256 _roundId
    ) external view returns (Allocation memory) {
        return allocations[_beneficiary][_roundId];
    }

    /**
     * @dev Retrieves the current ETH/USD price from Chainlink price feed
     * @return The current ETH/USD price
     */
    function getEthUsdPrice() internal view returns (uint256) {
        (, int256 price, , , ) = ethUsdPriceFeed.latestRoundData();
        if (price <= 0) revert InvalidEthUsdPrice();
        return uint256(price);
    }

    /**
     * @dev Allows admins to update the end time of the current round
     * @param _newEndTime The new end time for the current round
     */
    function updateCurrentRoundEndTime(
        uint256 _newEndTime
    ) external onlyRole(ADMIN_ROLE) {
        uint256 currentRoundId = getCurrentRoundId();
        SaleRound storage currentRound = saleRounds[currentRoundId];
        if (_newEndTime <= block.timestamp) revert InvalidTimeRange();
        if (_newEndTime <= currentRound.startTime) revert InvalidTimeRange();
        currentRound.endTime = _newEndTime;
        emit CurrentRoundEndTimeUpdated(currentRoundId, _newEndTime);
    }

    /**
     * @dev Allows admins to update parameters of a future round
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
    ) external onlyRole(ADMIN_ROLE) {
        if (_roundId <= getCurrentRoundId())
            revert CannotModifyPastOrCurrentRound();
        if (_startTime >= _endTime) revert InvalidTimeRange();
        if (_tokenPrice == 0) revert InvalidTokenPrice();
        if (_maxCap == 0 || _softCap == 0 || _softCap > _maxCap)
            revert InvalidCap();
        if (_minPurchase > _maxPurchase) revert InvalidPurchaseLimits();
        if (_vestingDuration == 0) revert InvalidVestingDuration();
        if (_tgeReleasePercentage > 100) revert InvalidTgeReleasePercentage();

        SaleRound storage round = saleRounds[_roundId];
        round.startTime = _startTime;
        round.endTime = _endTime;
        round.tokenPrice = _tokenPrice;
        round.maxCap = _maxCap;
        round.softCap = _softCap;
        round.minPurchase = _minPurchase;
        round.maxPurchase = _maxPurchase;
        round.cliffDuration = _cliffDuration;
        round.vestingDuration = _vestingDuration;
        round.tgeReleasePercentage = _tgeReleasePercentage;
        round.lockDuration = _lockDuration;

        emit FutureRoundUpdated(_roundId);
    }

    /**
     * @dev Allows admins to withdraw funds raised in a specific round
     * @param _roundId ID of the round to withdraw funds from
     */
    function withdrawRoundFunds(
        uint256 _roundId
    ) external onlyRole(ADMIN_ROLE) {
        SaleRound storage round = saleRounds[_roundId];
        if (!round.isFinish) revert RoundNotFinished();
        if (round.totalRaised < round.softCap) revert SoftCapNotReached();

        uint256 amount = round.totalRaised;
        round.totalRaised = 0;
        usdcToken.safeTransfer(msg.sender, amount);

        emit RoundFundsWithdrawn(_roundId, amount);
    }

    /**
     * @dev Allows users to request a refund for a specific round if its soft cap wasn't reached
     * @param _roundId ID of the round to request a refund from
     */
    function refundForRound(uint256 _roundId) external nonReentrant {
        if (!icoEnded) revert IcoNotEndedYet();
        SaleRound storage round = saleRounds[_roundId];
        if (!round.isFinish || round.totalRaised >= round.softCap)
            revert RefundNotAvailable();

        Allocation storage allocation = allocations[msg.sender][_roundId];
        uint256 refundAmount = allocation.totalUsdcAmount;
        if (refundAmount == 0) revert NoAllocationToRefund();

        allocation.totalUsdcAmount = 0;
        allocation.totalTokenAmount = 0;
        usdcToken.safeTransfer(msg.sender, refundAmount);

        emit Refunded(msg.sender, refundAmount);
    }
}