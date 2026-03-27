// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/TestToken.sol";
import "../src/StakingPool.sol";
import "../src/UniswapPool.sol";

/**
 * @title GenerateStakingEvents
 * @notice Generates a rich set of on-chain events for the eth-indexer test
 *         environment by interacting with StakingPool and UniswapPool.
 *
 * Event targets (approximate):
 *   StakingPool:
 *     1  × RewardAdded   (notifyRewardAmount)
 *     30 × Staked        (3 users × 10 rounds)
 *     ~10 × Withdrawn    (users withdraw partial amounts)
 *     ~10 × RewardPaid   (users call getReward / exit)
 *
 *   UniswapPool:
 *     1  × initial Mint  (deployer seeds liquidity)
 *     ~5 × Mint          (users add liquidity)
 *     ~20 × Swap         (alternating direction)
 *     ~5 × Burn          (users remove liquidity)
 *
 * Required environment variables:
 *   MNEMONIC         — BIP-39 mnemonic (same one used by Anvil)
 *   STAKING_ADDRESS  — deployed StakingPool address
 *   POOL_ADDRESS     — deployed UniswapPool address
 *   TOKEN1_ADDRESS   — staking token / first token in pair
 *   TOKEN2_ADDRESS   — rewards token / second token in pair
 *
 * NOTE: vm.warp is not available during broadcast. Rewards only accrue as
 * blocks advance. For richer RewardPaid events wrap this script in a shell
 * that calls anvil_increaseTime between phases.
 */
