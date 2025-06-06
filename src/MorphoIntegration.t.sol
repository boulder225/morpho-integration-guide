// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MorphoIntegration} from "../src/MorphoIntegration.sol";

// Mock contracts for testing
contract MockERC20 is IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    
    uint256 private _totalSupply;
    string public name;
    string public symbol;
    uint8 public decimals;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 currentAllowance = _allowances[from][msg.sender];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        
        _transfer(from, to, amount);
        _approve(from, msg.sender, currentAllowance - amount);
        
        return true;
    }

    function mint(address to, uint256 amount) external {
        _totalSupply += amount;
        _balances[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(_balances[from] >= amount, "ERC20: transfer amount exceeds balance");

        _balances[from] -= amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
}

contract MockMorpho {
    struct MarketParams {
        address loanToken;
        address collateralToken;
        address oracle;
        address irm;
        uint256 lltv;
    }

    struct Market {
        uint128 totalSupplyAssets;
        uint128 totalSupplyShares;
        uint128 totalBorrowAssets;
        uint128 totalBorrowShares;
        uint128 lastUpdate;
        uint128 fee;
    }

    struct Position {
        uint256 supplyShares;
        uint128 borrowShares;
        uint128 collateral;
    }

    mapping(bytes32 => Market) public markets;
    mapping(bytes32 => mapping(address => Position)) public positions;

    function supply(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        bytes calldata data
    ) external returns (uint256 assetsSupplied, uint256 sharesSupplied) {
        // Transfer tokens from caller
        IERC20(marketParams.loanToken).transferFrom(msg.sender, address(this), assets);
        
        // Simple 1:1 asset to share ratio for testing
        assetsSupplied = assets;
        sharesSupplied = assets;
        
        bytes32 marketId = keccak256(abi.encode(marketParams));
        positions[marketId][onBehalf].supplyShares += sharesSupplied;
        markets[marketId].totalSupplyAssets += uint128(assetsSupplied);
        markets[marketId].totalSupplyShares += uint128(sharesSupplied);
    }

    function supplyCollateral(
        MarketParams memory marketParams,
        uint256 assets,
        address onBehalf,
        bytes calldata data
    ) external {
        IERC20(marketParams.collateralToken).transferFrom(msg.sender, address(this), assets);
        
        bytes32 marketId = keccak256(abi.encode(marketParams));
        positions[marketId][onBehalf].collateral += uint128(assets);
    }

    function borrow(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) external returns (uint256 assetsBorrowed, uint256 sharesBorrowed) {
        assetsBorrowed = assets;
        sharesBorrowed = assets; // 1:1 for testing
        
        bytes32 marketId = keccak256(abi.encode(marketParams));
        positions[marketId][onBehalf].borrowShares += uint128(sharesBorrowed);
        markets[marketId].totalBorrowAssets += uint128(assetsBorrowed);
        markets[marketId].totalBorrowShares += uint128(sharesBorrowed);
        
        // Transfer tokens to receiver
        IERC20(marketParams.loanToken).transfer(receiver, assetsBorrowed);
    }

    function withdraw(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) external returns (uint256 assetsWithdrawn, uint256 sharesWithdrawn) {
        // Implementation for testing
        return (assets, shares);
    }

    function withdrawCollateral(
        MarketParams memory marketParams,
        uint256 assets,
        address onBehalf,
        address receiver
    ) external {
        // Implementation for testing
    }

    function repay(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        bytes calldata data
    ) external returns (uint256 assetsRepaid, uint256 sharesRepaid) {
        // Implementation for testing
        return (assets, shares);
    }

    function position(bytes32 id, address user) external view returns (Position memory) {
        return positions[id][user];
    }

    function market(bytes32 id) external view returns (Market memory) {
        return markets[id];
    }

    function idToMarketParams(bytes32 id) external view returns (MarketParams memory) {
        // Would need to store this mapping in real implementation
        MarketParams memory params;
        return params;
    }
}

contract MockIRM {
    function borrowRateView(
        MockMorpho.MarketParams memory marketParams,
        MockMorpho.Market memory market
    ) external pure returns (uint256) {
        // Return a fixed rate for testing (5% APR = 0.05 * 1e18)
        return 50000000000000000; // 5% in wei
    }
}

contract MockOracle {
    mapping(address => uint256) public prices;

    function setPrice(address token, uint256 price) external {
        prices[token] = price;
    }

    function getPrice(address token) external view returns (uint256) {
        return prices[token];
    }
}

/**
 * @title MorphoIntegrationTest
 * @notice Comprehensive test suite for MorphoIntegration contract
 */
contract MorphoIntegrationTest is Test {
    MorphoIntegration public integration;
    MockMorpho public mockMorpho;
    MockERC20 public loanToken;
    MockERC20 public collateralToken;
    MockIRM public mockIRM;
    MockOracle public mockOracle;
    
    address public user = address(0x1);
    address public owner = address(0x2);
    
    MockMorpho.MarketParams public marketParams;
    
    // Test constants
    uint256 constant SUPPLY_AMOUNT = 1000e18;
    uint256 constant COLLATERAL_AMOUNT = 2000e18;
    uint256 constant BORROW_AMOUNT = 500e18;
    uint256 constant LLTV = 800000000000000000; // 80% in wei

    function setUp() public {
        // Deploy mock contracts
        loanToken = new MockERC20("Mock USDC", "mUSDC", 6);
        collateralToken = new MockERC20("Mock WETH", "mWETH", 18);
        mockIRM = new MockIRM();
        mockOracle = new MockOracle();
        mockMorpho = new MockMorpho();
        
        // Deploy integration contract
        vm.prank(owner);
        integration = new MorphoIntegration(address(mockMorpho));
        
        // Set up market parameters
        marketParams = MockMorpho.MarketParams({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: address(mockOracle),
            irm: address(mockIRM),
            lltv: LLTV
        });
        
        // Set up test tokens
        loanToken.mint(user, SUPPLY_AMOUNT * 10);
        collateralToken.mint(user, COLLATERAL_AMOUNT * 10);
        loanToken.mint(address(mockMorpho), SUPPLY_AMOUNT * 10); // For borrow operations
        
        // Set oracle prices
        mockOracle.setPrice(address(loanToken), 1e18); // $1
        mockOracle.setPrice(address(collateralToken), 2000e18); // $2000
    }

    /// ===== SUPPLY TESTS =====

    function testSupplyWithProtection() public {
        vm.startPrank(user);
        
        // Approve tokens
        loanToken.approve(address(integration), SUPPLY_AMOUNT);
        
        // Execute supply
        (uint256 assetsSupplied, uint256 sharesSupplied) = integration.supplyWithProtection(
            marketParams,
            SUPPLY_AMOUNT,
            SUPPLY_AMOUNT // Min shares = assets for 1:1 ratio
        );
        
        vm.stopPrank();
        
        // Assertions
        assertEq(assetsSupplied, SUPPLY_AMOUNT);
        assertEq(sharesSupplied, SUPPLY_AMOUNT);
        
        // Check position
        bytes32 marketId = keccak256(abi.encode(marketParams));
        MockMorpho.Position memory position = mockMorpho.position(marketId, user);
        assertEq(position.supplyShares, SUPPLY_AMOUNT);
    }

    function testSupplyWithInsufficientShares() public {
        vm.startPrank(user);
        
        loanToken.approve(address(integration), SUPPLY_AMOUNT);
        
        // Expect revert due to slippage protection
        vm.expectRevert("Insufficient shares received");
        integration.supplyWithProtection(
            marketParams,
            SUPPLY_AMOUNT,
            SUPPLY_AMOUNT + 1 // Require more shares than possible
        );
        
        vm.stopPrank();
    }

    function testSupplyZeroAmount() public {
        vm.startPrank(user);
        
        vm.expectRevert(MorphoIntegration.ZeroAmount.selector);
        integration.supplyWithProtection(marketParams, 0, 0);
        
        vm.stopPrank();
    }

    /// ===== COLLATERAL TESTS =====

    function testSupplyCollateralSecure() public {
        vm.startPrank(user);
        
        collateralToken.approve(address(integration), COLLATERAL_AMOUNT);
        
        integration.supplyCollateralSecure(marketParams, COLLATERAL_AMOUNT);
        
        vm.stopPrank();
        
        // Check collateral position
        bytes32 marketId = keccak256(abi.encode(marketParams));
        MockMorpho.Position memory position = mockMorpho.position(marketId, user);
        assertEq(position.collateral, COLLATERAL_AMOUNT);
    }

    function testSupplyCollateralZeroAmount() public {
        vm.startPrank(user);
        
        vm.expectRevert(MorphoIntegration.ZeroAmount.selector);
        integration.supplyCollateralSecure(marketParams, 0);
        
        vm.stopPrank();
    }

    /// ===== BORROW TESTS =====

    function testBorrowWithHealthCheck() public {
        // First supply collateral
        vm.startPrank(user);
        collateralToken.approve(address(integration), COLLATERAL_AMOUNT);
        integration.supplyCollateralSecure(marketParams, COLLATERAL_AMOUNT);
        
        // Calculate max borrow based on LLTV
        uint256 maxBorrow = (COLLATERAL_AMOUNT * LLTV) / 1e18;
        
        // Borrow within limit
        (uint256 assetsBorrowed, uint256 sharesBorrowed) = integration.borrowWithHealthCheck(
            marketParams,
            maxBorrow,
            1e18 // Max health factor
        );
        
        vm.stopPrank();
        
        assertEq(assetsBorrowed, maxBorrow);
        assertEq(sharesBorrowed, maxBorrow);
        
        // Check user received tokens
        assertEq(loanToken.balanceOf(user), SUPPLY_AMOUNT * 10 + maxBorrow);
    }

    function testBorrowExceedsCollateral() public {
        vm.startPrank(user);
        
        // Supply minimal collateral
        collateralToken.approve(address(integration), 1e18);
        integration.supplyCollateralSecure(marketParams, 1e18);
        
        // Try to borrow more than collateral allows
        vm.expectRevert("Insufficient collateral");
        integration.borrowWithHealthCheck(marketParams, BORROW_AMOUNT, 1e18);
        
        vm.stopPrank();
    }

    /// ===== EFFICIENCY TESTS =====

    function testCalculateEfficiency() public {
        // Supply to generate efficiency data
        vm.startPrank(user);
        loanToken.approve(address(integration), SUPPLY_AMOUNT);
        integration.supplyWithProtection(marketParams, SUPPLY_AMOUNT, SUPPLY_AMOUNT);
        vm.stopPrank();
        
        bytes32 marketId = kecc