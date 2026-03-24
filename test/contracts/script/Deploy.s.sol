// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/TestToken.sol";

/**
 * @title Deploy
 * @dev Deploys two test tokens for eth-indexer testing
 */
contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy Token1 (simulating USDC)
        TestToken token1 = new TestToken("Test USDC", "TUSDC", type(uint256).max);
        console.log("Token1 (TUSDC) deployed at:", address(token1));

        // Deploy Token2 (simulating USDT)
        TestToken token2 = new TestToken("Test USDT", "TUSDT", type(uint256).max);
        console.log("Token2 (TUSDT) deployed at:", address(token2));

        vm.stopBroadcast();
    }
}
