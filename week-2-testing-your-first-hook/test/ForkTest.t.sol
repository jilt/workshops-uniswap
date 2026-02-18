// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
 
import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";

 
interface IERC20 {
    function balanceOf(address account) external view returns (uint);
}
 
contract ForkTest is Test {
    
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant USDC_WHALE = 0x9a17F715bAf444303392fAd997F9286f7DCd7BDd;
    // Looking for: 9,825,786.215209
 
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
}