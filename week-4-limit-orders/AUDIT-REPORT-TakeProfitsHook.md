# Security Audit Report: TakeProfitsHook.sol

**Methodology**: Trail of Bits–style audit (context building, entry-point analysis, sharp edges).

**Scope**: `src/TakeProfitsHook.sol`  
**Dependencies**: Uniswap v4-core (BaseHook, PoolManager, PoolKey, PoolId), OpenZeppelin ERC1155, Solmate FixedPointMathLib, CurrencySettler (test utils).

---

## 1. Entry Point Analysis (State-Changing Only)

| Category | Count |
|----------|-------|
| Public (Unrestricted) | 4 |
| Contract-Only (Hook callbacks) | 2 |
| **Total** | **6** |

### Public Entry Points (Unrestricted)

| Function | File | Notes |
|----------|------|-------|
| `placeOrder(PoolKey,int24,bool,uint256)` | TakeProfitsHook.sol:86 | Pulls tokens from user, updates `pendingOrders` / `claimTokensSupply`, mints ERC1155 claim tokens. |
| `cancelOrder(PoolKey,int24,bool,uint256)` | TakeProfitsHook.sol:114 | Burns claim tokens, decreases `pendingOrders` / `claimTokensSupply`, sends input token back. |
| `redeemTokens(PoolKey,int24,bool,uint256)` | TakeProfitsHook.sol:140 | Burns claim tokens, decreases `claimableOutputTokens` / `claimTokensSupply`, sends output token. |
| `getOrderId(PoolKey,int24,bool)` | TakeProfitsHook.sol:264 | **Pure** – excluded from state-changing count; listed for completeness. |

### Contract-Only (Hook Callbacks)

| Function | File | Expected Caller |
|----------|------|------------------|
| `_afterInitialize(address,PoolKey,uint160,int24)` | TakeProfitsHook.sol:292 | PoolManager during pool initialization. |
| `_afterSwap(address,PoolKey,SwapParams,BalanceDelta,bytes)` | TakeProfitsHook.sol:302 | PoolManager after each swap. |

**Observation**: `executeOrder` is `internal` and is the only path that consumes `pendingOrders` and credits `claimableOutputTokens`. It is never called; `_afterSwap` and `_afterInitialize` are stubbed with `// TODO`. So limit orders are never executed by the hook.

---

## 2. Critical Findings

### 2.1 Inconsistent PoolId access: `key.id()` vs `key.toId()` (Bug / Compile Risk)

- **Location**: `placeOrder` (L101) uses `key.id()`; `cancelOrder` (L130), `executeOrder` (L221), and `getOrderId` (L271) use `key.toId()`.
- **Context**: In v4-core, `PoolKey` only gets `toId()` from `PoolIdLibrary`; there is no `id()` on `PoolKey`.
- **Impact**: If `id()` is not defined elsewhere, the project does not compile. If it is an alias or extension, using two different methods for the same concept risks wrong-slot bugs (orders stored under one key and read/updated under another).
- **Recommendation**: Use `key.toId()` everywhere and remove or align any custom `id()` so there is a single, consistent way to derive `PoolId` from `PoolKey`.

### 2.2 Limit-order execution not implemented (Design / Completeness)

- **Location**: `_afterSwap` (L302–311), `_afterInitialize` (L292–300); `executeOrder` (L199–225) is never invoked.
- **Context**: Hook permissions set `afterSwap: true` and `afterInitialize: true`, but the overrides only return the selector and do not call `executeOrder`. No logic decides when price has crossed a tick or which orders to execute.
- **Impact**: Users can place, cancel, and (once output exists) redeem, but no swap callback ever fills orders. Funds in `pendingOrders` are never converted to output; the “take profit” behavior is absent.
- **Recommendation**: Implement `_afterSwap` (and optionally `_afterInitialize`) to determine which (pool, tick, zeroForOne) orders are in range and call `executeOrder` for them, then settle with the pool manager as required by the v4 hook interface.

### 2.3 Checks–Effects–Interactions (CEI) violation in `placeOrder` (Reentrancy)

- **Location**: TakeProfitsHook.sol:99–109.
- **Context**: State is updated before the external call:
  1. `pendingOrders[...] += inputAmount`
  2. `claimTokensSupply[orderId] += inputAmount`
  3. `_mint(msg.sender, orderId, inputAmount, '')`
  4. `IERC20(sellToken).transferFrom(msg.sender, address(this), inputAmount)` (external call)
