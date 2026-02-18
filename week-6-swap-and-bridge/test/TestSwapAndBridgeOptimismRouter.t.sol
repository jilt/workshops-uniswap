// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {SwapAndBridgeOptimismRouter, IL1StandardBridge} from "../src/SwapAndBridgeOptimismRouter.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";

interface IOUTbToken {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function faucet() external;
}

contract TestSwapAndBridgeOptimismRouter is Test, Deployers {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    These are events from L1StandardBridge and CrossDomainMessenger
    //////////////////////////////////////////////////////////////*/

    event ETHDepositInitiated(
        address indexed from,
        address indexed to,
        uint256 amount,
        bytes extraData
    );

    event ERC20DepositInitiated(
        address indexed l1Token,
        address indexed l2Token,
        address indexed from,
        address to,
        uint256 amount,
        bytes extraData
    );

    event ETHBridgeInitiated(
        address indexed from,
        address indexed to,
        uint256 amount,
        bytes extraData
    );

    event ERC20BridgeInitiated(
        address indexed localToken,
        address indexed remoteToken,
        address indexed from,
        address to,
        uint256 amount,
        bytes extraData
    );

    event SentMessage(
        address indexed target,
        address sender,
        bytes message,
        uint256 messageNonce,
        uint256 gasLimit
    );

    event SentMessageExtension1(address indexed sender, uint256 value);

    /*//////////////////////////////////////////////////////////////
                            TEST STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 sepoliaForkId = vm.createFork("https://sepolia.drpc.org");

    SwapAndBridgeOptimismRouter poolSwapAndBridgeOptimism;

    // OUTb = Optimism Useless Token Bridged (ETH Sepolia and OP Sepolia addresses)
    IOUTbToken l1Token =
        IOUTbToken(0x12608ff9dac79d8443F17A4d39D93317BAD026Aa);
    IOUTbToken l2Token =
        IOUTbToken(0x7c6b91D9Be155A6Db01f749217d76fF02A7227F2);

    // L1 Standard Bridge on ETH Sepolia
    IL1StandardBridge public constant L1_STANDARD_BRIDGE =
        IL1StandardBridge(0xFBb0621E0B23b5478B630BD55a5f21f67730B0F1);

    // Cross Domain Messenger L2 Contract Address
    address public constant L2_CROSS_DOMAIN_MESSENGER =
        0x4200000000000000000000000000000000000010;

    /*//////////////////////////////////////////////////////////////
                            TEST SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        vm.selectFork(sepoliaForkId);
        vm.deal(address(this), 500 ether);

        // Deploy manager and routers
        deployFreshManagerAndRouters();
        poolSwapAndBridgeOptimism = new SwapAndBridgeOptimismRouter(
            manager,
            L1_STANDARD_BRIDGE
        );

        // Get some OUTb tokens on L1 and approve the routers to use it
        l1Token.faucet();
        l1Token.approve(
            address(poolSwapAndBridgeOptimism),
            type(uint256).max
        );
        l1Token.approve(address(modifyLiquidityRouter), type(uint256).max);

        // Create the OUTb token mapping on the periphery contract
        poolSwapAndBridgeOptimism.addL1ToL2TokenAddress(
            address(l1Token),
            address(l2Token)
        );

        // Deploy an ETH <> OUTb pool and add some liquidity there
        (key, ) = initPool(
            CurrencyLibrary.ADDRESS_ZERO,
            Currency.wrap(address(l1Token)),
            IHooks(address(0)),
            3000,
            SQRT_PRICE_1_1
        );
        modifyLiquidityRouter.modifyLiquidity{value: 1 ether}(
            key,
            ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 10 ether,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
    }

    /**
     * As long as we are running on a fork, we cannot check the OP Sepolia side of things
     *     So we will only test based on the events being output by the contract
     *     A separate script file exists which tests on actual Sepolia Testnet and OP Sepolia
     */

    /*//////////////////////////////////////////////////////////////
                            TEST SWAP ETH FOR OUTb
                            WITH BRIDGING TO OP
                            RECIPIENT = SENDER
    //////////////////////////////////////////////////////////////*/

    function test_swapETHForOUTb_bridgeTokensToOptimism_recipientSameAsSender()
        public
    {
        vm.expectEmit(true, true, true, false);
        emit ERC20DepositInitiated(
            address(l1Token),
            address(l2Token),
            address(poolSwapAndBridgeOptimism),
            address(this),
            0,
            ZERO_BYTES
        );

        vm.expectEmit(true, true, true, false);
        emit ERC20BridgeInitiated(
            address(l1Token),
            address(l2Token),
            address(poolSwapAndBridgeOptimism),
            address(this),
            0,
            ZERO_BYTES
        );

        vm.expectEmit(true, false, false, false);
        emit SentMessage(L2_CROSS_DOMAIN_MESSENGER, address(0), ZERO_BYTES, 0, 0);

        vm.expectEmit(true, false, false, false);
        emit SentMessageExtension1(address(L1_STANDARD_BRIDGE), 0);

        poolSwapAndBridgeOptimism.swap{value: 0.001 ether}(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            SwapAndBridgeOptimismRouter.SwapSettings({
                bridgeTokens: true,
                recipientAddress: address(this)
            }),
            ZERO_BYTES
        );
    }

    /*//////////////////////////////////////////////////////////////
                            TEST SWAP ETH FOR OUTb
                            WITH BRIDGING TO OP
                            RECIPIENT != SENDER
    //////////////////////////////////////////////////////////////*/

    function test_swapETHForOUTb_bridgeTokensToOptimism_receipientNotSameAsSender()
        public
    {
        address recipientAddress = address(0x1);

        vm.expectEmit(true, true, true, false);
        emit ERC20DepositInitiated(
            address(l1Token),
            address(l2Token),
            address(poolSwapAndBridgeOptimism),
            recipientAddress,
            0,
            ZERO_BYTES
        );

        vm.expectEmit(true, true, true, false);
        emit ERC20BridgeInitiated(
            address(l1Token),
            address(l2Token),
            address(poolSwapAndBridgeOptimism),
            recipientAddress,
            0,
            ZERO_BYTES
        );

        vm.expectEmit(true, false, false, false);
        emit SentMessage(L2_CROSS_DOMAIN_MESSENGER, address(0), ZERO_BYTES, 0, 0);

        vm.expectEmit(true, false, false, false);
        emit SentMessageExtension1(address(L1_STANDARD_BRIDGE), 0);

        poolSwapAndBridgeOptimism.swap{value: 0.001 ether}(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            SwapAndBridgeOptimismRouter.SwapSettings({
                bridgeTokens: true,
                recipientAddress: recipientAddress
            }),
            ZERO_BYTES
        );
    }

    /*//////////////////////////////////////////////////////////////
                            TEST SWAP OUTb FOR ETH
                            WITH BRIDGING TO OP
                            RECIPIENT = SENDER
    //////////////////////////////////////////////////////////////*/

    function test_swapOUTbForETH_bridgeTokensToOptimism_recipientSameAsSender()
        public
    {
        vm.expectEmit(true, true, false, false);
        emit ETHDepositInitiated(
            address(poolSwapAndBridgeOptimism),
            address(this),
            0,
            ZERO_BYTES
        );

        vm.expectEmit(true, true, false, false);
        emit ETHBridgeInitiated(
            address(poolSwapAndBridgeOptimism),
            address(this),
            0,
            ZERO_BYTES
        );

        vm.expectEmit(true, false, false, false);
        emit SentMessage(L2_CROSS_DOMAIN_MESSENGER, address(0), ZERO_BYTES, 0, 0);

        vm.expectEmit(true, false, false, false);
        emit SentMessageExtension1(address(L1_STANDARD_BRIDGE), 0);

        poolSwapAndBridgeOptimism.swap(
            key,
            SwapParams({
                zeroForOne: false,
                amountSpecified: -0.001 ether,
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            SwapAndBridgeOptimismRouter.SwapSettings({
                bridgeTokens: true,
                recipientAddress: address(this)
            }),
            ZERO_BYTES
        );
    }

    /*//////////////////////////////////////////////////////////////
                            TEST SWAP OUTb FOR ETH
                            WITH BRIDGING TO OP
                            RECIPIENT != SENDER
    //////////////////////////////////////////////////////////////*/
    function test_swapOUTbForETH_bridgeTokensToOptimism_recipientNotSameAsSender()
        public
    {
        address recipientAddress = address(0x1);

        vm.expectEmit(true, true, false, false);
        emit ETHDepositInitiated(
            address(poolSwapAndBridgeOptimism),
            recipientAddress,
            0,
            ZERO_BYTES
        );

        vm.expectEmit(true, true, false, false);
        emit ETHBridgeInitiated(
            address(poolSwapAndBridgeOptimism),
            recipientAddress,
            0,
            ZERO_BYTES
        );

        vm.expectEmit(true, false, false, false);
        emit SentMessage(L2_CROSS_DOMAIN_MESSENGER, address(0), ZERO_BYTES, 0, 0);

        vm.expectEmit(true, false, false, false);
        emit SentMessageExtension1(address(L1_STANDARD_BRIDGE), 0);

        poolSwapAndBridgeOptimism.swap(
            key,
            SwapParams({
                zeroForOne: false,
                amountSpecified: -0.001 ether,
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            SwapAndBridgeOptimismRouter.SwapSettings({
                bridgeTokens: true,
                recipientAddress: recipientAddress
            }),
            ZERO_BYTES
        );
    }

    /*//////////////////////////////////////////////////////////////
                            TEST SWAP ETH FOR OUTb
                            WITHOUT BRIDGING
    //////////////////////////////////////////////////////////////*/
    function test_swapETHForOUTb_dontBridgeTokens() public {
        uint256 ethBalanceBefore = address(this).balance;
        uint256 ouTbBalanceBefore = l1Token.balanceOf(address(this));

        poolSwapAndBridgeOptimism.swap{value: 0.001 ether}(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            SwapAndBridgeOptimismRouter.SwapSettings({
                bridgeTokens: false,
                recipientAddress: address(this)
            }),
            ZERO_BYTES
        );

        uint256 ethBalanceAfter = address(this).balance;
        uint256 ouTbBalanceAfter = l1Token.balanceOf(address(this));

        assertEq(ethBalanceBefore - ethBalanceAfter, 0.001 ether);
        assertGt(ouTbBalanceAfter, ouTbBalanceBefore);
    }

    /*//////////////////////////////////////////////////////////////
                            TEST SWAP OUTb FOR ETH
                            WITHOUT BRIDGING
    //////////////////////////////////////////////////////////////*/

    function test_swapOUTbForETH_dontBridgeTokens() public {
        uint256 ethBalanceBefore = address(this).balance;
        uint256 ouTbBalanceBefore = l1Token.balanceOf(address(this));

        poolSwapAndBridgeOptimism.swap(
            key,
            SwapParams({
                zeroForOne: false,
                amountSpecified: -0.001 ether,
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            SwapAndBridgeOptimismRouter.SwapSettings({
                bridgeTokens: false,
                recipientAddress: address(this)
            }),
            ZERO_BYTES
        );

        uint256 ethBalanceAfter = address(this).balance;
        uint256 ouTbBalanceAfter = l1Token.balanceOf(address(this));

        assertGt(ethBalanceAfter, ethBalanceBefore);
        assertEq(ouTbBalanceBefore - ouTbBalanceAfter, 0.001 ether);
    }
}