// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@chainlink/contracts/src/interfaces/feeds/AggregatorV3Interface.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "./Melies.sol";
import "./MeliesTokenDistributor.sol";
import "./interfaces/IMeliesICO.sol";

/**
 * @title MeliesICO
 * @dev Manages the Initial Coin Offering (ICO) for the Melies token.
 *
 * This contract implements a comprehensive ICO system with the following features:
 * - Multiple sale rounds (Seed, Private Sale, Public Sale)
 * - Token purchases with ETH and USDC
 * - Whitelist management for each round
 * - Vesting schedules with cliff periods
 * - Refund mechanism for failed rounds
 * - Admin controls for ICO management
 * - Integration with Chainlink price feeds and Uniswap
 *
 * @author Melies Team
 */
contract MeliesICO is IMeliesICO, ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;

    // ============ CONSTANTS ============

    /// @dev Role for admin functions
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @dev Maximum contribution per wallet in public rounds ($50,000 USD)
    uint256 public constant PUBLIC_ROUND_MAX_CONTRIBUTION = 50_000e6;

    /// @dev Slippage tolerance denominator (10,000 = 100%)
    uint256 public constant SLIPPAGE_DENOMINATOR = 10_000;

    /// @dev Price feed decimals
    uint8 public constant PRICE_DECIMALS = 6;

    /// @dev USDC token decimals
    uint8 public constant USDC_DECIMALS = 6;

    // ============ STATE VARIABLES ============

    /// @dev Reference to the Melies token contract
    Melies public meliesToken;

    /// @dev Reference to the token distributor contract
    MeliesTokenDistributor public tokenDistributor;

    /// @dev Reference to the USDC token contract
    IERC20 public usdcToken;

    /// @dev Reference to the Uniswap V2 Router
    IUniswapV2Router02 public uniswapRouter;

    /// @dev Reference to the Chainlink ETH/USD price feed
    AggregatorV3Interface public ethUsdPriceFeed;

    /// @dev Slippage tolerance for ETH to USDC swaps (default: 0.5%)
    uint256 public slippageTolerance = 50;

    /// @dev Array of sale rounds
    SaleRound[] public saleRounds;

    /// @dev Mapping of user contributions per round
    mapping(address => mapping(uint256 => uint256))
        public userRoundContributions;

    /// @dev Mapping of whitelisted addresses per round
    mapping(uint256 => mapping(address => bool)) public whitelist;

    /// @dev Total USDC raised across all rounds
    uint256 public totalUsdcRaised;

    /// @dev Flag indicating if ICO has ended
    bool public icoEnded;

    /// @dev Flag indicating if token claims are enabled
    bool public claimEnabled;

    // ============ CONSTRUCTOR ============

    /**
     * @dev Constructor to initialize the MeliesICO contract
     * @param _meliesToken Address of the Melies token contract
     * @param _tokenDistributor Address of the MeliesTokenDistributor contract
     * @param _usdcToken Address of the USDC token contract
     * @param _uniswapRouter Address of the Uniswap V2 Router
     * @param _ethUsdPriceFeed Address of the Chainlink ETH/USD price feed
     *
     * Requirements:
     * - All addresses must be valid contract addresses
     */
    constructor(
        address _meliesToken,
        address _tokenDistributor,
        address _usdcToken,
        address _uniswapRouter,
        address _ethUsdPriceFeed
    ) {
        require(_meliesToken != address(0), "Invalid Melies token address");
        require(_tokenDistributor != address(0), "Invalid distributor address");
        require(_usdcToken != address(0), "Invalid USDC token address");
        require(_uniswapRouter != address(0), "Invalid Uniswap router address");
        require(_ethUsdPriceFeed != address(0), "Invalid price feed address");

        meliesToken = Melies(_meliesToken);
        tokenDistributor = MeliesTokenDistributor(_tokenDistributor);
        usdcToken = IERC20(_usdcToken);
        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
        ethUsdPriceFeed = AggregatorV3Interface(_ethUsdPriceFeed);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    // ============ ADMIN FUNCTIONS ============

    /**
     * @dev Updates the slippage tolerance for ETH to USDC swaps
     * @param _newSlippageTolerance New slippage tolerance value (max 10%)
     *
     * Requirements:
     * - Caller must have ADMIN_ROLE
     * - New slippage tolerance must not exceed 10%
     *
     * Emits a {SlippageToleranceUpdated} event.
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
     * @param _cliffMonthDuration Cliff duration for token vesting (in months)
     * @param _vestingMonthDuration Total vesting duration (in months)
     * @param _tgeReleasePercentage TGE release percentage
     *
     * Requirements:
     * - Caller must have ADMIN_ROLE
     * - Start time must be before end time
     * - Token price must be greater than 0
     * - Max cap and soft cap must be valid
     * - Purchase limits must be valid
     * - Vesting duration must be valid
     * - TGE release percentage must not exceed 100%
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
    ) external onlyRole(ADMIN_ROLE) {
        if (_startTime >= _endTime) revert InvalidTimeRange();
        if (_tokenPrice == 0) revert InvalidTokenPrice();
        if (_maxCap == 0 || _softCap == 0 || _softCap > _maxCap)
            revert InvalidCap();
        if (_minPurchase > _maxPurchase) revert InvalidPurchaseLimits();
        if (_vestingMonthDuration != 0 && _vestingMonthDuration < 1)
            revert InvalidVestingDuration();
        // Maximum duration is 48 months
        if ((_cliffMonthDuration + _vestingMonthDuration) > 48)
            revert InvalidCliffOrVestingDuration();
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
                totalUsdcRaised: 0,
                isFinish: false,
                cliffMonthDuration: _cliffMonthDuration,
                vestingMonthDuration: _vestingMonthDuration,
                tgeReleasePercentage: _tgeReleasePercentage
            })
        );
    }

    /**
     * @dev Adds addresses to the whitelist for a specific round
     * @param _roundId ID of the sale round
     * @param _addresses Addresses to be added to the whitelist
     *
     * Requirements:
     * - Caller must have ADMIN_ROLE
     * - Round ID must be valid
     *
     * Emits an {AddedToWhitelist} event.
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
     *
     * Requirements:
     * - Caller must have ADMIN_ROLE
     * - Round ID must be valid
     *
     * Emits a {RemovedFromWhitelist} event.
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
     * @dev Allows admins to add purchases made with fiat currency
     * @param _buyer Address of the token buyer
     * @param _usdAmount Amount of USD equivalent purchased
     * @param _roundId ID of the sale round
     *
     * Requirements:
     * - Caller must have ADMIN_ROLE
     * - Buyer address must be valid
     * - USD amount must be greater than 0
     * - Round ID must be valid
     */
    function addFiatPurchase(
        address _buyer,
        uint256 _usdAmount,
        uint8 _roundId
    ) external onlyRole(ADMIN_ROLE) {
        if (_buyer == address(0)) revert InvalidBuyer();
        if (_roundId >= saleRounds.length) revert InvalidRoundId();
        if (_usdAmount == 0) revert UsdAmountMustBeGreaterThanZero();

        _processPurchase(_buyer, _usdAmount, _roundId);
    }

    /**
     * @dev Allows admins to withdraw funds raised in a specific round
     * @param _roundId ID of the round to withdraw funds from
     *
     * Requirements:
     * - Caller must have ADMIN_ROLE
     * - Round must be finished
     * - Soft cap must be reached
     *
     * Emits a {RoundFundsWithdrawn} event.
     */
    function withdrawRoundFunds(
        uint256 _roundId
    ) external onlyRole(ADMIN_ROLE) {
        SaleRound storage round = saleRounds[_roundId];
        if (!round.isFinish) revert RoundNotFinished();
        if (round.totalUsdcRaised < round.softCap) revert SoftCapNotReached();

        uint256 usdcAmount = round.totalUsdcRaised;
        round.totalUsdcRaised = 0;

        if (usdcAmount > 0) {
            usdcToken.safeTransfer(msg.sender, usdcAmount);
        }

        emit RoundFundsWithdrawn(_roundId, usdcAmount);
    }

    /**
     * @dev Allows admins to end the ICO
     *
     * Requirements:
     * - Caller must have ADMIN_ROLE
     * - ICO must not already be ended
     *
     * Emits an {IcoEnded} event.
     */
    function endIco() external onlyRole(ADMIN_ROLE) {
        if (icoEnded) revert IcoAlreadyEnded();
        icoEnded = true;

        bool allRoundsSoftCapReached = true;
        for (uint256 i = 0; i < saleRounds.length; i++) {
            SaleRound storage round = saleRounds[i];
            if (!round.isFinish) {
                round.isFinish = true;
                if (round.totalUsdcRaised < round.softCap) {
                    allRoundsSoftCapReached = false;
                    emit RefundsAvailableForRound(i);
                }
            }
        }

        claimEnabled = allRoundsSoftCapReached;

        // Distribute unsold tokens if all rounds reached soft cap
        if (allRoundsSoftCapReached) {
            tokenDistributor.distributeUnsoldTokens();
        }

        emit IcoEnded(claimEnabled);
    }

    /**
     * @dev Allows admins to withdraw raised USDC after ICO ends
     *
     * Requirements:
     * - Caller must have ADMIN_ROLE
     * - ICO must be ended
     *
     * Emits a {UsdcWithdrawn} event.
     */
    function withdrawUsdc() external onlyRole(ADMIN_ROLE) {
        if (!icoEnded) revert IcoNotEndedYet();

        uint256 amount = usdcToken.balanceOf(address(this));

        usdcToken.safeTransfer(msg.sender, amount);
        emit UsdcWithdrawn(msg.sender, amount);
    }

    /**
     * @dev Allows admins to withdraw any ETH in the contract after ICO ends
     *
     * Requirements:
     * - Caller must have ADMIN_ROLE
     * - ICO must be ended
     * - Contract must have ETH balance
     *
     * Emits an {EthWithdrawn} event.
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
     * @dev Allows admins to recover any ERC20 tokens accidentally sent to the contract
     * @param _token Address of the ERC20 token to recover
     * @param _amount Amount of tokens to recover
     *
     * Requirements:
     * - Caller must have ADMIN_ROLE
     * - Token must not be Melies or USDC tokens
     * - Contract must have sufficient token balance
     *
     * Emits a {TokensRecovered} event.
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

    // ============ USER FUNCTIONS ============

    /**
     * @dev Allows users to buy tokens with ETH
     * @param _roundId ID of the sale round
     *
     * Requirements:
     * - User must send ETH with the transaction
     * - Round ID must be valid
     * - User must be whitelisted for the round
     *
     * Emits a {TokensPurchased} event.
     */
    function buyWithEth(uint8 _roundId) external payable nonReentrant {
        if (msg.value == 0) revert NoEthSent();
        if (_roundId >= saleRounds.length) revert InvalidRoundId();
        _buyWithEth(_roundId);
    }

    /**
     * @dev Allows users to buy tokens with USDC
     * @param _roundId ID of the sale round
     * @param _amount Amount of USDC to spend on token purchase
     *
     * Requirements:
     * - Round ID must be valid
     * - USDC amount must be greater than 0
     * - User must be whitelisted for the round
     * - User must have approved sufficient USDC allowance
     *
     * Emits a {TokensPurchased} event.
     */
    function buyWithUsdc(
        uint8 _roundId,
        uint256 _amount
    ) external nonReentrant {
        if (_roundId >= saleRounds.length) revert InvalidRoundId();
        if (_amount == 0) revert UsdcAmountMustBeGreaterThanZero();

        usdcToken.safeTransferFrom(msg.sender, address(this), _amount);

        _processPurchase(msg.sender, _amount, _roundId);
    }

    /**
     * @dev Allows users to request a refund if ICO ends without enabling claims
     *
     * Requirements:
     * - ICO must be ended
     * - Claims must not be enabled
     * - User must have allocations to refund
     *
     * Emits a {Refunded} event.
     */
    function refund() external nonReentrant {
        if (!icoEnded) revert IcoNotEndedYet();
        if (claimEnabled) revert RefundNotAvailable();
        uint256 totalRefundUsdcAmount = 0;

        for (uint256 i = 0; i < saleRounds.length; i++) {
            SaleRound storage round = saleRounds[i];
            if (round.isFinish && round.totalUsdcRaised < round.softCap) {
                uint256 allocationAmount = userRoundContributions[msg.sender][
                    i
                ];
                if (allocationAmount > 0) {
                    totalRefundUsdcAmount += allocationAmount;
                    userRoundContributions[msg.sender][i] = 0;
                }
            }
        }

        if (totalRefundUsdcAmount == 0) revert NoAllocationToRefund();
        if (totalRefundUsdcAmount > 0) {
            usdcToken.safeTransfer(msg.sender, totalRefundUsdcAmount);
        }
        emit Refunded(msg.sender, totalRefundUsdcAmount);
    }

    /**
     * @dev Allows users to request a refund for a specific round if its soft cap wasn't reached
     * @param _roundId ID of the round to request a refund from
     *
     * Requirements:
     * - ICO must be ended
     * - Round must be finished and soft cap not reached
     * - User must have allocations in the round
     *
     * Emits a {Refunded} event.
     */
    function refundForRound(uint256 _roundId) external nonReentrant {
        if (!icoEnded) revert IcoNotEndedYet();
        SaleRound storage round = saleRounds[_roundId];
        if (!round.isFinish || round.totalUsdcRaised >= round.softCap)
            revert RefundNotAvailable();

        uint256 refundUsdcAmount = userRoundContributions[msg.sender][_roundId];
        if (refundUsdcAmount == 0) revert NoAllocationToRefund();

        userRoundContributions[msg.sender][_roundId] = 0;
        if (refundUsdcAmount > 0) {
            usdcToken.safeTransfer(msg.sender, refundUsdcAmount);
        }

        emit Refunded(msg.sender, refundUsdcAmount);
    }

    // ============ INTERNAL FUNCTIONS ============

    /**
     * @dev Internal function to process ETH to token purchases
     * @param _roundId ID of the sale round
     */
    function _buyWithEth(uint8 _roundId) internal {
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

        _processPurchase(msg.sender, amounts[1], _roundId);
    }

    /**
     * @dev Internal function to process token purchases
     * @param _buyer Address of the token buyer
     * @param _usdAmount Amount of USD spent on the purchase
     * @param _roundId ID of the sale round
     * @return tokenAmount Amount of tokens purchased
     */
    function _processPurchase(
        address _buyer,
        uint256 _usdAmount,
        uint8 _roundId
    ) internal returns (uint256) {
        SaleRound storage round = saleRounds[_roundId];

        if (icoEnded) revert IcoAlreadyEnded();
        if (!whitelist[_roundId][_buyer]) revert NotWhitelisted();
        if (_usdAmount < round.minPurchase) revert BelowMinimumPurchase();
        if (_usdAmount > round.maxPurchase) revert ExceedsMaximumPurchase();

        // Check wallet contribution limit
        uint256 currentWalletContribution = userRoundContributions[_buyer][
            _roundId
        ];
        if (
            currentWalletContribution + _usdAmount >
            PUBLIC_ROUND_MAX_CONTRIBUTION
        ) {
            revert ExceedsWalletContributionLimit();
        }

        if (round.totalUsdcRaised + _usdAmount > round.maxCap)
            revert RoundCapExceeded();

        // Track total raised in USDC
        round.totalUsdcRaised += _usdAmount;

        // Track wallet contribution for the current round
        userRoundContributions[_buyer][_roundId] += _usdAmount;

        totalUsdcRaised += _usdAmount;

        // PRICE_DECIMALS cancels out with USDC_DECIMALS (6-6)
        uint256 tokenAmount = (_usdAmount * 10 ** meliesToken.decimals()) /
            round.tokenPrice;

        _addAllocation(_buyer, tokenAmount, _usdAmount, _roundId);

        emit TokensPurchased(_buyer, _usdAmount, tokenAmount);

        return tokenAmount;
    }

    /**
     * @dev Internal function to add token allocation for a buyer
     * @param _beneficiary Address of the token beneficiary
     * @param _tokenAmount Amount of tokens allocated
     * @param _usdcAmount Amount of USDC spent
     * @param _roundId ID of the sale round
     */
    function _addAllocation(
        address _beneficiary,
        uint256 _tokenAmount,
        uint256 _usdcAmount,
        uint256 _roundId
    ) internal {
        // Create allocation in MeliesTokenDistributor for vesting/claiming
        SaleRound memory round = saleRounds[_roundId];
        string memory roundName = _getRoundName(_roundId);

        // Convert TGE percentage from 0-100 to basis points (0-10000)
        uint256 tgeReleasePercentageBps = round.tgeReleasePercentage * 100;

        // Use cliff and vesting duration directly as they are already in months
        uint256 cliffMonths = round.cliffMonthDuration;
        uint256 vestingMonths = round.vestingMonthDuration;

        tokenDistributor.addAllocation(
            _beneficiary,
            _tokenAmount,
            cliffMonths,
            vestingMonths,
            roundName,
            tgeReleasePercentageBps,
            false
        );

        emit AllocationAdded(
            _beneficiary,
            _tokenAmount,
            round.cliffMonthDuration,
            round.vestingMonthDuration,
            _roundId
        );
    }

    /**
     * @dev Internal function to get round name based on round ID
     * @param _roundId ID of the sale round
     * @return Round name string
     */
    function _getRoundName(
        uint256 _roundId
    ) internal pure returns (string memory) {
        if (_roundId == 0) return "Seed";
        if (_roundId == 1) return "Private Sale";
        if (_roundId == 2) return "Public Sale";
        return string(abi.encodePacked("Round ", _roundId));
    }

    // ============ VIEW FUNCTIONS ============

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
     * @dev Retrieves the user's USDC contribution for a specific round
     * @param _beneficiary Address of the beneficiary
     * @param _roundId ID of the sale round
     * @return The total USDC amount contributed by the user in the specified round
     */
    function getUserRoundContribution(
        address _beneficiary,
        uint256 _roundId
    ) external view returns (uint256) {
        return userRoundContributions[_beneficiary][_roundId];
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
     * @dev Gets the total tokens sold across all ICO rounds
     * @return Total tokens sold
     */
    function getTotalTokensSold() external view returns (uint256) {
        return tokenDistributor.getTotalTokensSold();
    }

    /**
     * @dev Gets the total contribution amount for a specific wallet in a specific round
     * @param _wallet Address of the wallet to check
     * @param _roundId ID of the round to check
     * @return Total USD amount contributed by the wallet in the round
     */
    function getWalletContribution(
        address _wallet,
        uint256 _roundId
    ) external view returns (uint256) {
        return userRoundContributions[_wallet][_roundId];
    }

    /**
     * @dev Gets the total unsold tokens
     * @return Total unsold tokens
     */
    function getUnsoldTokens() external view returns (uint256) {
        return tokenDistributor.getUnsoldTokens();
    }

    /**
     * @dev Gets the sales performance percentage
     * @return Sales performance as a percentage (0-100)
     */
    function getSalesPerformance() external view returns (uint256) {
        return tokenDistributor.getSalesPerformance();
    }

    /**
     * @dev Checks if unsold tokens have been distributed
     * @return True if unsold tokens have been distributed
     */
    function isUnsoldTokensDistributed() external view returns (bool) {
        return tokenDistributor.isUnsoldTokensDistributed();
    }
}
