// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title StakingPool
 * @notice Synthetix-style staking rewards contract.
 *
 * Users stake `stakingToken` and earn `rewardsToken` at a per-second rate
 * set by the owner via `notifyRewardAmount`. Reward accrual is tracked via a
 * rewardPerTokenStored accumulator that is updated on every state-changing call
 * through the `updateReward` modifier.
 *
 * Security properties:
 *  - Reentrancy protected on all external state-mutating functions.
 *  - Reward rate is validated so it cannot exceed the available balance.
 *  - Staking / reward tokens are handled through SafeERC20.
 */
contract StakingPool is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // Custom errors
    // -------------------------------------------------------------------------

    error ZeroAmount();
    error ZeroAddress();
    error RewardTooHigh();
    error PeriodNotFinished();
    error InsufficientBalance();

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);
    event Recovered(address token, uint256 amount);

    // -------------------------------------------------------------------------
    // Immutables
    // -------------------------------------------------------------------------

    /// @notice Token that users stake into this pool.
    IERC20 public immutable stakingToken;

    /// @notice Token that users receive as rewards.
    IERC20 public immutable rewardsToken;

    // -------------------------------------------------------------------------
    // Reward accounting state
    // -------------------------------------------------------------------------

    /// @notice Unix timestamp when the current reward period finishes.
    uint256 public periodFinish;

    /// @notice Reward tokens distributed per second during the active period.
    uint256 public rewardRate;

    /// @notice Duration of each reward period in seconds (default: 7 days).
    uint256 public rewardsDuration = 7 days;

    /// @notice Timestamp of the last reward-per-token snapshot update.
    uint256 public lastUpdateTime;

    /// @notice Accumulated reward tokens per staked token (scaled by 1e18).
    uint256 public rewardPerTokenStored;

    // -------------------------------------------------------------------------
    // Per-user reward accounting
    // -------------------------------------------------------------------------

    /// @notice Snapshot of `rewardPerTokenStored` at the time of the user's
    ///         last interaction.
    mapping(address => uint256) public userRewardPerTokenPaid;

    /// @notice Accumulated rewards not yet claimed by each user.
    mapping(address => uint256) public rewards;

    // -------------------------------------------------------------------------
    // Staking balances
    // -------------------------------------------------------------------------

    /// @dev Total staked supply across all users.
    uint256 private _totalSupply;

    /// @dev Per-user staked balance.
    mapping(address => uint256) private _balances;

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /**
     * @param _stakingToken  ERC20 token users will stake.
     * @param _rewardsToken  ERC20 token users will earn as rewards.
     */
    constructor(address _stakingToken, address _rewardsToken) Ownable(msg.sender) {
        if (_stakingToken == address(0) || _rewardsToken == address(0)) revert ZeroAddress();
        stakingToken = IERC20(_stakingToken);
        rewardsToken = IERC20(_rewardsToken);
    }

    // -------------------------------------------------------------------------
    // Views
    // -------------------------------------------------------------------------

    /// @notice Total staked token supply in the pool.
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    /// @notice Staked balance of `account`.
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    /**
     * @notice Returns the lesser of the current time and `periodFinish`.
     *         Used as the upper time bound when calculating accrued rewards.
     */
    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    /**
     * @notice Cumulative reward tokens earned per unit of staked token,
     *         scaled by 1e18.
     */
    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored
            + (lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18 / _totalSupply;
    }

    /**
     * @notice Reward tokens that `account` has accumulated but not yet claimed.
     */
    function earned(address account) public view returns (uint256) {
        return _balances[account]
            * (rewardPerToken() - userRewardPerTokenPaid[account])
            / 1e18
            + rewards[account];
    }

    /**
     * @notice Total reward tokens that would be emitted over the full duration
     *         at the current rate.
     */
    function getRewardForDuration() external view returns (uint256) {
        return rewardRate * rewardsDuration;
    }

    // -------------------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------------------

    /**
     * @dev Snapshots `rewardPerToken` and updates the user's earned balance
     *      before any state-mutating operation.
     */
    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    // -------------------------------------------------------------------------
    // User-facing functions
    // -------------------------------------------------------------------------

    /**
     * @notice Stake `amount` of stakingToken into the pool.
     * @param amount Token amount to stake (must be > 0).
     */
    function stake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        if (amount == 0) revert ZeroAmount();
        _totalSupply += amount;
        _balances[msg.sender] += amount;
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    /**
     * @notice Withdraw `amount` of previously staked tokens.
     * @param amount Token amount to withdraw (must be > 0 and <= staked balance).
     */
    function withdraw(uint256 amount) public nonReentrant updateReward(msg.sender) {
        if (amount == 0) revert ZeroAmount();
        if (_balances[msg.sender] < amount) revert InsufficientBalance();
        _totalSupply -= amount;
        _balances[msg.sender] -= amount;
        stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @notice Claim all accumulated reward tokens for the caller.
     */
    function getReward() public nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardsToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    /**
     * @notice Withdraw the full staked balance and claim all rewards in one
     *         transaction.
     */
    function exit() external {
        withdraw(_balances[msg.sender]);
        getReward();
    }

    // -------------------------------------------------------------------------
    // Owner-only functions
    // -------------------------------------------------------------------------

    /**
     * @notice Fund the reward pool and start (or extend) the reward period.
     *
     * If the previous period has not finished, the remaining undistributed
     * rewards are rolled into the new period.  The resulting rate must not
     * exceed the available token balance divided by the duration to ensure
     * solvency.
     *
     * @param reward Amount of rewardsToken to distribute over `rewardsDuration`.
     */
    function notifyRewardAmount(uint256 reward)
        external
        onlyOwner
        updateReward(address(0))
    {
        if (block.timestamp >= periodFinish) {
            rewardRate = reward / rewardsDuration;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = (reward + leftover) / rewardsDuration;
        }

        // Solvency check: rate must not exceed available balance.
        uint256 balance = rewardsToken.balanceOf(address(this));
        if (rewardRate > balance / rewardsDuration) revert RewardTooHigh();

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + rewardsDuration;
        emit RewardAdded(reward);
    }

    /**
     * @notice Update the reward period duration.
     *
     * Can only be called after the current period has finished to avoid
     * disrupting ongoing reward accounting.
     *
     * @param _rewardsDuration New duration in seconds.
     */
    function setRewardsDuration(uint256 _rewardsDuration) external onlyOwner {
        if (block.timestamp < periodFinish) revert PeriodNotFinished();
        rewardsDuration = _rewardsDuration;
        emit RewardsDurationUpdated(_rewardsDuration);
    }

    /**
     * @notice Rescue ERC20 tokens accidentally sent to this contract.
     *
     * The staking token cannot be recovered to protect user deposits.
     *
     * @param tokenAddress Address of the token to recover.
     * @param tokenAmount  Amount to transfer to the owner.
     */
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        if (tokenAddress == address(stakingToken)) revert ZeroAddress();
        IERC20(tokenAddress).safeTransfer(owner(), tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }
}
