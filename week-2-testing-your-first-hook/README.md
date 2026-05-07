## The Tests

1. The "Blueprint" vs. The "Building"
ILoaderboard.sol (The Interface): This is just a definition. It tells the PointsHook what functions exist (like addUserToLeaderboard), but it contains zero logic. You cannot deploy an interface.
MockChainlinkFunctions.sol (The Implementation): This contains the actual code that handles the bubble sort, the top 10 logic, and the state variables.

2. Why we keep the Mock
Even though PointsHook only "sees" the interface, it still needs a real contract address to talk to during execution.

In Local Tests (PointsHook.t.sol): You deploy the Mock so that when the Hook calls addUserToLeaderboard, there is actual code to execute and actual storage to update. Without the mock, your tests would have no way to verify if rankings or points are working.
In Fork Tests (ForkTest.t.sol): You use the Mock's bytecode to "etch" over a real address. This allows you to simulate a complex off-chain system (Chainlink Functions) with a simple local script.

3. The Architecture Benefit
By using the interface in PointsHook.sol, you have made your contract "Future Proof."

When you go to production, you will create a new file (e.g., ChainlinkLeaderboard.sol) that actually handles the real Chainlink API calls. Because your hook uses ILoaderboard, you can swap the Mock for the Real contract at deployment time without changing a single line of code in your main Hook contract.

4. Test Features
**Decoupling**: PointsHook no longer cares how the leaderboard works, only that it follows the rules of the interface.
**Testability**: You can easily write different mocks (e.g., a mock that always returns Rank 1, or a mock that always reverts) to test how your Hook handles different scenarios.

## Foundry Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```
Specify a single contract to test

```shell
$ forge test --mc CounterTest
```

Specify a single function to test (verbose mode)

```shell
$ forge test --mt testIncrement -vv
```

Fork test

```shell
$ forge test --match-path test/ForkTest.t.sol --fork-url https://base-mainnet.g.alchemy.com/v2/YOUR_API_KEY -vv

```

`-v`: High-level summary.
`-vv`: Shows console.log output.
`-vvv`: Shows failure stack traces.
`-vvvv`: Shows stack traces for all tests (including passing ones).
`--watch`: Re-runs tests automatically every time you save a file.

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```

## Fuzzing

1. Using `bound()` and `clamp()` — clamp a fuzzed value into a safe range after it is generated

```typescript
function testFuzzIncrement_bound(uint times) public {
    // clamp times into range [0, 1000]. This maps the fuzz input into the range.
    times = bound(times, 0, 1000);
 
    // run increment `times` times (avoid excessively large loops in tests)
    for (uint i = 0; i < times; ++i) {
        counter.increment();
    }
 
    assertEq(counter.count(), times);
}
```

2. Using `vm.assume()` — reject generated inputs that don't meet preconditions so the fuzzer will keep trying other inputs

```typescript
function testFuzzIncrement_assume(uint times) public {
    // Assume times is small enough to keep this test fast
    vm.assume(times <= 1000);
 
    for (uint i = 0; i < times; ++i) {
        counter.increment();
    }
 
    assertEq(counter.count(), times);
}
```
Actions required to test in your fork environment:

1. Mine a contract address for our hook using HookMiner (from v4-hooks-public)
2. Deploy our hook contract