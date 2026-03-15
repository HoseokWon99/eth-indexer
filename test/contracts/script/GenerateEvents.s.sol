// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/TestToken.sol";

/**
 * @title GenerateEvents
 * @dev Generates deterministic test events for eth-indexer
 * Token1: 50 Transfers + 30 Approvals
 * Token2: 40 Transfers + 20 Approvals
 * Total: 90 Transfers + 50 Approvals = 140 events
 */
contract GenerateEvents is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address token1Address = vm.envAddress("TOKEN1_ADDRESS");
        address token2Address = vm.envAddress("TOKEN2_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        TestToken token1 = TestToken(token1Address);
        TestToken token2 = TestToken(token2Address);

        // Generate deterministic addresses for testing
        address alice = address(0x1111111111111111111111111111111111111111);
        address bob = address(0x2222222222222222222222222222222222222222);
        address charlie = address(0x3333333333333333333333333333333333333333);

        console.log("Generating events for Token1 (TUSDC)...");
        // Token1: 50 Transfers
        for (uint256 i = 0; i < 50; i++) {
            address recipient = (i % 3 == 0) ? alice : (i % 3 == 1) ? bob : charlie;
            token1.transfer(recipient, (i + 1) * 1000 * 10**18);
        }

        // Token1: 30 Approvals
        for (uint256 i = 0; i < 30; i++) {
            address spender = (i % 3 == 0) ? alice : (i % 3 == 1) ? bob : charlie;
            token1.approve(spender, (i + 1) * 5000 * 10**18);
        }

        console.log("Generating events for Token2 (TUSDT)...");
        // Token2: 40 Transfers
        for (uint256 i = 0; i < 40; i++) {
            address recipient = (i % 3 == 0) ? alice : (i % 3 == 1) ? bob : charlie;
            token2.transfer(recipient, (i + 1) * 2000 * 10**18);
        }

        // Token2: 20 Approvals
        for (uint256 i = 0; i < 20; i++) {
            address spender = (i % 3 == 0) ? alice : (i % 3 == 1) ? bob : charlie;
            token2.approve(spender, (i + 1) * 10000 * 10**18);
        }

        vm.stopBroadcast();

        console.log("Event generation complete:");
        console.log("- Token1: 50 Transfers + 30 Approvals");
        console.log("- Token2: 40 Transfers + 20 Approvals");
        console.log("- Total: 140 events (excluding constructor events)");
    }
}