- **Impact**: A malicious or callback-heavy ERC20 could reenter during `transferFrom`. A reentrant call could interact with the same order (e.g. cancel or redeem) with state already updated, or duplicate state updates if the token logic and hook logic are composed in an unexpected way. Risk is protocol- and token-dependent but violates standard safe ordering.
- **Recommendation**: Follow CEI: perform `transferFrom` first (or at least before any state that a reentrant call could rely on), then update `pendingOrders`, `claimTokensSupply`, and mint. Alternatively, use a reentrancy guard for the whole flow.

---

## 3. Medium / Design Considerations

### 3.1 Use of test utility in production path

- **Location**: L14 – `import {CurrencySettler} from 'v4-core/test/utils/CurrencySettler.sol'`.
- **Context**: `CurrencySettler` is under `test/utils`. The remapping `v4-core/=.../src/` does not include `test/`, so the import path may not resolve in this repo; even when it does, test helpers are usually not audited or guaranteed stable for production.
- **Recommendation**: Use a production-grade settlement helper or inline the settle/take logic in the hook so the main contract does not depend on test utils.

### 3.2 No slippage or price bounds on execution

- **Location**: `executeOrder` → `swapAndSettleBalances` with `sqrtPriceLimitX96` set to `MIN_SQRT_PRICE + 1` or `MAX_SQRT_PRICE - 1` (L213–215).
- **Context**: Comment states “No slippage limits (maximum slippage possible).” Execution is at whatever price the pool has when the hook runs.
- **Impact**: When `_afterSwap` is implemented, a large swap that moves price could be followed by execution of limit orders at worse-than-expected prices. Acceptable only if the design explicitly allows “market” execution at current price.
- **Recommendation**: Document this as intentional; if not, consider optional min-output or price bounds for execution (e.g. per order or per pool).

### 3.3 `redeemTokens` and division by zero

- **Location**: L181–184 – `totalInputAmountForPosition = claimTokensSupply[orderId]` used as denominator in `mulDivDown`.
- **Context**: The function reverts with `NothingToClaim()` when `claimableOutputTokens[orderId] == 0`. In the current design, `claimableOutputTokens` is only increased in `executeOrder`, and redemptions decrease both `claimableOutputTokens` and `claimTokensSupply` together, so in practice `claimTokensSupply[orderId]` should be > 0 whenever there is something to claim.
- **Impact**: If a bug or upgrade ever allowed `claimableOutputTokens[orderId] > 0` while `claimTokensSupply[orderId] == 0`, `mulDivDown` would revert (division by zero). Not an issue for current logic but a fragile invariant.
- **Recommendation**: Add an explicit check that `claimTokensSupply[orderId] != 0` before the division, or document the invariant and add a comment/fuzz test that enforces it.

---

## 4. Invariants and Assumptions (Context-Building Summary)

- **orderId**: `keccak256(abi.encode(key.toId(), tick, zeroForOne))` – must be computed the same way everywhere (hence importance of fixing `key.id()` vs `key.toId()`).
- **pendingOrders**: Total input amount per (poolId, tick, zeroForOne) that has not yet been executed or cancelled; only decreased by `cancelOrder` and `executeOrder`.
- **claimTokensSupply[orderId]**: Total supply of ERC1155 claim tokens for that orderId; must match the sum of inputs for that order minus redemptions (and any cancellation).
- **claimableOutputTokens[orderId]**: Output token amount available to redeem for that orderId; only increased in `executeOrder`, decreased in `redeemTokens`.
- **Trust**: PoolManager and v4 pool behavior (swap, settle, take) are trusted; ERC20s are assumed standard or at least non-malicious for CEI/reentrancy.

---

## 5. Sharp Edges (API / Footguns)

- **Tick rounding**: `getLowerUsableTick` rounds toward more negative ticks. Users who pass a tick that is not already spacing-aligned may get a different tick than they expect; document that “tick” is rounded down to the nearest valid tick.
- **Exact input, unbounded output**: `amountSpecified: -int256(inputAmount)` means “exact input”; output depends on pool state. Combined with no slippage in execution, this is a deliberate “take whatever the pool gives” design – should be clear in UX/docs.
- **ERC1155 tokenId = orderId**: The same `orderId` (large uint from keccak256) is used as ERC1155 tokenId. No semantic checks; ensure frontends and integrators do not assume small or sequential IDs.

---

## 6. Summary Table

| Severity | Count | Items |
|----------|-------|--------|
| Critical | 2 | Wrong/missing PoolId in `placeOrder`; execution path never called (TODO hooks). |
| High | 1 | CEI violation in `placeOrder` (reentrancy). |
| Medium | 3 | Test util import; no slippage on execution; div-by-zero invariant in `redeemTokens`. |
| Low / Info | 3 | Tick rounding, exact-input semantics, ERC1155 tokenId = orderId. |

---

*Report generated using Trail of Bits–style audit skills (entry-point analysis, audit context building, sharp edges).*
