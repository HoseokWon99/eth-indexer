// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/TestToken.sol";

/**
 * @title GenerateEvents
 * @dev Generates deterministic test events for eth-indexer
 *
 */
contract GenerateEvents is Script {
    function run() external {
        string memory mnemonic = vm.envString("MNEMONIC");
        uint256 deployerPrivateKey = vm.deriveKey(mnemonic, 0);

        TestToken[2] memory tokens = [
            TestToken(vm.envAddress("TOKEN1_ADDRESS")),
            TestToken(vm.envAddress("TOKEN2_ADDRESS"))
        ];

        // Derive accounts 1-3 from mnemonic
        uint256[3] memory privateKeys = [
            vm.deriveKey(mnemonic, 1),
            vm.deriveKey(mnemonic, 2),
            vm.deriveKey(mnemonic, 3)
        ];

        address[3] memory accounts = [
            vm.addr(privateKeys[0]),
            vm.addr(privateKeys[1]),
            vm.addr(privateKeys[2])
        ];

        // Deployer transfers tokens to accounts
        vm.startBroadcast(deployerPrivateKey);
        for (uint256 i = 0; i < 60; ++i) {
            uint256 j = i % 3;
            address recipient = accounts[(j + 1) % 3];
            uint256 amount = (j + 1) * 100 * 10**18;

            for (uint256 k = 0; k < tokens.length; ++k) {
                tokens[k].transfer(recipient, amount);
            }
        }
        vm.stopBroadcast();

        // Each sender approves recipient to spend their tokens
        for (uint256 i = 0; i < 60; ++i) {
            uint256 j = i % 3;
            address recipient = accounts[(j + 1) % 3];
            uint256 amount = (j + 1) * 100 * 10**18;

            for (uint256 k = 0; k < tokens.length; ++k) {
                vm.broadcast(privateKeys[j]);
                tokens[k].approve(recipient, amount);
            }
        }
    }
}
