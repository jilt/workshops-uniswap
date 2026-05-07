## What does this hook do

this hook transforms a standard Uniswap pool into a loyalty-driven ecosystem where trading volume is converted into social status and on-chain collectibles.


## Available hook functions

```
beforeInitialize
afterInitialize
 
beforeAddLiquidity
beforeRemoveLiquidity
afterAddLiquidity
afterRemoveLiquidity
 
beforeSwap
afterSwap
 
beforeDonate
afterDonate
 
beforeSwapReturnDelta
afterSwapReturnDelta
afterAddLiquidityReturnDelta
afterRemoveLiquidityReturnDelta
```

## main part of the lesson used

In order to know who much ETH are spent during the swap we need `balanceDelta` struct from `afterSwap` hook

```solidity
beforeSwap(
	address sender, 
	PoolKey calldata key, 
	SwapParams calldata params, 
	bytes calldata hookData
)
 
afterSwap(
	address sender,
	PoolKey calldata key, 
	SwapParams calldata params, 
	BalanceDelta delta, 
	bytes calldata hookData
)
```
## Deploy the hook

### Set your environment variables
```
export POOL_MANAGER=0x... 
export RPC_URL=http://localhost:8545
export PRIVATE_KEY=0x...
```
### Run the deployment
```
forge script script/DeployPointsHook.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
```

## How This Hook is Built

### The Loyalty Manager, PointsHook.sol

It sits on top of Uniswap and watches every trade.

**The Trigger:** It only cares when someone spends ETH to buy a Token. If you are doing any other kind of trade, it ignores you.
**The Identity Check (hookData):** Before it does any math, it checks if the trade included the buyer's address. If the address is missing, it "reverts" (cancels the transaction) immediately. This is a security and gas-saving feature—it doesn't want to waste computing power on a trade it can't reward.
**The Reward (Cashback):** It looks at how much ETH you spent and gives you 20% of that value in Points.
If you spend 0.5 ETH, you get 1 Point.
These points are "Pool-Specific," meaning points earned only in the selected pool.
**The Level-Up (Tiers):** After giving you points, it checks a leaderboard. If your total points or your rank are high enough, it automatically updates the erc1155 metadata for you with your user's level:
Basic: The starting level.
Rare: For active traders.
Legendary: For the top 3 players on the leaderboard.

### The Global Scoreboard MockChainlinkFunctions.sol

In a real-world app, calculating a "Global Rank" is too expensive to do directly on the blockchain. You would usually use a service like Chainlink to talk to an external database.

Since you are testing locally, this "Mock" contract acts as that external database.

**The Leaderboard:** It keeps a list of the top 10 users across the whole system.
**Rankings:** It calculates who is #1, #2, etc., based on their total points and trade volume.
**The Connection:** When the Hook finishes a swap, it sends the data here. This contract then tells the Hook: "Hey, this user is now ranked #2 globally," which allows the Hook to decide if the user deserves a level upgrade.

## Summary of the Flow:
User Swaps: You buy a token with 1 ETH on Uniswap.
Hook Wakes Up: The Hook calculates you earned 2 points.
Points Issued: You receive 2 "Pool Points" (an ERC-1155 token).
Scoreboard Updates: The Hook tells the Mock contract you just earned 2 points.
Rank Check: The Mock contract sees you are now in the Top 3.
Achievement Unlocked: The Hook sees your new rank and updates the metadata for your tokens signaling your levelling up.

## Advanced Use Cases: Beyond Gamification

The pattern used in this workshop—connecting a Hook to an external data source via a Mock/Chainlink interface—isn't just for points and leaderboards. It is the foundation for sophisticated DeFi strategies:

*   **IL Protection:** By fetching real-time token prices from **Chainlink Oracles**, a hook can detect when a pool is being "arbitraged" (toxic flow). It can then dynamically increase fees to compensate Liquidity Providers for potential Impermanent Loss.
*   **Automated Rebalancing:** Hooks can trigger liquidity shifts based on external market conditions. If an oracle reports a price trend change, the hook can move liquidity ranges in `beforeSwap` to ensure LPs remain profitable.
*   **Dynamic Volatility Fees:** Using external volatility data, hooks can charge higher fees during turbulent markets and lower fees during stable periods, optimizing the pool for volume and safety.
