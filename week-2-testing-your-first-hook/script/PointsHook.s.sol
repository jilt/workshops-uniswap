// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Script} from 'forge-std/Script.sol';

import {Hooks} from 'v4-core/libraries/Hooks.sol';
import {IPoolManager} from 'v4-core/interfaces/IPoolManager.sol';
import {HookMiner} from 'v4-hooks-public/src/utils/HookMiner.sol';

import {PointsHook} from '../src/PointsHook.sol';


// Live run: forge script script/PointsHook.s.sol:PointsHookScript --rpc-url https://sepolia.base.org --chain-id 84532 --broadcast --verify
// Test run: forge script script/PointsHook.s.sol:PointsHookScript --rpc-url https://sepolia.base.org --chain-id 84532
//           ^----------^ ^--------------------------------------^ ^--------------------------------^ ^--------------^


contract PointsHookScript is Script {

    // https://getfoundry.sh/guides/deterministic-deployments-using-create2/#getting-started
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    // https://docs.uniswap.org/contracts/v4/deployments#base-sepolia-84532
    address internal constant POOL_MANAGER = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;

    // Add the address of your deployed MockChainlinkFunctions or ILoaderboard implementation
    address internal constant LEADERBOARD = 0x0000000000000000000000000000000000000000; // Update this!

    function run() external {
        uint privateKey = vm.envUint('PRIVATE_KEY');

        // Hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG);

        // The constructor now requires BOTH the PoolManager and the Leaderboard address
        bytes memory constructorArgs = abi.encode(POOL_MANAGER, LEADERBOARD);
        (address hookAddress, bytes32 salt) = HookMiner.find(CREATE2_DEPLOYER, flags, type(PointsHook).creationCode, constructorArgs);

        vm.startBroadcast(privateKey);

        // Deploy the hook using CREATE2
        PointsHook pointsHook = new PointsHook{salt: salt}(IPoolManager(POOL_MANAGER), LEADERBOARD);
        require(address(pointsHook) == hookAddress, 'PointsHookScript: hook address mismatch');

        vm.stopBroadcast();
    }

}
