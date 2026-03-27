// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/TestToken.sol";
import "../src/UniswapPool.sol";

/**
 * @title UniswapPoolTest
 * @notice Comprehensive Foundry test suite for UniswapPool.
 *
 * Coverage:
 *  - Initial state verification and token ordering
 *  - First mint (geometric mean, MINIMUM_LIQUIDITY lock)
 *  - Subsequent mints (proportional LP minting)
 *  - Burn (token redemption)
 *  - Swaps in both directions with 0.3% fee enforcement
 *  - Revert conditions (InsufficientLiquidity, KInvariantViolation, zero output)
 *  - TWAP price accumulator growth
 *  - Skim excess tokens
 *  - Fuzz tests for swap k-invariant and mint/burn round-trip
 */
contract UniswapPoolTest is Test {
    // -------------------------------------------------------------------------
    // Events (redeclared for use with vm.expectEmit)
    // -------------------------------------------------------------------------

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    // -------------------------------------------------------------------------
    // Actors
    // -------------------------------------------------------------------------

    address public constant alice   = address(0x1111111111111111111111111111111111111111);
    address public constant bob     = address(0x2222222222222222222222222222222222222222);
    address public constant charlie = address(0x3333333333333333333333333333333333333333);

    uint256 public constant INITIAL_MINT = 10_000_000 * 1e18;

    // -------------------------------------------------------------------------
    // Contracts under test
    // -------------------------------------------------------------------------

    TestToken   public tokenA;
    TestToken   public tokenB;
    UniswapPool public pool;

    /// @dev Canonical token0 / token1 after address-sort.
    IERC20 public token0;
    IERC20 public token1;

    // -------------------------------------------------------------------------
    // setUp
    // -------------------------------------------------------------------------

    function setUp() public {
        tokenA = new TestToken("Token A", "TKA", INITIAL_MINT * 10);
        tokenB = new TestToken("Token B", "TKB", INITIAL_MINT * 10);

        pool   = new UniswapPool(address(tokenA), address(tokenB));
        token0 = pool.token0();
        token1 = pool.token1();

        // Distribute tokens to actors.
        for (uint256 i = 0; i < 3; i++) {
            address actor = i == 0 ? alice : (i == 1 ? bob : charlie);
            tokenA.transfer(actor, INITIAL_MINT);
            tokenB.transfer(actor, INITIAL_MINT);
        }

        // Actors approve pool.
        address[3] memory actors = [alice, bob, charlie];
        for (uint256 i = 0; i < 3; i++) {
            vm.startPrank(actors[i]);
            tokenA.approve(address(pool), type(uint256).max);
            tokenB.approve(address(pool), type(uint256).max);
            vm.stopPrank();
        }

        // Test contract also approves (used by helpers called without prank).
        tokenA.approve(address(pool), type(uint256).max);
        tokenB.approve(address(pool), type(uint256).max);
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    /**
     * @dev Transfer amt0/amt1 (as token0/token1) from `user` then call mint.
     *      Returns LP tokens minted.
     */
    function _addLiquidity(address user, uint256 amt0, uint256 amt1)
        internal
        returns (uint256 liquidity)
    {
        vm.startPrank(user);
        token0.transfer(address(pool), amt0);
        token1.transfer(address(pool), amt1);
        vm.stopPrank();
        liquidity = pool.mint(user);
    }

    /**
     * @dev Compute expected output amount for a given input using the 0.3% fee.
     *      Mirrors Uniswap V2 formula: amountOut = (amountIn * 997 * reserveOut)
     *                                              / (reserveIn * 1000 + amountIn * 997)
     */
    function _getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, "insufficient input");
        require(reserveIn > 0 && reserveOut > 0, "insufficient liquidity");
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator       = amountInWithFee * reserveOut;
        uint256 denominator     = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    // -------------------------------------------------------------------------
    // Initial state
    // -------------------------------------------------------------------------

    function test_InitialState() public view {
        // token0 < token1 by address.
        assertTrue(address(pool.token0()) < address(pool.token1()));

        (uint112 r0, uint112 r1,) = pool.getReserves();
        assertEq(r0, 0);
        assertEq(r1, 0);
        assertEq(pool.totalSupply(), 0);
    }

    // -------------------------------------------------------------------------
    // Mint
    // -------------------------------------------------------------------------

    function test_FirstMint() public {
        uint256 amt0 = 1_000_000 * 1e18;
        uint256 amt1 = 1_000_000 * 1e18;

        uint256 liquidity = _addLiquidity(alice, amt0, amt1);

        // sqrt(1e6 * 1e18 * 1e6 * 1e18) - MINIMUM_LIQUIDITY
        uint256 expectedLiquidity = _sqrt(amt0 * amt1) - pool.MINIMUM_LIQUIDITY();
        assertEq(liquidity, expectedLiquidity);

        // MINIMUM_LIQUIDITY permanently locked.
        assertEq(pool.balanceOf(address(0xdead)), pool.MINIMUM_LIQUIDITY());

        // Alice received LP tokens.
        assertEq(pool.balanceOf(alice), liquidity);
    }

    function test_MintEmitsEvent() public {
        uint256 amt0 = 500_000 * 1e18;
        uint256 amt1 = 500_000 * 1e18;

        vm.startPrank(alice);
        token0.transfer(address(pool), amt0);
        token1.transfer(address(pool), amt1);
        vm.stopPrank();

        vm.expectEmit(true, false, false, true);
        emit Mint(address(this), amt0, amt1);
        pool.mint(alice);
    }

    function test_SyncEmitsOnMint() public {
        uint256 amt0 = 100_000 * 1e18;
        uint256 amt1 = 200_000 * 1e18;

        vm.startPrank(alice);
        token0.transfer(address(pool), amt0);
        token1.transfer(address(pool), amt1);
        vm.stopPrank();

        vm.expectEmit(false, false, false, true);
        emit Sync(uint112(amt0), uint112(amt1));
        pool.mint(alice);
    }

    function test_SubsequentMint() public {
        // Seed pool with initial liquidity.
        uint256 init0 = 1_000_000 * 1e18;
        uint256 init1 = 1_000_000 * 1e18;
        _addLiquidity(alice, init0, init1);

        // Capture total supply and reserves BEFORE the second mint.
        uint256 totalBefore = pool.totalSupply();
        (uint112 r0Before, uint112 r1Before,) = pool.getReserves();

        // Bob adds proportional liquidity (50% of initial amounts).
        uint256 add0 = 500_000 * 1e18;
        uint256 add1 = 500_000 * 1e18;

        // Compute expected LP using the state that existed before the mint.
        uint256 expectedLp = Math.min(
            add0 * totalBefore / uint256(r0Before),
            add1 * totalBefore / uint256(r1Before)
        );

        uint256 bobLiquidity = _addLiquidity(bob, add0, add1);

        // Use approximate equality to handle integer rounding.
        assertApproxEqAbs(bobLiquidity, expectedLp, 1);
        assertGt(bobLiquidity, 0);
    }

    // -------------------------------------------------------------------------
    // Burn
    // -------------------------------------------------------------------------

    function test_Burn() public {
        uint256 amt0 = 1_000_000 * 1e18;
        uint256 amt1 = 1_000_000 * 1e18;
        uint256 liquidity = _addLiquidity(alice, amt0, amt1);

        // Alice sends LP tokens to pool then burns.
        vm.prank(alice);
        pool.transfer(address(pool), liquidity);

        uint256 token0Before = token0.balanceOf(alice);
        uint256 token1Before = token1.balanceOf(alice);

        (uint256 returned0, uint256 returned1) = pool.burn(alice);

        assertTrue(returned0 > 0);
        assertTrue(returned1 > 0);
        assertEq(token0.balanceOf(alice), token0Before + returned0);
        assertEq(token1.balanceOf(alice), token1Before + returned1);
    }

    function test_BurnEmitsEvent() public {
        uint256 amt0 = 1_000_000 * 1e18;
        uint256 amt1 = 1_000_000 * 1e18;
        uint256 liquidity = _addLiquidity(alice, amt0, amt1);

        vm.prank(alice);
        pool.transfer(address(pool), liquidity);

        (uint112 r0, uint112 r1,) = pool.getReserves();
        uint256 totalSupply_ = pool.totalSupply();
        uint256 expectedAmt0 = liquidity * uint256(r0) / totalSupply_;
        uint256 expectedAmt1 = liquidity * uint256(r1) / totalSupply_;

        vm.expectEmit(true, false, false, true, address(pool));
        emit Burn(address(this), expectedAmt0, expectedAmt1, alice);
        pool.burn(alice);
    }

    // -------------------------------------------------------------------------
    // Swap
    // -------------------------------------------------------------------------

    function test_SwapToken0ForToken1() public {
        // Seed pool.
        _addLiquidity(alice, 1_000_000 * 1e18, 1_000_000 * 1e18);

        (uint112 r0Before, uint112 r1Before,) = pool.getReserves();

        uint256 amountIn  = 10_000 * 1e18;
        uint256 amountOut = _getAmountOut(amountIn, r0Before, r1Before);

        // Send token0 to pool, then swap for token1 out.
        vm.startPrank(bob);
        token0.transfer(address(pool), amountIn);
        vm.stopPrank();

        uint256 bobToken1Before = token1.balanceOf(bob);
        pool.swap(0, amountOut, bob);

        assertEq(token1.balanceOf(bob), bobToken1Before + amountOut);

        (uint112 r0After, uint112 r1After,) = pool.getReserves();
        assertGt(r0After, r0Before);
        assertLt(r1After, r1Before);
    }

    function test_SwapToken1ForToken0() public {
        _addLiquidity(alice, 1_000_000 * 1e18, 1_000_000 * 1e18);

        (uint112 r0Before, uint112 r1Before,) = pool.getReserves();

        uint256 amountIn  = 10_000 * 1e18;
        uint256 amountOut = _getAmountOut(amountIn, r1Before, r0Before);

        vm.startPrank(bob);
        token1.transfer(address(pool), amountIn);
        vm.stopPrank();

        uint256 bobToken0Before = token0.balanceOf(bob);
        pool.swap(amountOut, 0, bob);

        assertEq(token0.balanceOf(bob), bobToken0Before + amountOut);
    }

    function test_SwapEmitsEvent() public {
        _addLiquidity(alice, 1_000_000 * 1e18, 1_000_000 * 1e18);

        (uint112 r0,uint112 r1,) = pool.getReserves();
        uint256 amountIn  = 5_000 * 1e18;
        uint256 amountOut = _getAmountOut(amountIn, r0, r1);

        vm.prank(bob);
        token0.transfer(address(pool), amountIn);

        vm.expectEmit(true, true, false, true);
        emit Swap(address(this), amountIn, 0, 0, amountOut, bob);
        pool.swap(0, amountOut, bob);
    }

    function test_RevertWhen_SwapInsufficientLiquidity() public {
        _addLiquidity(alice, 1_000_000 * 1e18, 1_000_000 * 1e18);

        (uint112 r0, uint112 r1,) = pool.getReserves();

        // Request more than available reserves.
        vm.expectRevert(UniswapPool.InsufficientLiquidity.selector);
        pool.swap(uint256(r0) + 1, 0, bob);

        vm.expectRevert(UniswapPool.InsufficientLiquidity.selector);
        pool.swap(0, uint256(r1) + 1, bob);
    }

    function test_RevertWhen_SwapKViolation() public {
        _addLiquidity(alice, 1_000_000 * 1e18, 1_000_000 * 1e18);

        (uint112 r0,,) = pool.getReserves();
        uint256 smallOut = uint256(r0) / 1000; // 0.1% of reserve

        // Send a tiny dust amount of token1 — far too little to cover the fee on smallOut.
        // amountIn = 1 wei, which fails the k-invariant check for a 0.1% output.
        vm.prank(bob);
        token1.transfer(address(pool), 1);

        vm.expectRevert(UniswapPool.KInvariantViolation.selector);
        pool.swap(smallOut, 0, bob);
    }

    function test_RevertWhen_SwapZeroOutput() public {
        _addLiquidity(alice, 1_000_000 * 1e18, 1_000_000 * 1e18);

        vm.expectRevert(UniswapPool.InsufficientOutputAmount.selector);
        pool.swap(0, 0, bob);
    }

    // -------------------------------------------------------------------------
    // TWAP price accumulator
    // -------------------------------------------------------------------------

    function test_PriceCumulativeAccumulates() public {
        _addLiquidity(alice, 1_000_000 * 1e18, 2_000_000 * 1e18);

        uint256 price0Before = pool.price0CumulativeLast();
        uint256 price1Before = pool.price1CumulativeLast();

        // Advance time and call sync to trigger accumulator update.
        vm.warp(block.timestamp + 1 hours);
        pool.sync();

        assertTrue(pool.price0CumulativeLast() > price0Before);
        assertTrue(pool.price1CumulativeLast() > price1Before);
    }

    // -------------------------------------------------------------------------
    // Skim
    // -------------------------------------------------------------------------

    function test_Skim() public {
        _addLiquidity(alice, 1_000_000 * 1e18, 1_000_000 * 1e18);

        uint256 extraToken0 = 5_000 * 1e18;
        uint256 extraToken1 = 3_000 * 1e18;

        // Send tokens directly (bypass mint).
        vm.prank(bob);
        token0.transfer(address(pool), extraToken0);
        vm.prank(bob);
        token1.transfer(address(pool), extraToken1);

        uint256 charlieToken0Before = token0.balanceOf(charlie);
        uint256 charlieToken1Before = token1.balanceOf(charlie);

        pool.skim(charlie);

        assertEq(token0.balanceOf(charlie), charlieToken0Before + extraToken0);
        assertEq(token1.balanceOf(charlie), charlieToken1Before + extraToken1);
    }

    // -------------------------------------------------------------------------
    // Fuzz tests
    // -------------------------------------------------------------------------

    function testFuzz_SwapMaintainsK(uint256 amountIn) public {
        // Seed with significant liquidity.
        _addLiquidity(alice, 1_000_000 * 1e18, 1_000_000 * 1e18);

        (uint112 r0, uint112 r1,) = pool.getReserves();

        // Bound amountIn to between 1 wei and 1% of reserve to keep swap valid.
        amountIn = bound(amountIn, 1, uint256(r0) / 100);

        uint256 amountOut = _getAmountOut(amountIn, r0, r1);
        // If output rounds down to 0, skip.
        vm.assume(amountOut > 0);

        uint256 kBefore = uint256(r0) * uint256(r1);

        vm.prank(bob);
        token0.transfer(address(pool), amountIn);
        pool.swap(0, amountOut, bob);

        (uint112 r0After, uint112 r1After,) = pool.getReserves();
        uint256 kAfter = uint256(r0After) * uint256(r1After);

        // k must not decrease after a valid swap (fees increase k).
        assertGe(kAfter, kBefore);
    }

    function testFuzz_MintBurn(uint256 amt0, uint256 amt1) public {
        amt0 = bound(amt0, 1e15, 1e24);
        amt1 = bound(amt1, 1e15, 1e24);

        // Ensure alice has enough tokens.
        deal(address(token0), alice, amt0);
        deal(address(token1), alice, amt1);

        vm.startPrank(alice);
        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        uint256 sqrt_ = _sqrt(amt0 * amt1);
        // Skip if first mint would produce 0 LP (too little liquidity).
        vm.assume(sqrt_ > pool.MINIMUM_LIQUIDITY());

        uint256 token0Before = token0.balanceOf(alice);
        uint256 token1Before = token1.balanceOf(alice);

        // Add liquidity.
        uint256 liquidity = _addLiquidity(alice, amt0, amt1);
        assertTrue(liquidity > 0);

        // Remove liquidity.
        vm.prank(alice);
        pool.transfer(address(pool), liquidity);
        (uint256 returned0, uint256 returned1) = pool.burn(alice);

        // Alice should get back close to what she put in (minus MINIMUM_LIQUIDITY share).
        // Allow up to 0.1% deviation for rounding and the locked minimum.
        assertApproxEqRel(token0.balanceOf(alice), token0Before, 0.001e18);
        assertApproxEqRel(token1.balanceOf(alice), token1Before, 0.001e18);

        // Returned amounts must be non-zero.
        assertTrue(returned0 > 0);
        assertTrue(returned1 > 0);
    }

    // -------------------------------------------------------------------------
    // Internal math helper (mirrors OZ Math.sqrt for test comparison)
    // -------------------------------------------------------------------------

    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}

// Bring Math.min into scope for test_SubsequentMint.
import "@openzeppelin/contracts/utils/math/Math.sol";
