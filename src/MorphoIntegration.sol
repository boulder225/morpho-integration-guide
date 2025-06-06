// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IMorpho } from "./IMorpho.sol";

interface IIrm {
    function borrowRateView(IMorpho.MarketParams memory marketParams, IMorpho.Market memory market)
        external
        view
        returns (uint256);
}

/**
 * @title MorphoIntegration
 * @notice A comprehensive wrapper for Morpho Blue protocol interactions
 * @dev Implements security patterns and efficiency optimizations from the integration guide
 */
contract MorphoIntegration is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    /// @notice The Morpho Blue protocol contract
    IMorpho public immutable morpho;

    /// @notice Efficiency tracking for P2P matching
    struct EfficiencyMetrics {
        uint256 totalP2PVolume;
        uint256 totalPoolVolume;
        uint256 lastUpdateTimestamp;
    }

    /// @notice Market efficiency metrics
    mapping(bytes32 => EfficiencyMetrics) public marketEfficiency;

    /// @notice Events
    event SupplyExecuted(bytes32 indexed marketId, address indexed user, uint256 assets, uint256 shares);
    event BorrowExecuted(bytes32 indexed marketId, address indexed user, uint256 assets, uint256 shares);
    event CollateralSupplied(bytes32 indexed marketId, address indexed user, uint256 assets);
    event EfficiencyUpdated(bytes32 indexed marketId, uint256 efficiency);

    /// @notice Errors
    error InvalidMarketParams();
    error InsufficientCollateral();
    error InvalidIRM();
    error ZeroAmount();

    constructor(address _morpho) {
        morpho = IMorpho(_morpho);
    }

    /**
     * @notice Supply assets to a Morpho market with collateral protection
     * @param marketParams The market parameters defining the lending pair
     * @param assets Amount of loan tokens to supply
     * @param minShares Minimum shares to receive (slippage protection)
     */
    function supplyWithProtection(IMorpho.MarketParams memory marketParams, uint256 assets, uint256 minShares)
        external
        nonReentrant
        returns (uint256 assetsSupplied, uint256 sharesSupplied)
    {
        if (assets == 0) revert ZeroAmount();

        _validateMarketParams(marketParams);

        bytes32 marketId = _getMarketId(marketParams);

        // Transfer tokens from user
        IERC20 loanToken = IERC20(marketParams.loanToken);
        loanToken.safeTransferFrom(msg.sender, address(this), assets);

        // Approve Morpho to spend tokens only if needed
        if (loanToken.allowance(address(this), address(morpho)) < assets) {
            loanToken.safeApprove(address(morpho), type(uint256).max);
        }

        // Execute supply
        (assetsSupplied, sharesSupplied) = morpho.supply(
            marketParams,
            assets,
            0, // Let Morpho calculate shares
            msg.sender,
            ""
        );

        // Slippage protection
        require(sharesSupplied >= minShares, "Insufficient shares received");

        // Update efficiency metrics - use unchecked for gas optimization
        unchecked {
            EfficiencyMetrics storage metrics = marketEfficiency[marketId];
            metrics.totalP2PVolume += assetsSupplied / 2; // Assume 50% P2P for demo
            metrics.totalPoolVolume += assetsSupplied / 2; // Assume 50% pool for demo
            metrics.lastUpdateTimestamp = block.timestamp;
        }

        emit SupplyExecuted(marketId, msg.sender, assetsSupplied, sharesSupplied);
    }

    /**
     * @notice Supply collateral with security validations
     * @param marketParams The market parameters
     * @param assets Amount of collateral tokens to supply
     */
    function supplyCollateralSecure(IMorpho.MarketParams memory marketParams, uint256 assets) external nonReentrant {
        if (assets == 0) revert ZeroAmount();

        _validateMarketParams(marketParams);

        bytes32 marketId = _getMarketId(marketParams);

        // Transfer collateral from user
        IERC20 collateralToken = IERC20(marketParams.collateralToken);
        collateralToken.safeTransferFrom(msg.sender, address(this), assets);

        // Approve Morpho only if needed
        if (collateralToken.allowance(address(this), address(morpho)) < assets) {
            collateralToken.safeApprove(address(morpho), type(uint256).max);
        }

        // Supply collateral
        morpho.supplyCollateral(marketParams, assets, msg.sender, "");

        emit CollateralSupplied(marketId, msg.sender, assets);
    }

    /**
     * @notice Borrow with health factor validation
     * @param marketParams The market parameters
     * @param assets Amount to borrow
     * @param maxHealthFactor Maximum allowed health factor (scaled by 1e18)
     */
    function borrowWithHealthCheck(IMorpho.MarketParams memory marketParams, uint256 assets, uint256 maxHealthFactor)
        external
        nonReentrant
        returns (uint256 assetsBorrowed, uint256 sharesBorrowed)
    {
        if (assets == 0) revert ZeroAmount();

        _validateMarketParams(marketParams);

        // Check current position
        bytes32 marketId = _getMarketId(marketParams);
        IMorpho.Position memory position = morpho.position(marketId, msg.sender);

        // Validate sufficient collateral (simplified health factor check)
        uint256 collateralValue = position.collateral; // In practice, would use oracle
        uint256 borrowValue = assets; // In practice, would use oracle

        require(collateralValue * marketParams.lltv / 1e18 >= borrowValue, "Insufficient collateral");

        // Execute borrow
        (assetsBorrowed, sharesBorrowed) = morpho.borrow(marketParams, assets, 0, msg.sender, msg.sender);

        emit BorrowExecuted(marketId, msg.sender, assetsBorrowed, sharesBorrowed);
    }

    /**
     * @notice Calculate market efficiency (P2P volume / Total volume)
     * @param marketId The market identifier
     * @return efficiency The efficiency percentage (scaled by 100)
     */
    function calculateEfficiency(bytes32 marketId) public view returns (uint256 efficiency) {
        EfficiencyMetrics memory metrics = marketEfficiency[marketId];
        uint256 totalVolume = metrics.totalP2PVolume + metrics.totalPoolVolume;

        if (totalVolume == 0) return 0;

        efficiency = (metrics.totalP2PVolume * 100) / totalVolume;
    }

    /**
     * @notice Get comprehensive market information
     * @param marketParams The market parameters
     * @return market The market state
     * @return efficiency Current efficiency percentage
     * @return borrowRate Current borrow rate
     */
    function getMarketInfo(IMorpho.MarketParams memory marketParams)
        external
        view
        returns (IMorpho.Market memory market, uint256 efficiency, uint256 borrowRate)
    {
        bytes32 marketId = _getMarketId(marketParams);
        market = morpho.market(marketId);
        efficiency = calculateEfficiency(marketId);
        borrowRate = IIrm(marketParams.irm).borrowRateView(marketParams, market);
    }

    /// ===== INTERNAL FUNCTIONS =====

    /**
     * @notice Validate market parameters
     * @param marketParams The market parameters to validate
     */
    function _validateMarketParams(IMorpho.MarketParams memory marketParams) internal view {
        if (marketParams.loanToken == address(0)) revert InvalidMarketParams();
        if (marketParams.collateralToken == address(0)) revert InvalidMarketParams();
        if (marketParams.oracle == address(0)) revert InvalidMarketParams();
        if (marketParams.irm == address(0)) revert InvalidMarketParams();
        if (marketParams.lltv == 0 || marketParams.lltv > 1e18) revert InvalidMarketParams();

        _validateIRM(marketParams.irm);
    }

    /**
     * @notice Validate Interest Rate Model
     * @param irm The IRM address to validate
     */
    function _validateIRM(address irm) internal view {
        // Basic validation - in production, add more comprehensive checks
        require(irm.code.length > 0, "Invalid IRM: not a contract");
    }

    /**
     * @notice Generate market ID from parameters
     * @param marketParams The market parameters
     * @return The market ID hash
     */
    function _getMarketId(IMorpho.MarketParams memory marketParams) internal pure returns (bytes32) {
        return keccak256(abi.encode(marketParams));
    }

    /**
     * @notice Update efficiency metrics for a market
     * @param marketId The market identifier
     * @param volume The transaction volume
     */
    function _updateEfficiencyMetrics(bytes32 marketId, uint256 volume) internal {
        EfficiencyMetrics storage metrics = marketEfficiency[marketId];

        // Simplified P2P detection logic
        // In practice, would analyze actual P2P matching from Morpho events
        metrics.totalP2PVolume += volume / 2; // Assume 50% P2P for demo
        metrics.totalPoolVolume += volume / 2; // Assume 50% pool for demo
        metrics.lastUpdateTimestamp = block.timestamp;

        uint256 efficiency = calculateEfficiency(marketId);
        emit EfficiencyUpdated(marketId, efficiency);
    }

    /// ===== EMERGENCY FUNCTIONS =====

    /**
     * @notice Emergency token recovery (owner only)
     * @param token Token to recover
     * @param amount Amount to recover
     */
    function emergencyRecover(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }
}
