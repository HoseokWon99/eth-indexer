// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/TestToken.sol";
import "../src/StakingPool.sol";

/**
 * @title StakingPoolTest
 * @notice Comprehensive Foundry test suite for StakingPool.
 *
 * Coverage:
 *  - Initial state verification
 *  - Stake / withdraw happy paths and event emission
 *  - Revert conditions (ZeroAmount, InsufficientBalance)
 *  - Reward accrual, claiming, and exit
 *  - Multi-staker proportional reward distribution
 *  - Owner management (notifyRewardAmount, setRewardsDuration)
 *  - Fuzz tests for stake/withdraw and proportional rewards
 *  - Invariant helper asserting totalSupply == sum of balances
 */
contract StakingPoolTest is Test {
    // -------------------------------------------------------------------------
    // Events (redeclared for use with vm.expectEmit)
    // -------------------------------------------------------------------------

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);
    event Recovered(address token, uint256 amount);

    // -------------------------------------------------------------------------
    // Constants / actors
    // -------------------------------------------------------------------------

    address public constant alice   = address(0x1111111111111111111111111111111111111111);
    address public constant bob     = address(0x2222222222222222222222222222222222222222);
    address public constant charlie = address(0x3333333333333333333333333333333333333333);

    uint256 public constant INITIAL_MINT    = 1_000_000 * 1e18;
    uint256 public constant REWARD_AMOUNT   = 100_000  * 1e18;
    uint256 public constant REWARDS_DURATION = 7 days;

    // -------------------------------------------------------------------------
    // Contracts under test
    // -------------------------------------------------------------------------

    TestToken   public stakingToken;
    TestToken   public rewardsToken;
    StakingPool public pool;

    // -------------------------------------------------------------------------
    // setUp
    // -------------------------------------------------------------------------

    function setUp() public {
        // Deploy tokens.
        stakingToken = new TestToken("Staking Token", "STK", INITIAL_MINT * 10);
        rewardsToken = new TestToken("Rewards Token", "RWD", INITIAL_MINT * 10);

        // Deploy pool.
        pool = new StakingPool(address(stakingToken), address(rewardsToken));

        // Distribute staking tokens to users.
        stakingToken.transfer(alice,   INITIAL_MINT);
        stakingToken.transfer(bob,     INITIAL_MINT);
        stakingToken.transfer(charlie, INITIAL_MINT);

        // Users approve pool.
        vm.prank(alice);
        stakingToken.approve(address(pool), type(uint256).max);
        vm.prank(bob);
        stakingToken.approve(address(pool), type(uint256).max);
        vm.prank(charlie);
        stakingToken.approve(address(pool), type(uint256).max);

        // Fund and start a reward period (owner = address(this)).
        rewardsToken.transfer(address(pool), REWARD_AMOUNT);
        pool.notifyRewardAmount(REWARD_AMOUNT);
    }

    // -------------------------------------------------------------------------
    // Helper
    // -------------------------------------------------------------------------

    /// @dev Stake `amount` of staking tokens from `user`.
    function _stake(address user, uint256 amount) internal {
        vm.prank(user);
        pool.stake(amount);
    }

    // -------------------------------------------------------------------------
    // Initial state
    // -------------------------------------------------------------------------

    function test_InitialState() public view {
        assertEq(address(pool.stakingToken()),  address(stakingToken));
        assertEq(address(pool.rewardsToken()),  address(rewardsToken));
        assertEq(pool.rewardsDuration(),        REWARDS_DURATION);
        assertEq(pool.totalSupply(),            0);
        assertEq(pool.rewardRate(),             REWARD_AMOUNT / REWARDS_DURATION);
        assertTrue(pool.periodFinish() > block.timestamp);
    }

    // -------------------------------------------------------------------------
    // Stake
    // -------------------------------------------------------------------------

    function test_Stake() public {
        uint256 amount = 1000 * 1e18;
        _stake(alice, amount);

        assertEq(pool.balanceOf(alice), amount);
        assertEq(pool.totalSupply(),    amount);
        assertEq(stakingToken.balanceOf(address(pool)), amount);
        assertEq(stakingToken.balanceOf(alice), INITIAL_MINT - amount);
    }

    function test_StakeEmitsEvent() public {
        uint256 amount = 500 * 1e18;
        vm.expectEmit(true, true, false, true);
        emit Staked(alice, amount);
        _stake(alice, amount);
    }

    function test_RevertWhen_StakeZero() public {
        vm.prank(alice);
        vm.expectRevert(StakingPool.ZeroAmount.selector);
        pool.stake(0);
    }

    // -------------------------------------------------------------------------
    // Withdraw
    // -------------------------------------------------------------------------

    function test_Withdraw() public {
        uint256 stakeAmount = 1000 * 1e18;
        _stake(alice, stakeAmount);

        uint256 withdrawAmount = 600 * 1e18;
        vm.prank(alice);
        pool.withdraw(withdrawAmount);

        assertEq(pool.balanceOf(alice), stakeAmount - withdrawAmount);
        assertEq(pool.totalSupply(),    stakeAmount - withdrawAmount);
        assertEq(stakingToken.balanceOf(alice), INITIAL_MINT - stakeAmount + withdrawAmount);
    }

    function test_WithdrawEmitsEvent() public {
        uint256 amount = 300 * 1e18;
        _stake(alice, amount);

        vm.expectEmit(true, true, false, true);
        emit Withdrawn(alice, amount);
        vm.prank(alice);
        pool.withdraw(amount);
    }

    function test_RevertWhen_WithdrawZero() public {
        _stake(alice, 100 * 1e18);
        vm.prank(alice);
        vm.expectRevert(StakingPool.ZeroAmount.selector);
        pool.withdraw(0);
    }

    function test_RevertWhen_WithdrawTooMuch() public {
        uint256 stakeAmount = 100 * 1e18;
        _stake(alice, stakeAmount);

        vm.prank(alice);
        vm.expectRevert(StakingPool.InsufficientBalance.selector);
        pool.withdraw(stakeAmount + 1);
    }

    // -------------------------------------------------------------------------
    // Reward accrual
    // -------------------------------------------------------------------------

    function test_RewardAccrual() public {
        _stake(alice, 1000 * 1e18);
        assertEq(pool.earned(alice), 0);

        vm.warp(block.timestamp + 1 days);
        assertTrue(pool.earned(alice) > 0);
    }

    function test_GetReward() public {
        uint256 stakeAmount = 1000 * 1e18;
        _stake(alice, stakeAmount);

        vm.warp(block.timestamp + 3 days);

        uint256 expectedReward = pool.earned(alice);
        assertTrue(expectedReward > 0);

        uint256 balanceBefore = rewardsToken.balanceOf(alice);

        vm.expectEmit(true, true, false, true);
        emit RewardPaid(alice, expectedReward);
        vm.prank(alice);
        pool.getReward();

        assertEq(rewardsToken.balanceOf(alice), balanceBefore + expectedReward);
        assertEq(pool.earned(alice), 0);
    }

    function test_Exit() public {
        uint256 stakeAmount = 1000 * 1e18;
        _stake(alice, stakeAmount);

        vm.warp(block.timestamp + 2 days);

        uint256 earnedBefore = pool.earned(alice);
        assertTrue(earnedBefore > 0);

        uint256 stakingBefore = stakingToken.balanceOf(alice);
        uint256 rewardBefore  = rewardsToken.balanceOf(alice);

        vm.prank(alice);
        pool.exit();

        // All staking tokens returned.
        assertEq(stakingToken.balanceOf(alice), stakingBefore + stakeAmount);
        // Rewards received (approximate: earned value may change slightly due to block.timestamp same tx).
        assertTrue(rewardsToken.balanceOf(alice) > rewardBefore);
        // Pool balance cleared.
        assertEq(pool.balanceOf(alice), 0);
        assertEq(pool.earned(alice),    0);
    }

    // -------------------------------------------------------------------------
    // Multiple stakers — proportional reward distribution
    // -------------------------------------------------------------------------

    function test_MultipleStakers() public {
        // Alice stakes 3x more than bob.
        _stake(alice, 3000 * 1e18);
        _stake(bob,   1000 * 1e18);

        vm.warp(block.timestamp + 7 days);

        uint256 aliceEarned = pool.earned(alice);
        uint256 bobEarned   = pool.earned(bob);

        // Alice should earn approximately 3x what bob earns.
        // Allow 1% tolerance for integer rounding.
        assertApproxEqRel(aliceEarned, bobEarned * 3, 0.01e18);
    }

    // -------------------------------------------------------------------------
    // notifyRewardAmount
    // -------------------------------------------------------------------------

    function test_NotifyRewardAmount() public {
        // Finish current period.
        vm.warp(block.timestamp + 7 days + 1);
        pool.setRewardsDuration(7 days);

        uint256 newReward = 50_000 * 1e18;
        rewardsToken.transfer(address(pool), newReward);

        vm.expectEmit(false, false, false, true);
        emit RewardAdded(newReward);
        pool.notifyRewardAmount(newReward);

        assertGt(pool.rewardRate(), 0);
        assertEq(pool.rewardRate(), newReward / 7 days);
    }

    // -------------------------------------------------------------------------
    // setRewardsDuration
    // -------------------------------------------------------------------------

    function test_SetRewardsDuration() public {
        // Let current period finish.
        vm.warp(block.timestamp + 7 days + 1);

        uint256 newDuration = 14 days;
        vm.expectEmit(false, false, false, true);
        emit RewardsDurationUpdated(newDuration);
        pool.setRewardsDuration(newDuration);

        assertEq(pool.rewardsDuration(), newDuration);
    }

    function test_RevertWhen_SetDurationDuringPeriod() public {
        // Period is still active (setUp started one).
        vm.expectRevert(StakingPool.PeriodNotFinished.selector);
        pool.setRewardsDuration(14 days);
    }

    // -------------------------------------------------------------------------
    // Fuzz tests
    // -------------------------------------------------------------------------

    function testFuzz_StakeWithdraw(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);

        _stake(alice, amount);

        assertEq(pool.balanceOf(alice), amount);
        assertEq(pool.totalSupply(),    amount);

        vm.prank(alice);
        pool.withdraw(amount);

        assertEq(pool.balanceOf(alice), 0);
        assertEq(pool.totalSupply(),    0);
        // Alice recovers her full stake.
        assertEq(stakingToken.balanceOf(alice), INITIAL_MINT);
    }

    function testFuzz_RewardProportional(uint256 aliceAmt, uint256 bobAmt) public {
        aliceAmt = bound(aliceAmt, 1e15, 1e24);
        bobAmt   = bound(bobAmt,   1e15, 1e24);

        // Ensure actors have enough tokens.
        deal(address(stakingToken), alice, aliceAmt);
        deal(address(stakingToken), bob,   bobAmt);

        _stake(alice, aliceAmt);
        _stake(bob,   bobAmt);

        vm.warp(block.timestamp + 3 days);

        uint256 aliceEarned = pool.earned(alice);
        uint256 bobEarned   = pool.earned(bob);

        // Total earned must be positive.
        assertTrue(aliceEarned + bobEarned > 0);

        // Proportionality: alice / bob ≈ aliceAmt / bobAmt (10% tolerance for rounding).
        if (aliceEarned > 0 && bobEarned > 0) {
            uint256 expectedRatio = aliceAmt * 1e18 / bobAmt;
            uint256 actualRatio   = aliceEarned * 1e18 / bobEarned;
            assertApproxEqRel(actualRatio, expectedRatio, 0.10e18);
        }

        _invariant_totalSupplyMatchesBalances(alice, bob, charlie);
    }

    // -------------------------------------------------------------------------
    // Invariant helper
    // -------------------------------------------------------------------------

    /// @dev Asserts that pool.totalSupply() == sum of individual balances.
    function _invariant_totalSupplyMatchesBalances(
        address user1,
        address user2,
        address user3
    ) internal view {
        uint256 sum = pool.balanceOf(user1) + pool.balanceOf(user2) + pool.balanceOf(user3);
        assertEq(pool.totalSupply(), sum, "Invariant: totalSupply != sum of balances");
    }
}
