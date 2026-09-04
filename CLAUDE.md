# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Foundry project for USD1, a 1Money stablecoin built as an M0 extension. One production
contract, `src/v1/USD1.sol`, subclasses M0's `MYieldToOneForcedTransfer` with a single
override. It behaves exactly like 1Money's live 1USD v1; the design record is
`docs/specs/2026-09-03-usd1-m0-extension-design.md`.

## Common Commands

```bash
# Build contracts
forge build

# Run all tests
forge test

# Run tests with verbosity (useful for debugging)
forge test -vvv

# Run a specific test file
forge test --match-path test/v1/USD1.t.sol

# Run a specific test function
forge test --match-test test_ClaimYield_WhilePaused

# Format Solidity code
forge fmt

# Check formatting without modifying
forge fmt --check

# Coverage (--ir-minimum is required because via_ir = true)
forge coverage --ir-minimum

# Upgrade-safety validation (same command as CI). Needs a full build: if it reports
# "not from a full compilation", run `forge clean && forge build` first.
forge build && npx --yes @openzeppelin/upgrades-core@1.37.0 validate out/build-info \
  --contract src/v1/USD1.sol:USD1 --unsafeAllow constructor,state-variable-immutable

# Security scan (same ruleset as CI) and its canary
./.github/scripts/security-scan.sh
./.github/scripts/security-scan.sh --canary

# Deploy script (dry run for external signing)
forge script script/v1/Deploy.s.sol:Deploy --rpc-url <alias> --sender <DEPLOYER_ADDRESS>
```

## Project Structure

- `src/v1/` - The production contract
- `script/v1/` - Deployment script (`.s.sol`)
- `script/testnet/` - Testnet-only helpers, not production code
- `test/v1/` - Unit tests and the deploy-script test (`.t.sol`)
- `lib/` - Vendored dependencies as plain tracked files. **There are no git submodules.**
- `docs/specs/` and `docs/plans/` - Design documents and implementation plans

## Dependencies

`lib/evm-m-extensions`, `lib/forge-std`, and `lib/openzeppelin-contracts` are copied
byte-for-byte from `1Money-Co/1USD` at commit `6ac7629`, with six unused subtrees removed.
The M0 code matches upstream `m0-foundation/evm-m-extensions` at `bd27438`. Do not run
`forge install` or `forge update`, and do not edit anything under `lib/`. Updating a
dependency means copying a new snapshot in, recording its provenance in a spec, and
re-reviewing behavior, because upstream M0 has changed `MYieldToOneForcedTransfer` since
this snapshot.

## Testing Conventions

- Test contracts inherit from `forge-std/Test.sol`
- Test functions are prefixed with `test_` for unit tests
- Fuzz tests are prefixed with `testFuzz_`
- Use `setUp()` for test initialization
- `test/v1/DeployUSD1.t.sol` pins every env variable the deploy script reads with
  `vm.setEnv`, because Foundry loads `.env` into `forge test`. Keep it that way. The
  twelve `note[unsafe-cheatcode]` entries `forge lint` reports for those calls are expected.

## CI Requirements

`test.yml` runs:
1. `forge fmt --check` - Code must be formatted
2. `forge build --sizes` - Build with contract size output
3. OpenZeppelin upgrades-core validation of `src/v1/USD1.sol:USD1` with
   `--unsafeAllow constructor,state-variable-immutable` (both inherent to M0's
   constructor-set immutables; do not add more without recording why)
4. `forge test -vvv` - All tests must pass

`semgrep.yml` runs Semgrep SAST on pull requests and pushes to `main`, and blocks
on ERROR-severity findings. Reproduce it locally with:

```bash
./.github/scripts/security-scan.sh            # scan (same ruleset as CI)
./.github/scripts/security-scan.sh --canary   # prove the ruleset still detects
```

Scope is every git-tracked `.sol` file outside `lib/` and `test/`. Two guards mean
this gate cannot silently pass: a canary of planted vulnerabilities that must trip
5 named rules, and a coverage assertion that every in-scope file was scanned *and*
parsed. Do not weaken either — semgrep reports an unparseable file as "scanned"
and exits 0, so without them a broken gate is indistinguishable from clean code.

## Interface Reuse Rules

**IMPORTANT:** Always reuse interfaces from the vendored M0 library before creating local copies.

1. Check `lib/evm-m-extensions/src/` for existing interfaces
2. Use `remappings.txt` paths (e.g., `evm-m-extensions/src/interfaces/IMExtension.sol`)
3. Only create local interfaces under `script/testnet/interfaces/` when:
   - No library equivalent exists (e.g., `IMTokenFaucet.sol`)
   - The library interface needs extension (e.g., `IPausableExtended.sol` adds `paused()`)
   - The upstream library is not vendored (e.g., `IWrappedMTokenLike.sol`)

Key library interface paths:
- `evm-m-extensions/src/interfaces/IMExtension.sol`
- `evm-m-extensions/src/projects/yieldToOne/interfaces/IMYieldToOne.sol`
- `evm-m-extensions/src/swap/interfaces/ISwapFacility.sol`
- `evm-m-extensions/src/swap/interfaces/IRegistrarLike.sol`
- `evm-m-extensions/src/components/freezable/IFreezable.sol`
- `evm-m-extensions/src/components/pausable/IPausable.sol`
- `evm-m-extensions/src/components/forcedTransferable/IForcedTransferable.sol`

## Deployment Context

The owner deploys through Palisade external signing and operates the contract from a
separate program (`scp-core`). Keep the `--sender` dry-run flow and
`generateProxyDeployInput` output of `script/v1/Deploy.s.sol` stable; both are consumed
downstream.
