// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
 
import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {MockChainlinkFunctions} from "../src/MockChainlinkFunctions.sol";
import {PointsHook} from "../src/PointsHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
 
interface IERC20 {
    function balanceOf(address account) external view returns (uint);
}
 
contract ForkTest is Test {
    // Base Mainnet Addresses
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant USDC_WHALE = 0x9a17F715bAf444303392fAd997F9286f7DCd7BDd;
    
    // Suppose this is the real Chainlink Functions Router on Base
    address constant CHAINLINK_ROUTER = 0x000000000000000000000000000000000000dEaD;
    // Real V4 PoolManager on Base (placeholder)
    address constant POOL_MANAGER = 0x0111111111111111111111111111111111111111;
 
    uint forkId;
 
    // modifier to create and select a fork from MAINNET_RPC_URL env var
    modifier forked(uint _blockNumber) {
        forkId = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        vm.selectFork(forkId);
        vm.rollFork(_blockNumber);
        _;
    }

    function testUSDCBalanceForked() public forked(41257975) {
        // Deploy a new USDC contract
        // deployCodeTo('USDC.sol', '', USDC);

        uint balance = IERC20(USDC).balanceOf(USDC_WHALE);
        console.log("Whale balance (USDC):", balance / 1e6);

        assertEq(balance, 9997624403202, "Whale should have large balance");
    }

    function test_HookWithMockInFork() public forked(41257975) {
        // 1. Deploy the mock
        MockChainlinkFunctions mock = new MockChainlinkFunctions();
        
        // 2. "Etch" the mock onto the real Chainlink address
        // This ensures the Hook's calls to CHAINLINK_ROUTER hit our mock logic
        vm.etch(CHAINLINK_ROUTER, address(mock).code);
        
        // 3. Deploy Hook pointing to the "real" address
        PointsHook hook = new PointsHook(IPoolManager(POOL_MANAGER), CHAINLINK_ROUTER);
        
        // Now you can test hook logic using real mainnet state for pools/tokens
        // while keeping the Chainlink part controlled by your mock.
        assertEq(address(hook.mockChainlink()), CHAINLINK_ROUTER);
    }
}