contract GenerateStakingEvents is Script {
    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    uint256 constant REWARD_FUND    = 100_000 * 1e18;
    uint256 constant STAKE_UNIT     = 1_000   * 1e18;
    uint256 constant SWAP_UNIT      = 10_000  * 1e18;
    uint256 constant LIQUIDITY_UNIT = 100_000 * 1e18;

    // -------------------------------------------------------------------------
    // Shared state (set once in run, read by helpers)
    // -------------------------------------------------------------------------

    StakingPool internal _staking;
    UniswapPool internal _pool;
    TestToken   internal _token1;
    TestToken   internal _token2;

    uint256     internal _deployerKey;
    uint256[3]  internal _userKeys;
    address[3]  internal _users;

    IERC20 internal _poolToken0;
    IERC20 internal _poolToken1;

    // -------------------------------------------------------------------------
    // Entrypoint
    // -------------------------------------------------------------------------

    function run() external {
        _loadEnv();
        _phase1_distributeAndFund();
        _phase2_approvals();
        _phase3_stakeEvents();
        _phase4_withdrawEvents();
        _phase5_rewardEvents();
        _phase6_poolMintEvents();
        _phase7_swapEvents();
        _phase8_burnEvents();
        console.log("GenerateStakingEvents: all transactions broadcast.");
    }

    // -------------------------------------------------------------------------
    // Phase helpers
    // -------------------------------------------------------------------------

    function _loadEnv() internal {
        string memory mnemonic = vm.envString("MNEMONIC");

        _staking    = StakingPool(vm.envAddress("STAKING_ADDRESS"));
        _pool       = UniswapPool(vm.envAddress("POOL_ADDRESS"));
        _token1     = TestToken(vm.envAddress("TOKEN1_ADDRESS"));
        _token2     = TestToken(vm.envAddress("TOKEN2_ADDRESS"));

        _deployerKey  = vm.deriveKey(mnemonic, 0);
        _userKeys[0]  = vm.deriveKey(mnemonic, 1);
        _userKeys[1]  = vm.deriveKey(mnemonic, 2);
        _userKeys[2]  = vm.deriveKey(mnemonic, 3);
        _users[0]     = vm.addr(_userKeys[0]);
        _users[1]     = vm.addr(_userKeys[1]);
        _users[2]     = vm.addr(_userKeys[2]);

        _poolToken0 = _pool.token0();
        _poolToken1 = _pool.token1();
    }

    /// @dev Distributes tokens to users, funds the staking reward period,
    ///      and seeds the pool with initial liquidity.
    function _phase1_distributeAndFund() internal {
        vm.startBroadcast(_deployerKey);

        // Give each user generous allocations of both tokens.
        for (uint256 i = 0; i < 3; i++) {
            _token1.transfer(_users[i], 500_000 * 1e18);
            _token2.transfer(_users[i], 500_000 * 1e18);
        }

        // Fund the staking pool and notify a reward period.
        _token2.approve(address(_staking), REWARD_FUND);
        _token2.transfer(address(_staking), REWARD_FUND);
        _staking.notifyRewardAmount(REWARD_FUND);
        // Emits: RewardAdded(REWARD_FUND)

        // Seed initial pool liquidity (equal amounts of each token).
        _poolToken0.transfer(address(_pool), LIQUIDITY_UNIT);
        _poolToken1.transfer(address(_pool), LIQUIDITY_UNIT);
        _pool.mint(vm.addr(_deployerKey));
        // Emits: Mint + Sync

        vm.stopBroadcast();
    }

    /// @dev Each user approves the staking pool and AMM pool for both tokens.
    function _phase2_approvals() internal {
        for (uint256 i = 0; i < 3; i++) {
            vm.startBroadcast(_userKeys[i]);
            _token1.approve(address(_staking), type(uint256).max);
            _token1.approve(address(_pool),    type(uint256).max);
            _token2.approve(address(_pool),    type(uint256).max);
            IERC20(address(_poolToken0)).approve(address(_pool), type(uint256).max);
            IERC20(address(_poolToken1)).approve(address(_pool), type(uint256).max);
            vm.stopBroadcast();
        }
    }

    /// @dev Generates ~30 Staked events: 3 users × 10 rounds with varying amounts.
    function _phase3_stakeEvents() internal {
        for (uint256 round = 0; round < 10; round++) {
            for (uint256 i = 0; i < 3; i++) {
                uint256 amount = STAKE_UNIT * (i + 1) * (round + 1);
                vm.broadcast(_userKeys[i]);
                _staking.stake(amount);
                // Emits: Staked(users[i], amount)
            }
        }
    }

    /// @dev Generates ~10 Withdrawn events: each user withdraws ~20% of their
    ///      balance twice.
    function _phase4_withdrawEvents() internal {
        for (uint256 round = 0; round < 2; round++) {
            for (uint256 i = 0; i < 3; i++) {
                uint256 balance = _staking.balanceOf(_users[i]);
                if (balance == 0) continue;
                uint256 withdrawAmt = balance / 5;
                if (withdrawAmt == 0) continue;
                vm.broadcast(_userKeys[i]);
                _staking.withdraw(withdrawAmt);
                // Emits: Withdrawn(users[i], withdrawAmt)
            }
        }
    }

    /// @dev Generates ~10 RewardPaid events across multiple claim rounds.
    ///      Includes one exit() call (Withdrawn + RewardPaid for user[0]).
    function _phase5_rewardEvents() internal {
        // Round 1: all three users claim whatever has accrued.
        for (uint256 i = 0; i < 3; i++) {
            if (_staking.earned(_users[i]) > 0) {
                vm.broadcast(_userKeys[i]);
                _staking.getReward();
                // Emits: RewardPaid(users[i], reward)
            }
        }

        // Each user stakes more to keep earning.
        for (uint256 i = 0; i < 3; i++) {
            vm.broadcast(_userKeys[i]);
            _staking.stake(STAKE_UNIT * (i + 2));
        }

        // Round 2: claim after extra stakes.
        for (uint256 i = 0; i < 3; i++) {
            if (_staking.earned(_users[i]) > 0) {
                vm.broadcast(_userKeys[i]);
                _staking.getReward();
            }
        }

        // user[0]: full exit (Withdrawn + RewardPaid in one tx).
        if (_staking.balanceOf(_users[0]) > 0) {
            vm.broadcast(_userKeys[0]);
            _staking.exit();
            // Emits: Withdrawn + RewardPaid
        }

        // Rounds 3-4: remaining users claim twice more.
        for (uint256 round = 0; round < 2; round++) {
            for (uint256 i = 1; i < 3; i++) {
                if (_staking.earned(_users[i]) > 0) {
                    vm.broadcast(_userKeys[i]);
                    _staking.getReward();
                }
            }
        }
    }

    /// @dev Generates ~5 additional Mint events: users add proportional liquidity.
    function _phase6_poolMintEvents() internal {
        // users[0] and users[1] add liquidity in two rounds.
        for (uint256 round = 0; round < 2; round++) {
            for (uint256 i = 0; i < 2; i++) {
                _userAddLiquidity(_userKeys[i], _users[i], round);
            }
        }

        // users[2] adds once.
        _userAddLiquidity(_userKeys[2], _users[2], 2);
    }

    /// @dev Internal helper used by _phase6 to avoid stack depth issues.
    function _userAddLiquidity(uint256 key, address user, uint256 round) internal {
        (uint112 r0, uint112 r1,) = _pool.getReserves();
        if (r0 == 0 || r1 == 0) return;

        uint256 addAmt0 = LIQUIDITY_UNIT / (round + 2);
        uint256 addAmt1 = addAmt0 * uint256(r1) / uint256(r0);
        if (addAmt1 == 0) return;

        vm.startBroadcast(key);
        _poolToken0.transfer(address(_pool), addAmt0);
        _poolToken1.transfer(address(_pool), addAmt1);
        vm.stopBroadcast();

        _pool.mint(user);
        // Emits: Mint + Sync
    }

    /// @dev Generates ~20 Swap events alternating between both swap directions.
    function _phase7_swapEvents() internal {
        for (uint256 swapRound = 0; swapRound < 20; swapRound++) {
            (uint112 r0, uint112 r1,) = _pool.getReserves();
            if (r0 == 0 || r1 == 0) break;

            uint256 userIdx  = swapRound % 3;
            bool    dirFwd   = (swapRound % 2 == 0); // true: token0→token1
            uint256 amtIn    = SWAP_UNIT * (swapRound % 3 + 1);

            if (dirFwd) {
                _swapToken0For1(_userKeys[userIdx], _users[userIdx], amtIn, r0, r1);
            } else {
                _swapToken1For0(_userKeys[userIdx], _users[userIdx], amtIn, r0, r1);
            }
        }
    }

    function _swapToken0For1(
        uint256 key,
        address user,
        uint256 amtIn,
        uint112 r0,
        uint112 r1
    ) internal {
        uint256 amtOut = _getAmountOut(amtIn, r0, r1);
        if (amtOut == 0 || amtOut >= r1) return;

        vm.startBroadcast(key);
        _poolToken0.transfer(address(_pool), amtIn);
        vm.stopBroadcast();

        _pool.swap(0, amtOut, user);
        // Emits: Swap + Sync
    }

    function _swapToken1For0(
        uint256 key,
        address user,
        uint256 amtIn,
        uint112 r0,
        uint112 r1
    ) internal {
        uint256 amtOut = _getAmountOut(amtIn, r1, r0);
        if (amtOut == 0 || amtOut >= r0) return;

        vm.startBroadcast(key);
        _poolToken1.transfer(address(_pool), amtIn);
        vm.stopBroadcast();

        _pool.swap(amtOut, 0, user);
        // Emits: Swap + Sync
    }

    /// @dev Generates ~5 Burn events: each of the three users burns half their
    ///      LP balance, plus deployer and user[0] burn additional positions.
    function _phase8_burnEvents() internal {
        // Three users each burn half.
        for (uint256 i = 0; i < 3; i++) {
            _burnHalf(_userKeys[i], _users[i]);
        }

        // Deployer burns one-third.
        address deployer = vm.addr(_deployerKey);
        uint256 deployerLp = _pool.balanceOf(deployer);
        if (deployerLp > 0) {
            uint256 burnAmt = deployerLp / 3;
            if (burnAmt > 0) {
                vm.startBroadcast(_deployerKey);
                _pool.transfer(address(_pool), burnAmt);
                vm.stopBroadcast();
                _pool.burn(deployer);
                // Emits: Burn + Sync
            }
        }

        // user[0] burns remaining LP.
        uint256 remaining = _pool.balanceOf(_users[0]);
        if (remaining > 0) {
            vm.startBroadcast(_userKeys[0]);
            _pool.transfer(address(_pool), remaining);
            vm.stopBroadcast();
            _pool.burn(_users[0]);
            // Emits: Burn + Sync
        }
    }

    function _burnHalf(uint256 key, address user) internal {
        uint256 lpBalance = _pool.balanceOf(user);
        if (lpBalance == 0) return;
        uint256 burnAmt = lpBalance / 2;
        if (burnAmt == 0) return;

        vm.startBroadcast(key);
        _pool.transfer(address(_pool), burnAmt);
        vm.stopBroadcast();

        _pool.burn(user);
        // Emits: Burn + Sync
    }

    // -------------------------------------------------------------------------
    // Internal math helper
    // -------------------------------------------------------------------------

    /// @dev Uniswap V2 output amount formula including 0.3% fee.
    function _getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) return 0;
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator       = amountInWithFee * reserveOut;
        uint256 denominator     = reserveIn * 1000 + amountInWithFee;
        return numerator / denominator;
    }
}
