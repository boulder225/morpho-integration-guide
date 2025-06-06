// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console2 } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MorphoIntegration } from "../src/MorphoIntegration.sol";
import { IMorpho } from "../src/IMorpho.sol";

/**
 * @title ExampleIntegration
 * @notice Demonstrates how to use MorphoIntegration contract
 * @dev This script shows real-world usage patterns
 */
contract ExampleIntegration is Script {
    MorphoIntegration integration;

    // Example tokens (mainnet addresses)
    address constant USDC = 0xa0b86a33E6417C0c91d7bCbc75D3d83D36C8b2A7;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant ETH_USD_ORACLE = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address constant MORPHO_IRM = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;

    // Market parameters
    IMorpho.MarketParams marketParams;

    function setUp() public {
        address integrationAddress = vm.envAddress("INTEGRATION_ADDRESS");
        integration = MorphoIntegration(integrationAddress);

        // Set up market parameters
        marketParams = IMorpho.MarketParams({
            loanToken: USDC,
            collateralToken: WETH,
            oracle: ETH_USD_ORACLE,
            irm: MORPHO_IRM,
            lltv: 800000000000000000 // 80%
         });
    }

    /**
     * @notice Example 1: Basic supply operation
     */
    function example1_BasicSupply() external {
        console2.log("\n=== Example 1: Basic Supply ===");

        uint256 supplyAmount = 1000e6; // 1000 USDC
        uint256 minShares = supplyAmount * 99 / 100; // 1% slippage tolerance

        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);

        // Approve tokens
        IERC20(USDC).approve(address(integration), supplyAmount);

        // Execute supply with slippage protection
        (uint256 assetsSupplied, uint256 sharesReceived) =
            integration.supplyWithProtection(marketParams, supplyAmount, minShares);

        vm.stopBroadcast();

        console2.log("Assets supplied:", assetsSupplied);
        console2.log("Shares received:", sharesReceived);
        console2.log("Effective rate:", (sharesReceived * 1e18) / assetsSupplied);
    }

    /**
     * @notice Example 2: Collateral supply and borrowing
     */
    function example2_CollateralAndBorrow() external {
        console2.log("\n=== Example 2: Collateral & Borrow ===");

        uint256 collateralAmount = 1e18; // 1 WETH
        uint256 borrowAmount = 1600e6; // $1600 USDC (80% of $2000 WETH)

        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);

        // Step 1: Supply collateral
        IERC20(WETH).approve(address(integration), collateralAmount);
        integration.supplyCollateralSecure(marketParams, collateralAmount);
        console2.log("Collateral supplied:", collateralAmount);

        // Step 2: Borrow with health check
        (uint256 assetsBorrowed, uint256 sharesBorrowed) = integration.borrowWithHealthCheck(
            marketParams,
            borrowAmount,
            1.5e18 // Max health factor of 1.5
        );

        vm.stopBroadcast();

        console2.log("Assets borrowed:", assetsBorrowed);
        console2.log("Shares borrowed:", sharesBorrowed);

        // Calculate health factor
        uint256 collateralValue = collateralAmount * 2000; // Assume $2000 ETH price
        uint256 borrowValue = assetsBorrowed;
        uint256 healthFactor = (collateralValue * marketParams.lltv / 1e18) * 1e18 / borrowValue;
        console2.log("Health factor:", healthFactor);
    }

    /**
     * @notice Example 3: Market analysis and efficiency tracking
     */
    function example3_MarketAnalysis() public view {
        console2.log("\n=== Example 3: Market Analysis ===");

        // Get comprehensive market information
        (IMorpho.Market memory market, uint256 efficiency, uint256 borrowRate) = integration.getMarketInfo(marketParams);

        console2.log("Total supply assets:", market.totalSupplyAssets);
        console2.log("Total borrow assets:", market.totalBorrowAssets);
        console2.log("Market efficiency:", efficiency, "%");
        console2.log("Current borrow rate:", borrowRate);

        // Calculate utilization rate
        if (market.totalSupplyAssets > 0) {
            uint256 utilization = (market.totalBorrowAssets * 100) / market.totalSupplyAssets;
            console2.log("Utilization rate:", utilization, "%");
        }

        // Calculate supply APY (simplified)
        uint256 supplyRate = (borrowRate * market.totalBorrowAssets) / market.totalSupplyAssets;
        console2.log("Supply rate:", supplyRate);
    }

    /**
     * @notice Example 4: Batch operations for efficiency
     */
    function example4_BatchOperations() external {
        console2.log("\n=== Example 4: Batch Operations ===");

        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address user = vm.addr(privateKey);

        // Check balances before
        uint256 usdcBefore = IERC20(USDC).balanceOf(user);
        uint256 wethBefore = IERC20(WETH).balanceOf(user);

        vm.startBroadcast(privateKey);

        // Batch 1: Setup position
        uint256 collateralAmount = 0.5e18; // 0.5 WETH
        uint256 supplyAmount = 500e6; // 500 USDC

        IERC20(WETH).approve(address(integration), collateralAmount);
        IERC20(USDC).approve(address(integration), supplyAmount);

        integration.supplyCollateralSecure(marketParams, collateralAmount);
        integration.supplyWithProtection(marketParams, supplyAmount, supplyAmount * 99 / 100);

        // Batch 2: Leverage position
        uint256 borrowAmount = 400e6; // Borrow 400 USDC
        integration.borrowWithHealthCheck(marketParams, borrowAmount, 2e18);

        // Could supply borrowed USDC again for leverage (be careful with liquidation risk)

        vm.stopBroadcast();

        // Check balances after
        uint256 usdcAfter = IERC20(USDC).balanceOf(user);
        uint256 wethAfter = IERC20(WETH).balanceOf(user);

        console2.log("USDC change:", int256(usdcAfter) - int256(usdcBefore));
        console2.log("WETH change:", int256(wethAfter) - int256(wethBefore));
    }

    /**
     * @notice Example 5: Risk management and monitoring
     */
    function example5_RiskManagement() public view {
        console2.log("\n=== Example 5: Risk Management ===");

        address user = vm.addr(vm.envUint("PRIVATE_KEY"));
        bytes32 marketId = keccak256(abi.encode(marketParams));

        // Get user position (would need to add this function to integration contract)
        // MorphoIntegration.Position memory position = integration.getUserPosition(marketParams, user);

        // Risk metrics calculation (placeholder logic)
        uint256 collateralValue = 1e18 * 2000; // 1 ETH * $2000
        uint256 borrowValue = 800e6; // $800 borrowed

        // Health factor
        uint256 healthFactor = (collateralValue * marketParams.lltv / 1e18) * 1e18 / borrowValue;
        console2.log("Health factor:", healthFactor);

        // Liquidation price
        uint256 liquidationPrice = (borrowValue * 1e18) / (1e18 * marketParams.lltv / 1e18);
        console2.log("Liquidation price (ETH):", liquidationPrice);

        // Risk level assessment
        if (healthFactor > 2e18) {
            console2.log("Risk level: LOW");
        } else if (healthFactor > 1.5e18) {
            console2.log("Risk level: MEDIUM");
        } else if (healthFactor > 1.2e18) {
            console2.log("Risk level: HIGH");
        } else {
            console2.log("Risk level: CRITICAL");
        }

        // Efficiency analysis
        uint256 efficiency = integration.calculateEfficiency(marketId);
        console2.log("Market efficiency:", efficiency, "% (target: >60%)");
    }

    /**
     * @notice Run all examples in sequence
     */
    function runAllExamples() external {
        setUp();

        console2.log("Running Morpho Integration Examples");
        console2.log("=====================================");

        // Note: In practice, you'd run these separately to avoid conflicts
        // example1_BasicSupply();
        // example2_CollateralAndBorrow();
        example3_MarketAnalysis();
        // example4_BatchOperations();
        example5_RiskManagement();

        console2.log("\nAll examples completed successfully!");
    }
}
