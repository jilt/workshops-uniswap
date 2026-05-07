// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
 
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
 
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
 
import {Currency} from "v4-core/types/Currency.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
 
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
 
import {ERC1155TokenReceiver} from "solmate/src/tokens/ERC1155.sol";
 
import {PointsHook} from "../src/PointsHook.sol";
import {MockChainlinkFunctions} from "../src/MockChainlinkFunctions.sol";
 
contract TestPointsHook is Test, Deployers, ERC1155TokenReceiver {
 
	MockERC20 token; // our token to use in the ETH-TOKEN pool
 
    MockChainlinkFunctions mockChainlink;
    
    // Test users from HookMock
    address user1 = address(0x1111111111111111111111111111111111111111);
    address user2 = address(0x2222222222222222222222222222222222222222);
    address user3 = address(0x3333333333333333333333333333333333333333);
    address newUser = address(0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaab);


	// Native tokens are represented by address(0)
	Currency ethCurrency = Currency.wrap(address(0));
	Currency tokenCurrency;
 
	PointsHook hook;

    function setUp() public {
        // Deploy Mock Chainlink Scoreboard first
        mockChainlink = new MockChainlinkFunctions();

        // Deploy PoolManager and Router contracts
        deployFreshManagerAndRouters();
        
        // Deploy our TOKEN contract
        token = new MockERC20("Test Token", "TEST", 18);
        tokenCurrency = Currency.wrap(address(token));
    
        // Mint a bunch of TOKEN to ourselves and to address(1)
        token.mint(address(this), type(uint128).max);
        token.mint(address(1), type(uint128).max);
    
        // Deploy hook to an address that has the proper flags set
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG);
        deployCodeTo("PointsHook.sol", abi.encode(address(manager), address(mockChainlink)), address(flags));

        // Deploy our hook
        hook = PointsHook(address(flags));
    
        // Approve our TOKEN for spending on the swap router and modify liquidity router
        // These variables are coming from the `Deployers` contract
        token.approve(address(swapRouter), type(uint256).max);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);
    
        // Initialize a pool
        (key, ) = initPool(
            ethCurrency, // Currency 0 = ETH
            tokenCurrency, // Currency 1 = TOKEN
            hook, // Hook Contract
            3000, // Swap Fees
            SQRT_PRICE_1_1 // Initial Sqrt(P) value = 1
        );
    
        // Add some liquidity to the pool
        uint160 sqrtPriceAtTickLower = TickMath.getSqrtPriceAtTick(-60);
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(60);
    
        uint256 ethToAdd = 0.003 ether;
        uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(
            SQRT_PRICE_1_1,
            sqrtPriceAtTickUpper,
            ethToAdd
        );
    
        modifyLiquidityRouter.modifyLiquidity{value: ethToAdd}(
            key,
            ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: int256(uint256(liquidityDelta)),
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
    }

    // Basic unit test for the swap function
    // - We need to make sure that we can spend ETH and receive points
    // - Spend 0.001 ETH (1e15)
    // - Receive 2x points = 0.002 points (2e15)
    function test_swap_success() public {
        // Get the PoolId uint
        uint256 poolIdUint = uint256(PoolId.unwrap(key.toId()));

        // Using this PoolIdUint value we can find the start balance of the user points
        uint256 pointsBalanceOriginal = hook.balanceOf(
            address(this),
            poolIdUint
        );
    
        // How can we confirm that we have the right value?
        assertEq(pointsBalanceOriginal, 0, 'Points balance is not 0');

        // Set user address in hook data
        bytes memory hookData = abi.encode(address(this));
    
        // Now we swap
        // We will swap 0.001 ether for tokens
        // We should get 20% of 0.001 * 10**18 points
        // = 2 * 10**14
        swapRouter.swap{value: 0.001 ether}(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether, // Exact input for output swap
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            hookData
        );

        uint256 pointsBalanceAfterSwap = hook.balanceOf(
            address(this),
            poolIdUint
        );

        assertEq(pointsBalanceAfterSwap - pointsBalanceOriginal, 0.002 ether, 'Points balance is not correct');
    }

    // Swap TOKEN for TOKEN -> Get no points
    // Test overflow amounts of tokens

    // Swap TOKEN for ETH -> Get no points
    function test_swap_tokenForEth() public {
        // Get the PoolId uint
        uint256 poolIdUint = uint256(PoolId.unwrap(key.toId()));

        // Using this PoolIdUint value we can find the start balance of the user points
        uint256 pointsBalanceOriginal = hook.balanceOf(
            address(this),
            poolIdUint
        );
    
        // How can we confirm that we have the right value?
        assertEq(pointsBalanceOriginal, 0, 'Points balance is not 0');

        // Set user address in hook data
        bytes memory hookData = abi.encode(address(this));
    
        // Now we swap
        // We will swap 0.001 ether for tokens
        // We should get 20% of 0.001 * 10**18 points
        // = 2 * 10**14
        swapRouter.swap(
            key,
            SwapParams({
                zeroForOne: false,
                amountSpecified: -0.001 ether, // Exact input for output swap
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            hookData
        );

        // Using this PoolIdUint value we can find the start balance of the user points
        uint256 pointsBalanceAfterSwap = hook.balanceOf(
            address(this),
            poolIdUint
        );
    
        // How can we confirm that we have the right value?
        assertEq(pointsBalanceOriginal, pointsBalanceAfterSwap, 'Points balance is not 0');
    }
    
    // Swap a number not divisible by 5 (e.g. < 5) -> Get no points
    function test_swap_swapDust() public {
        uint256 poolIdUint = uint256(PoolId.unwrap(key.toId()));
        uint256 pointsBalanceOriginal = hook.balanceOf(
            address(this),
            poolIdUint
        );

        bytes memory hookData = abi.encode(address(this));
    
        // Swap 1 wei (the smallest possible amount)
        swapRouter.swap{value: 1}(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -1,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            hookData
        );

        uint256 pointsBalanceAfterSwap = hook.balanceOf(address(this), poolIdUint);
        assertEq(pointsBalanceAfterSwap - pointsBalanceOriginal, 2, 'Points balance is not correct for dust');
    }

    function testFuzz_swap(uint256 _amount, bool _zeroForOne, address _pointsRecipient) public {
        // To ensure that we can convert the uint to an int, we need to ensure the value does not go over uint128
        // vm.assume(_amount < type(uint128).max);
        _amount = bound(_amount, 5, type(uint128).max);

        // Ensure that we have enough tokens to fill the swap
        if (_zeroForOne) {
            // We need more ETH
            deal(address(this), _amount);
        } else {
            // We need more TOKEN
            deal(address(token), address(this), _amount);
            token.approve(address(swapRouter), _amount);
        }

        uint256 poolIdUint = uint256(PoolId.unwrap(key.toId()));
        uint256 pointsBalanceOriginal = hook.balanceOf(_pointsRecipient, poolIdUint);
    
        // Set user address in hook data
        bytes memory hookData = abi.encode(_pointsRecipient);
    
        // Now we swap
        // We will swap 0.001 ether for tokens
        // We should get 20% of 0.001 * 10**18 points
        // = 2 * 10**14
        swapRouter.swap{value: _zeroForOne ? _amount : 0}(
            key,
            SwapParams({
                zeroForOne: _zeroForOne,
                // forge-lint: disable-next-line(unsafe-typecast)
                amountSpecified: -int256(_amount), // Exact input for output swap
                sqrtPriceLimitX96: _zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            hookData
        );

        uint256 pointsBalanceAfterSwap = hook.balanceOf(_pointsRecipient, poolIdUint);

        // @todo We only gain points if the are swapping ETH for TOKEN
        if (_zeroForOne) {
            assertGt(pointsBalanceAfterSwap, pointsBalanceOriginal, 'No points gained');
        } else {
            assertEq(pointsBalanceAfterSwap, pointsBalanceOriginal, 'Points balance is not correct');
        }
    }

    // ========== LEADERBOARD TESTS (MERGED) ==========

    function test_LeaderboardInitialized() public {
        uint256 length = mockChainlink.getLeaderboardLength();
        assertEq(length, 10, "Leaderboard should have 10 initial entries");
    }
    
    function test_GetUserRank() public {
        (uint256 rank, uint256 points, uint256 swapCount) = mockChainlink.getUserRank(user1);
        
        assertEq(rank, 1, "User1 should be rank 1");
        assertEq(points, 5000, "User1 should have 5000 points");
        assertEq(swapCount, 50, "User1 should have 50 swaps");
    }
    
    function test_GetUserRankNotFound() public {
        (uint256 rank, uint256 points, uint256 swapCount) = mockChainlink.getUserRank(newUser);
        
        assertEq(rank, 0, "Unknown user should have rank 0");
        assertEq(points, 0, "Unknown user should have 0 points");
        assertEq(swapCount, 0, "Unknown user should have 0 swaps");
    }
    
    function test_GetTopUsers() public {
        MockChainlinkFunctions.LeaderboardEntry[] memory topUsers = mockChainlink.getTopUsers(5);
        
        assertEq(topUsers.length, 5, "Should return 5 top users");
        assertEq(topUsers[0].user, user1, "First should be user1");
    }
    
    function test_UpdateLeaderboardEntry() public {
        mockChainlink.adminUpdateEntry(0, user1, 6000, 60, 120 ether);
        
        (uint256 rank, uint256 points, uint256 swapCount) = mockChainlink.getUserRank(user1);
        assertEq(points, 6000, "User1 points should be updated to 6000");
    }
    
    function test_UpdateLeaderboardEntryOutOfBounds() public {
        vm.expectRevert("Index out of bounds");
        mockChainlink.adminUpdateEntry(20, user1, 1000, 10, 10 ether);
    }
    
    function test_UpdateExistingUser() public {
        uint256 initialLength = mockChainlink.getLeaderboardLength();
        
        // Add points to existing user
        mockChainlink.addUserToLeaderboard(user1, 500, 5, 5 ether);
        
        uint256 newLength = mockChainlink.getLeaderboardLength();
        assertEq(newLength, initialLength, "Length should remain same for existing user");
        
        (uint256 rank, uint256 points, uint256 swapCount) = mockChainlink.getUserRank(user1);
        assertEq(points, 5500, "User1 points should be increased to 5500");
    }
    
    function test_LeaderboardRanking() public {
        (uint256 rank1, uint256 points1,) = mockChainlink.getUserRank(user1);
        (uint256 rank2, uint256 points2,) = mockChainlink.getUserRank(user2);
        (uint256 rank3, uint256 points3,) = mockChainlink.getUserRank(user3);
        
        assertEq(rank1, 1, "User1 should be rank 1");
        assertEq(rank2, 2, "User2 should be rank 2");
        assertEq(rank3, 3, "User3 should be rank 3");
        
        assertGt(points1, points2, "Rank 1 should have more points than rank 2");
    }
    
    function test_GameLoop_MultipleSwaps_Leaderboard() public {
        for (uint256 i = 0; i < 10; i++) {
            mockChainlink.addUserToLeaderboard(newUser, 100, 1, 1 ether);
        }
        
        (uint256 rank, uint256 points, uint256 swapCount) = mockChainlink.getUserRank(newUser);
        assertGt(points, 0, "User should accumulate points");
        assertGt(swapCount, 0, "User should accumulate swaps");
    }

    function test_TokenTierUpgrade_Logic_Merged() public {
        (uint256 rank,,,) = mockChainlink.getUserRank(user1);
        
        uint256 tier;
        if (rank <= 3) {
            tier = 3; // Legendary
        } else if (rank <= 6) {
            tier = 2; // Rare
        } else {
            tier = 1; // Basic
        }
        
        assertEq(tier, 3, "User1 (rank 1) should get legendary tier");
    }

    function test_SendMockRequest_Merged() public {
        bytes memory emptyBytes = "";
        bytes32 requestId = mockChainlink.sendRequest(emptyBytes, emptyBytes, "test", emptyBytes, new bytes, 1, 100000, bytes32(0));
        assertNotEq(requestId, bytes32(0), "Request ID should not be zero");
    }
}