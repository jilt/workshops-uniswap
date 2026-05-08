# Custom Curve (CSMM) NoOp Hook

### NoOp Hooks Flow

NoOp hooks are hooks that can override the PM's own logic for operations - like swaps.

The way they work is that hooks like `beforeSwap` and `afterSwap` get the ability to return their own balance deltas. `beforeSwap` particularly has a special one - `BeforeSwapDelta` - which is slightly different from the normal `BalanceDelta`.

Based on the returned deltas, the actual operation supposed to be conducted by the PM may be modified.

For example, if a user wants to do an exact input swap for selling 1 Token A for Token B:

**Without NoOp Hooks**

- User calls `swap` on Swap Router
- Swap Router calls PM `swap`
- PM calls `beforeSwap` for whatever it needs to do
- PM conducts a swap on `pools[id].swap` with `amountSpecified = -1` and `zeroForOne = true`
- PM gets a `BalanceDelta` of `-1 Token A` and some positive `Token B` value
- PM calls `afterSwap` on the hook
- PM returns the `BalanceDelta` to the Swap Router
- Swap Router accounts for the `BalanceDelta` and trasnfers Token A from user to PM and Token B from PM to user

---

**With NoOp Hooks**

- User calls `swap` on Swap Router
- Swap Router calls PM `swap`
- PM calls `beforeSwap`
- `beforeSwap` can return a `BeforeSwapDelta` which specifies it has "consumed" the `-1 Token A` from the user, and has created a `+1 Token B` delta as well, leaving `0 Token A` to be swapped through the PM
- PM sees there are no tokens left to swap through its regular logic, so the regular `swap` operation is NoOp-ed
- PM calls `afterSwap`
- `afterSwap` can optionally return a different `BalanceDelta` further
- PM returns the final `BalanceDelta` to the Swap Router
- The final `BalanceDelta` is `-1 Token A` and `+1 Token B`
- Swap Router settles the final `BalanceDelta` and transfers Token A from user to PM and Token B from PM to user

It is possible for `beforeSwap` for example to only consume portion of the Token A - perhaps 0.5 Token A - and leave the remaining 0.5 Token A to go through the regular PM swap function. This is useful for example if the hook wants to charge "custom fees" for some services it is performing that it keeps for itself (not LP fee and not protocol fee).

### Flow

The hook acts as a middleman between the User and the Pool Manager.

Liquidity Providers add liquidity through the hook, where the hook takes their tokens and adds that liquidity under its own control to the Pool Manager.

When swappers wish to swap on the CSMM, the hook is the one maintaining liquidity for the swap. This part is a little tricky - let's go through the flow.

Quick Revision of Terminology:

Remember that all terminology and conventions are designed from the perspective of the User.

- `take` => Receive a currency from the PoolManager i.e. user is "taking" money from PM
- `settle` => Sending a currency to the PoolManager i.e. user is "settling" debt to PM

The general flow for a swap goes as follows:

1. User calls Swap Router
2. Swap Router calls PM
3. PM calls hook
4. Hook returns
5. PM returns final BalanceDelta
6. Swap Router accounts for the final BalanceDelta

In our case, let's see what the flow looks like. First, for an LP:

1. LP wants to add 100 Token A and 100 Token B to the pool
2. LP calls `addLiquidity` on the hook contract directly (no routers, no PM involved)
3. Hook _does not_ go through "modifyLiquidity" on the PM - since that would be liquidity being added to the default pricing curve
4. Hook simply takes the user's money and sends it to PM (normal token transfer, not calling a function)
5. PM now has a debt to the hook of 100 Token A and 100 Token B
6. Hook "takes" the money back from the PM in the form of claim tokens
7. Hook keeps the claim tokens with itself, and accounts for the LP's share of the pool manually

Then, when a swapper comes by:

1. Swapper wants to swap 1 Token A for 1 Token B
2. Swapper calls `swap` on the Swap Router
3. Swap Router calls the PM `swap`
4. PM calls hook `beforeSwap`
5. To NoOp the PM's own `swap` function, `beforeSwap` must return a `BeforeSwapDelta` which negates the PMs swap. PMs swap is negated if there is no amount left to swap for the PM.
6. So, in this case, `beforeSwap` must say that it has consumed the 1 Token A provided as input, so there are 0 Tokens left to swap through the PM's own swap function - therefore NoOp-ing it
7. To actually handle the swap itself, remember the hook has claim tokens for all the liquidity with it.
8. The user, to sell Token A, must be sending 1 Token A to the PM. The hook will claim ownership of that 1 Token A by minting a claim token for it from the PM.
9. Also, the hook burns a claim token for B that it had, so the PM can use that Token B to pay the user
10. At the end of the PM's `swap` function, therefore, we have the following deltas created:

- User has a delta of -1 Token A to PM
- Hook has a delta of +1 Token A (claim token mint) from PM

- User has a delta of +1 Token B from PM
- Hook has a delta of -1 Token B (claim token burn) to PM

The sum total delta, therefore, is settled. Only thing left to do is move the underlying Token A from user to PM, and Token B from PM to user.

SwapRouter gets told to move `-1 Token A` from user to PM, and `+1 Token B` from PM to user. It does that, and the transaction is complete.

### Implemented Modular Architecture

The implementation is split into two modules to separate concerns:

1.  **`CSMMVault.sol`**: An abstract contract handling LP share accounting using the ERC-1155 standard. It tracks `totalSupply` per pool and provides a `totalAssets` view that queries the Pool Manager for the hook's claim token balances.
2.  **`CSMMHook.sol`**: The core Uniswap v4 hook that manages the `beforeSwap` NoOp logic and facilitates liquidity entry/exit.

#### Yield Mechanism (Swap Fees)

The hook implements a 1% fee on swaps. Because we use a NoOp flow with claim tokens:

- When a user swaps 100 Token A for Token B, the hook "consumes" the 100 Token A (minting 100 claim tokens).
- The hook only "burns" 99 claim tokens of Token B to pay the user.
- The remaining 1% remains in the hook's balance within the Pool Manager.

#### Liquidity Management

**Adding Liquidity**: LPs call `addLiquidity` directly on the hook. The hook settles the tokens to the PM and mints 1:1 LP shares (represented as ERC-1155 tokens) to the LP.

**Removing Liquidity**: LPs call `removeLiquidity`. The hook calculates their proportional share of the current reserves (including accumulated fees) and burns the necessary claim tokens to return the underlying assets. This ensures LPs capture the yield generated by swappers.

### Testing

To verify the hook's functionality, swap logic, and yield accumulation, run the test suite using Foundry:

```bash
forge test -vvv
```

The tests in `CSMM.t.sol` validate:
- Correct minting of claim tokens upon adding liquidity.
- Execution of NoOp swaps with the 1% fee deduction.
- Proportional distribution of accumulated swap fees to LPs upon liquidity removal.
