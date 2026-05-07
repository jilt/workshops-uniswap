// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PointsHook} from "../src/PointsHook.sol";
import {MockChainlinkFunctions} from "../src/MockChainlinkFunctions.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";

contract DeployPointsHook is Script {
    function run() external {
        // The PoolManager address depends on the network you are deploying to.
        // For local testing with anvil, ensure you have deployed the V4 core first.
        address poolManager = vm.envOr("POOL_MANAGER", address(0)); 
        if (poolManager == address(0)) {
            revert("POOL_MANAGER address must be set in environment or script");
        }

        vm.startBroadcast();

        // 1. Deploy the Mock Scoreboard (MockChainlinkFunctions)
        // In a production scenario, this would be the actual Chainlink Functions contract.
        MockChainlinkFunctions mock = new MockChainlinkFunctions();
        console.log("Mock Scoreboard deployed to:", address(mock));

        // 2. Define the Hook Flags
        // PointsHook only uses 'afterSwap', which corresponds to Hooks.AFTER_SWAP_FLAG (bit 6).
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG);

        // 3. Mine for a valid Hook address
        // HookMiner finds a salt such that: address(CREATE2) & flags == flags
        bytes memory constructorArgs = abi.encode(poolManager, address(mock));
        bytes memory creationCode = abi.encodePacked(type(PointsHook).creationCode, constructorArgs);

        (address hookAddress, bytes32 salt) = HookMiner.mine(
            address(this), // The deployer address
            flags,
            creationCode
        );

        // 4. Deploy the PointsHook using the mined salt
        PointsHook hook = new PointsHook{salt: salt}(
            IPoolManager(poolManager),
            address(mock)
        );

        console.log("PointsHook deployed to:", address(hook));
        require(address(hook) == hookAddress, "Address mining mismatch");

        vm.stopBroadcast();
    }
}