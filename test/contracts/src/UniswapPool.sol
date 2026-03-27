// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title UniswapPool
 * @notice Uniswap V2-style constant-product AMM pool.
 *
 * Liquidity providers deposit token0 and token1 in the current reserve ratio
 * and receive LP tokens representing their share of the pool. Swappers send
 * one token to the contract then call `swap`, paying a 0.3% fee enforced via
 * the k-invariant check on adjusted balances.
 *
 * TWAP price accumulators are updated every time reserves change, following
 * the original Uniswap V2 oracle design (overflow-safe via unchecked arithmetic
 * on uint256 accumulators).
 *
 * Simplifications vs. production Uniswap V2:
 *  - No flash-loan callback.
 *  - No factory / fee-to split.
 *  - No permit on LP tokens.
 */
contract UniswapPool is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // Custom errors
    // -------------------------------------------------------------------------

    error InsufficientLiquidity();
    error InsufficientInputAmount();
    error InsufficientOutputAmount();
    error InvalidTo();
    error Overflow();
    error InsufficientLiquidityMinted();
    error InsufficientLiquidityBurned();
    error KInvariantViolation();

    // -------------------------------------------------------------------------
    // Events
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
    // Constants
    // -------------------------------------------------------------------------

    /// @notice Minimum LP tokens permanently locked to the dead address on
    ///         the first mint to prevent pool price manipulation.
    uint256 public constant MINIMUM_LIQUIDITY = 1000;

    /// @dev Dead address used to permanently lock MINIMUM_LIQUIDITY.
    address private constant DEAD = address(0xdead);

    // -------------------------------------------------------------------------
    // Immutables
    // -------------------------------------------------------------------------

    /// @notice First token of the pair (address-sorted: token0 < token1).
    IERC20 public immutable token0;

    /// @notice Second token of the pair.
    IERC20 public immutable token1;

    // -------------------------------------------------------------------------
    // Reserve state
    // -------------------------------------------------------------------------

    uint112 private _reserve0;
    uint112 private _reserve1;
    uint32  private _blockTimestampLast;

    // -------------------------------------------------------------------------
    // TWAP accumulators
    // -------------------------------------------------------------------------

    /// @notice Cumulative price of token0 in terms of token1 (UQ112x112, seconds).
    uint256 public price0CumulativeLast;

    /// @notice Cumulative price of token1 in terms of token0 (UQ112x112, seconds).
    uint256 public price1CumulativeLast;

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /**
     * @param tokenA First token address (will be sorted).
     * @param tokenB Second token address (will be sorted).
     */
    constructor(address tokenA, address tokenB)
        ERC20("UniswapPool LP", "UNI-V2")
    {
        require(tokenA != tokenB, "UniswapPool: IDENTICAL_ADDRESSES");
        require(tokenA != address(0) && tokenB != address(0), "UniswapPool: ZERO_ADDRESS");
        // Sort tokens by address for canonical ordering.
        (token0, token1) = tokenA < tokenB
            ? (IERC20(tokenA), IERC20(tokenB))
            : (IERC20(tokenB), IERC20(tokenA));
    }

    // -------------------------------------------------------------------------
    // Views
    // -------------------------------------------------------------------------

    /**
     * @notice Current reserve snapshot.
     * @return reserve0_           Current token0 reserve.
     * @return reserve1_           Current token1 reserve.
     * @return blockTimestampLast_ Timestamp of the last reserve update.
     */
    function getReserves()
        public
        view
        returns (uint112 reserve0_, uint112 reserve1_, uint32 blockTimestampLast_)
    {
        reserve0_ = _reserve0;
        reserve1_ = _reserve1;
        blockTimestampLast_ = _blockTimestampLast;
    }

    // -------------------------------------------------------------------------
    // Core AMM logic
    // -------------------------------------------------------------------------

    /**
     * @notice Add liquidity to the pool.
     *
     * Caller must transfer token0 and token1 to this contract before calling
     * `mint`. The LP tokens minted are proportional to the contributed amounts
     * relative to current reserves.  On first mint, `MINIMUM_LIQUIDITY` LP
     * tokens are burned to the dead address.
     *
     * @param to Recipient of the minted LP tokens.
     * @return liquidity Amount of LP tokens minted.
     */
    function mint(address to) external nonReentrant returns (uint256 liquidity) {
        (uint112 reserve0_, uint112 reserve1_,) = getReserves();
        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));
        uint256 amount0 = balance0 - reserve0_;
        uint256 amount1 = balance1 - reserve1_;

        uint256 totalSupply_ = totalSupply();
        if (totalSupply_ == 0) {
            // First mint: geometric mean minus the permanently locked minimum.
            uint256 product = amount0 * amount1;
            liquidity = Math.sqrt(product) - MINIMUM_LIQUIDITY;
            // Permanently lock MINIMUM_LIQUIDITY to prevent price manipulation.
            _mint(DEAD, MINIMUM_LIQUIDITY);
        } else {
            liquidity = Math.min(
                amount0 * totalSupply_ / reserve0_,
                amount1 * totalSupply_ / reserve1_
            );
        }

        if (liquidity == 0) revert InsufficientLiquidityMinted();
        _mint(to, liquidity);

        _update(balance0, balance1, reserve0_, reserve1_);
        emit Mint(msg.sender, amount0, amount1);
    }

    /**
     * @notice Remove liquidity from the pool.
     *
     * Caller must transfer LP tokens to this contract before calling `burn`.
     * The tokens returned are proportional to the LP share burned.
     *
     * @param to Recipient of the returned tokens.
     * @return amount0 Amount of token0 returned.
     * @return amount1 Amount of token1 returned.
     */
    function burn(address to)
        external
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        (uint112 reserve0_, uint112 reserve1_,) = getReserves();
        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));
        uint256 liquidity = balanceOf(address(this));

        uint256 totalSupply_ = totalSupply();
        amount0 = liquidity * balance0 / totalSupply_;
        amount1 = liquidity * balance1 / totalSupply_;

        if (amount0 == 0 || amount1 == 0) revert InsufficientLiquidityBurned();

        _burn(address(this), liquidity);
        token0.safeTransfer(to, amount0);
        token1.safeTransfer(to, amount1);

        balance0 = token0.balanceOf(address(this));
        balance1 = token1.balanceOf(address(this));

        _update(balance0, balance1, reserve0_, reserve1_);
        emit Burn(msg.sender, amount0, amount1, to);
    }

    /**
     * @notice Swap tokens.
     *
     * Caller must send the input token to this contract before calling `swap`.
     * The 0.3% fee is enforced via the k-invariant check on adjusted balances:
     *
     *   adjustedBalance = balance * 1000 - amountIn * 3
     *
     * @param amount0Out Amount of token0 to send to `to` (0 if swapping token0→token1).
     * @param amount1Out Amount of token1 to send to `to` (0 if swapping token1→token0).
     * @param to         Recipient of the output tokens.
     */
    function swap(uint256 amount0Out, uint256 amount1Out, address to)
        external
        nonReentrant
    {
        if (amount0Out == 0 && amount1Out == 0) revert InsufficientOutputAmount();

        (uint112 reserve0_, uint112 reserve1_,) = getReserves();
        if (amount0Out >= reserve0_ || amount1Out >= reserve1_) revert InsufficientLiquidity();
        if (to == address(token0) || to == address(token1)) revert InvalidTo();

        // Send output tokens.
        if (amount0Out > 0) token0.safeTransfer(to, amount0Out);
        if (amount1Out > 0) token1.safeTransfer(to, amount1Out);

        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));

        // Determine how many input tokens were received.
        uint256 amount0In = balance0 > reserve0_ - amount0Out
            ? balance0 - (reserve0_ - amount0Out)
            : 0;
        uint256 amount1In = balance1 > reserve1_ - amount1Out
            ? balance1 - (reserve1_ - amount1Out)
            : 0;

        if (amount0In == 0 && amount1In == 0) revert InsufficientInputAmount();

        // Enforce k-invariant with 0.3% fee deducted from input.
        {
            uint256 balance0Adjusted = balance0 * 1000 - amount0In * 3;
            uint256 balance1Adjusted = balance1 * 1000 - amount1In * 3;
            uint256 kBefore = uint256(reserve0_) * uint256(reserve1_) * 1_000_000;
            if (balance0Adjusted * balance1Adjusted < kBefore) revert KInvariantViolation();
        }

        _update(balance0, balance1, reserve0_, reserve1_);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    /**
     * @notice Sweep excess token balances (above current reserves) to `to`.
     *
     * Useful for recovering tokens accidentally sent to the pool or fees
     * accumulated via small rounding differences.
     *
     * @param to Recipient of excess tokens.
     */
    function skim(address to) external nonReentrant {
        (uint112 reserve0_, uint112 reserve1_,) = getReserves();
        uint256 excess0 = token0.balanceOf(address(this)) - reserve0_;
        uint256 excess1 = token1.balanceOf(address(this)) - reserve1_;
        if (excess0 > 0) token0.safeTransfer(to, excess0);
        if (excess1 > 0) token1.safeTransfer(to, excess1);
    }

    /**
     * @notice Force reserves to match current token balances.
     *
     * Useful after tokens are donated directly to the pool without going
     * through `mint`.
     */
    function sync() external nonReentrant {
        (uint112 reserve0_, uint112 reserve1_,) = getReserves();
        _update(token0.balanceOf(address(this)), token1.balanceOf(address(this)), reserve0_, reserve1_);
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    /**
     * @dev Update reserves and TWAP price accumulators.
     *
     * The time-weighted price is accumulated by multiplying the current
     * reserve ratio by the elapsed seconds since the last update. Integer
     * overflow is intentional and handled via unchecked arithmetic (matching
     * the original Uniswap V2 oracle design).
     *
     * @param balance0  Current token0 balance of this contract.
     * @param balance1  Current token1 balance of this contract.
     * @param reserve0_ Reserve0 at the start of the current transaction.
     * @param reserve1_ Reserve1 at the start of the current transaction.
     */
    function _update(
        uint256 balance0,
        uint256 balance1,
        uint112 reserve0_,
        uint112 reserve1_
    ) private {
        if (balance0 > type(uint112).max || balance1 > type(uint112).max) revert Overflow();

        uint32 blockTimestamp = uint32(block.timestamp);
        uint32 timeElapsed;
        unchecked {
            timeElapsed = blockTimestamp - _blockTimestampLast;
        }

        if (timeElapsed > 0 && reserve0_ > 0 && reserve1_ > 0) {
            // UQ112x112 fixed-point: multiply reserve by 2^112 then divide.
            // We approximate by scaling to avoid 224-bit arithmetic:
            // price = (reserve_denominator * 1e18) / reserve_numerator * timeElapsed
            // This is sufficient for indexer testing purposes.
            unchecked {
                price0CumulativeLast += (uint256(reserve1_) * 1e18 / uint256(reserve0_)) * timeElapsed;
                price1CumulativeLast += (uint256(reserve0_) * 1e18 / uint256(reserve1_)) * timeElapsed;
            }
        }

        _reserve0 = uint112(balance0);
        _reserve1 = uint112(balance1);
        _blockTimestampLast = blockTimestamp;

        emit Sync(uint112(balance0), uint112(balance1));
    }
}
