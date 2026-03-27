// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/StakingPool.sol";
import "../src/UniswapPool.sol";

/**
 * @title DeployStaking
 * @notice Deploys StakingPool and UniswapPool against existing TestToken addresses.
 *
 * Required environment variables:
 *   PRIVATE_KEY      — deployer private key (hex, with or without 0x prefix)
 *   TOKEN1_ADDRESS   — address of the staking / token0 ERC20
 *   TOKEN2_ADDRESS   — address of the rewards / token1 ERC20
 *
 * Usage (local Anvil):
 *   forge script script/DeployStaking.s.sol \
 *     --rpc-url anvil \
 *     --broadcast \
 *     -vvvv
 */
contract DeployStaking is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address token1 = vm.envAddress("TOKEN1_ADDRESS");
        address token2 = vm.envAddress("TOKEN2_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy StakingPool: users stake token1 and earn token2.
        StakingPool stakingPool = new StakingPool(token1, token2);
        console.log("StakingPool deployed at:", address(stakingPool));

        // Deploy UniswapPool: constant-product AMM for token1/token2.
        UniswapPool uniswapPool = new UniswapPool(token1, token2);
        console.log("UniswapPool deployed at:", address(uniswapPool));

        console.log("token0 (sorted):", address(uniswapPool.token0()));
        console.log("token1 (sorted):", address(uniswapPool.token1()));

        vm.stopBroadcast();
    }
}
