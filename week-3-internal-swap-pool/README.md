# Uniswap v4 Internal Swap Pool: LVR Capture Edition

This repository contains a Uniswap v4 hook that implements an **Internal Swap Pool**. Unlike traditional hooks that charge a flat percentage fee on every trade, this hook acts as an internal arbitrageur to capture **Loss Versus Rebalancing (LVR)**.

## The Evolution of the Hook

### Phase 1: The 1% Fee Model (Legacy)
Initially, the hook was designed to take a 1% fee on every swap via the `afterSwap` hook. While effective at building reserves, this model:
1. Increased slippage for the end user.
2. Reduced the price competitiveness of the pool.
3. Taxed "non-toxic" retail flow and "toxic" arbitrage flow equally.

### Phase 2: The Arbitrageur Model (Current)
The hook now captures liquidity by identifying price discrepancies between the Uniswap pool and the broader market (via an external Oracle). Instead of taxing users, it "frontruns" the main pool's liquidity to fill arbitrage orders internally at a fair market price, keeping the profit for the LPs.

## How It Works

The hook uses an **Oracle-Driven Internalization** strategy:

1. **Price Monitoring**: In `beforeSwap`, the hook queries an external `IOracle` to find the "Fair Market Price" (e.g., the price on CEXs or high-volume aggregates).
2. **Arbitrage Detection**: It compares the current `slot0` price of the Uniswap pool with the Oracle price.
    - If `Pool Price < Oracle Price` during a `zeroForOne` swap, an arbitrage opportunity (toxic flow) exists.
3. **Internal Execution**: Instead of letting the arbitrageur drain value from the concentrated liquidity ticks at a "stale" price, the hook intercepts the trade:
    - It fills the order internally using its accumulated reserves.
    - It executes the swap at the **Oracle Price** rather than the stale pool price.
4. **Spread Capture**: The difference between the stale price and the fair price (the arbitrage profit) is captured by the hook contract.
5. **LP Distribution**: The captured profits are stored in `_poolFees` and periodically pushed to active Liquidity Providers via the `poolManager.donate` function.

## Key Technical Features

- **Flash Accounting**: Uses `beforeSwapReturnDelta` to modify the swap requirements in real-time, effectively bypassing the main pool for internalized volume.
- **MEV Protection**: By filling toxic flow at the Oracle price, the hook captures value that would otherwise be lost to MEV bots and searchers.
- **Zero Fee Impact**: Standard retail swaps that occur at the market price are not taxed, ensuring the pool remains competitive for aggregators.

## Architecture

- `InternalSwapPool.sol`: The core logic managing the `beforeSwap` interception and fee distribution.
- `IOracle.sol`: The interface for external price discovery similar to our previous chainlink functions calls mocks.
- `MockOracle.sol`: A test utility to simulate market volatility and price discrepancies.

## Running Tests

The test suite is built using Foundry. To run the tests for the Internal Swap Pool hook, use the following command:

```bash
forge test --match-path test/InternalSwapPool.t.sol
```
The tests verify that when a price discrepancy exists, the hook correctly fills the order from internal reserves and accumulates "profit" for LPs.