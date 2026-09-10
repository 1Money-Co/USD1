# <img src="logo.png" alt="1Money" height="28"> USD1

## What is USD1?

USD1 is a 6-decimal stablecoin issued by 1Money as an [M0 extension](https://docs.m0.org/build/extensions/).
Token name `1Money USD1`, symbol `USD1`. Users deposit M and receive USD1 one-to-one; the
yield the M backing earns is collected by a designated treasury.

Think of it like a savings account where you deposit dollars and get a receipt. The bank (treasury) earns the interest, and you can always withdraw your dollars using the receipt.

USD1 also includes compliance features: accounts can be frozen by a freeze manager, the contract can be paused, and tokens can be force-transferred from frozen accounts to support regulatory requirements.

### Relationship to 1USD

1Money also issues [1USD](https://github.com/1Money-Co/1USD), an M0 extension built from the
same library snapshot with the same behavior. The two are separate tokens with different
names, symbols, proxy addresses, and role holders, backed by the same M token through the
same SwapFacility. Nothing on-chain links them. Integrations must identify each token by
chain and contract address, never by name.

## Contract Architecture

USD1 is built on M0's [Extension framework](https://docs.m0.org/build/extensions/). The production contract is a single file that inherits from M0's library:

```
src/v1/USD1.sol (USD1)
  └── MYieldToOneForcedTransfer  (lib: evm-m-extensions)
        ├── MYieldToOne           — ERC20 token with yield-to-one-recipient model
        │     ├── MExtension      — Base M Extension (wrap/unwrap M, earning)
        │     ├── Freezable       — Account freeze/unfreeze
        │     └── Pausable        — Contract pause/unpause
        └── ForcedTransferable    — Force transfer from frozen accounts
```

**What USD1 adds on top of the library:** A single override — `_beforeClaimYield()` — that restricts yield claiming to accounts with `YIELD_RECIPIENT_MANAGER_ROLE`. In the base library, `claimYield()` is callable by anyone. USD1 makes it permissioned, and this also allows yield to be claimed even when the contract is paused.

The M0 library is vendored under `lib/evm-m-extensions` as plain files, byte-identical to
the copy that backs live 1USD (upstream `m0-foundation/evm-m-extensions` at commit
`bd27438`, `common` at v1.4.0). See `docs/specs/2026-09-03-usd1-m0-extension-design.md`
for what was copied and why.

### How It Works

```
User M/wM ──> SwapFacility ──> USD1 Extension Token
                                    |
                              Yield Generated
                                    |
                                    v
                               Treasury
```

1. **Deposit:** Users swap M or wM (Wrapped M) for USD1 via M0's [SwapFacility](https://docs.m0.org/build/extensions/core-components/swapfacility). The extension contract holds the M tokens as backing.
2. **Yield accrual:** The held M tokens earn yield from the M0 protocol. This yield accrues in the extension contract as excess M balance above `totalSupply`.
3. **Yield claiming:** A permissioned manager calls `claimYield()`, which mints USD1 tokens equal to the accrued yield and sends them to the treasury address.
4. **Redemption:** Users swap USD1 back for M or wM at any time via the SwapFacility.

### Deployment Model

USD1 is deployed as a **TransparentUpgradeableProxy** (OpenZeppelin) via the CreateX CREATE3 factory for deterministic addresses across chains. The salt is `bytes20(deployer) ‖ 0x00 ‖ bytes11(keccak256("USD1"))`, so one deployer produces the same USD1 proxy address on every chain, and a different address from 1USD (whose salt name is `OneUSD`). The deployment script (`script/v1/Deploy.s.sol`) handles both implementation and proxy deployment.

## Actors and Roles

The contract uses OpenZeppelin's `AccessControl`. All roles are assigned at initialization and managed by the admin.

| Actor | Role | Can Do | Cannot Do |
|-------|------|--------|-----------|
| **Admin** | `DEFAULT_ADMIN_ROLE` | Grant/revoke any role, including granting `DEFAULT_ADMIN_ROLE` to another address; enable/disable M earning | Cannot directly freeze, pause, claim yield, or force transfer without also holding those specific roles |
| **Freeze Manager** | `FREEZE_MANAGER_ROLE` | Freeze and unfreeze individual accounts or batches. Frozen accounts cannot send, receive, or approve tokens | Cannot pause the contract, claim yield, or force transfer |
| **Yield Recipient Manager** | `YIELD_RECIPIENT_MANAGER_ROLE` | Call `claimYield()` to mint accrued yield to treasury; call `setYieldRecipient()` to change the treasury address (this auto-claims pending yield first). Can claim yield even when the contract is paused | Cannot freeze accounts, pause, or force transfer |
| **Pauser** | `PAUSER_ROLE` | Pause and unpause the contract. When paused: transfers, wrapping (deposit), and unwrapping (redeem) are blocked | Cannot freeze accounts, claim yield, or force transfer. Pausing does NOT block yield claiming |
| **Forced Transfer Manager** | `FORCED_TRANSFER_MANAGER_ROLE` | Force transfer tokens from frozen accounts to any valid recipient (single or batch). Bypasses pause and freeze checks on the recipient | Can only transfer FROM frozen accounts. Cannot freeze/unfreeze, pause, or claim yield |
| **Token Holder** | (none) | Transfer tokens (if not frozen/paused), approve spenders, redeem for M via SwapFacility | Cannot claim yield, freeze, pause, or force transfer |

### Key Functions

| Function | Access | Description |
|----------|--------|-------------|
| `claimYield()` | `YIELD_RECIPIENT_MANAGER_ROLE` | Mint accumulated yield to treasury |
| `yield()` | Public (view) | View current accumulated yield |
| `yieldRecipient()` | Public (view) | View yield recipient (treasury) address |
| `setYieldRecipient(address)` | `YIELD_RECIPIENT_MANAGER_ROLE` | Change treasury address (auto-claims first) |
| `forceTransfer(address, address, uint256)` | `FORCED_TRANSFER_MANAGER_ROLE` | Seize tokens from a frozen account |
| `forceTransfers(address[], address[], uint256[])` | `FORCED_TRANSFER_MANAGER_ROLE` | Batch seize from frozen accounts |
| `freeze(address)` / `freezeAccounts(address[])` | `FREEZE_MANAGER_ROLE` | Freeze account(s) |
| `unfreeze(address)` / `unfreezeAccounts(address[])` | `FREEZE_MANAGER_ROLE` | Unfreeze account(s) |
| `pause()` / `unpause()` | `PAUSER_ROLE` | Pause/unpause the contract |
| `enableEarning()` / `disableEarning()` | `DEFAULT_ADMIN_ROLE` | Enable/disable M yield earning |

## Development

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (tested with v1.5.1)
- Node 20+ for the upgrade-safety validator (`npx`)
- [Semgrep CE](https://semgrep.dev/) for the security scan

### Installation

Dependencies are vendored under `lib/`; there are no git submodules.

```bash
git clone https://github.com/1Money-Co/USD1.git
cd USD1
```

### Build

```bash
forge build
```

### Test

```bash
# Run all tests
forge test -vvv

# Run a specific test
forge test --match-test test_ClaimYield_WhilePaused -vvv
```

### Coverage

```bash
# The --ir-minimum flag is required because the project uses via_ir = true
forge coverage --ir-minimum
```

Expected output for `src/v1/USD1.sol`: 100% across lines, statements, branches, and functions.

### Upgrade safety

The implementation sits behind a transparent proxy, so every change to it is checked with
OpenZeppelin's validator. The two allowances are inherent to M0's pattern of fixing the M
token and SwapFacility as constructor immutables. Run it on a full build; if it reports
`Build info file ... is not from a full compilation`, run `forge clean && forge build` and retry.

```bash
forge build
npx --yes @openzeppelin/upgrades-core@1.37.0 validate out/build-info \
  --contract src/v1/USD1.sol:USD1 \
  --unsafeAllow constructor,state-variable-immutable
```

### Security scan

Static analysis with [Semgrep CE](https://semgrep.dev/), using the `solidity/security`
rules from [semgrep/semgrep-rules](https://github.com/semgrep/semgrep-rules) at a pinned
commit. The same script runs locally and in CI, so a local pass means a CI pass.

```bash
# Install semgrep (once)
python3 -m pip install --user semgrep

# Scan the repo — blocks on ERROR-severity findings
./.github/scripts/security-scan.sh

# Prove the ruleset still detects planted vulnerabilities
./.github/scripts/security-scan.sh --canary
```

Scope: every git-tracked `.sol` file outside `lib/` (vendored upstream code) and `test/`
(Foundry mocks trip these rules on purpose). The scan asserts that each of those files
was both scanned *and* parsed — semgrep counts a file it failed to parse as "scanned"
and still exits 0, so without that assertion a Solidity construct its grammar does not
yet handle would go silently uninspected.

To update the ruleset, bump `RULES_SHA` in `.github/scripts/security-scan.sh` and re-run
the canary.

## Project Structure

```
src/
  v1/USD1.sol               # The M0 extension token
script/
  v1/Deploy.s.sol           # Implementation and CREATE3 proxy deployment
  testnet/                  # Testnet-only interaction scripts (not production code)
    Admin.s.sol
    Swap.s.sol
    Faucet.sol
    interfaces/
test/
  v1/USD1.t.sol             # Unit tests
  v1/DeployUSD1.t.sol       # Deploy script run against a local CREATE3 factory
lib/                        # Vendored dependencies (plain files, no submodules)
  evm-m-extensions/         # M0 Extension framework (MYieldToOneForcedTransfer, etc.)
  forge-std/                # Foundry test framework
  openzeppelin-contracts/   # OpenZeppelin
docs/
  specs/                    # Design documents
  plans/                    # Implementation plans
.github/
  scripts/
    security-scan.sh        # Semgrep SAST — same ruleset locally and in CI
  workflows/
    test.yml                # fmt, build, upgrade-safety validation, tests
    semgrep.yml             # Semgrep SAST gate
```

## Deployments

### Ethereum Mainnet

Deployed on Ethereum mainnet (chain ID `1`) through Palisade external signing.
The implementation, transparent proxy, and ProxyAdmin are verified on Etherscan;
the proxy is linked to the `USD1` implementation from `src/v1/USD1.sol`.

| Contract | Address |
|----------|---------|
| **USD1 Extension** (proxy — use this) | [`0xfEa9182A59861Eb4a8c9a808304a4E8b67932f11`](https://etherscan.io/address/0xfEa9182A59861Eb4a8c9a808304a4E8b67932f11#code) |
| Implementation (`USD1`) | [`0xe5ef1269c11426d3E9965588236f2be54c9B3A48`](https://etherscan.io/address/0xe5ef1269c11426d3E9965588236f2be54c9B3A48#code) |
| ProxyAdmin | [`0x0618bBfC551C7f29848a131269C165A59AbD86d2`](https://etherscan.io/address/0x0618bBfC551C7f29848a131269C165A59AbD86d2#code) |

Token config: name `1Money USD1`, symbol `USD1`, decimals `6`.

#### Release Transactions (Mainnet)

Both transactions were sent by deployer
[`0x0543b6fbf0855d601eBe9d430e3a49f2f035e2FB`](https://etherscan.io/address/0x0543b6fbf0855d601eBe9d430e3a49f2f035e2FB)
and confirmed successfully.

| Transaction | Nonce | Block | Hash |
|-------------|-------|-------|------|
| TX1 — deploy USD1 implementation | `0` | `25940044` | [`0x8076991fcd44dfb04867ff4c2780ca6095314e0b3fd49dd0cba4cf61d057600c`](https://etherscan.io/tx/0x8076991fcd44dfb04867ff4c2780ca6095314e0b3fd49dd0cba4cf61d057600c) |
| TX2 — deploy and initialize proxy via CreateX CREATE3 | `1` | `25940115` | [`0xfad8140eb59b8e51862b402fd77779f7fc2b543aa2e1415552301700f1500f9e`](https://etherscan.io/tx/0xfad8140eb59b8e51862b402fd77779f7fc2b543aa2e1415552301700f1500f9e) |

TX2 calls CreateX at `0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed` and initializes
the proxy atomically. These release transactions have consumed nonces `0` and `1`;
their unsigned payloads must not be reused for another deployment.

#### Role Assignments (Mainnet)

Assignments at deployment, as encoded in TX2:

| Role / Config | Address |
|---------------|---------|
| `DEFAULT_ADMIN_ROLE` | `0x0543b6fbf0855d601eBe9d430e3a49f2f035e2FB` |
| `FREEZE_MANAGER_ROLE` | `0x0543b6fbf0855d601eBe9d430e3a49f2f035e2FB` |
| `YIELD_RECIPIENT_MANAGER_ROLE` | `0xf70a1Ea3F554B3570b5Ef166Bd57d2c8fBB7330A` |
| `PAUSER_ROLE` | `0x0543b6fbf0855d601eBe9d430e3a49f2f035e2FB` |
| `FORCED_TRANSFER_MANAGER_ROLE` | `0x0543b6fbf0855d601eBe9d430e3a49f2f035e2FB` |
| Yield Recipient / treasury (config, not a role) | `0xf70a1Ea3F554B3570b5Ef166Bd57d2c8fBB7330A` |
| ProxyAdmin owner (controls upgrades) | `0x0543b6fbf0855d601eBe9d430e3a49f2f035e2FB` |

The treasury and yield manager use the same address in this release. M0 earner
approval, SwapFacility listing, and enabling earning are separate from these
deployment transactions; see [Post-deployment prerequisites](#post-deployment-prerequisites).

### M0 Protocol Contracts (Mainnet)

| Contract | Address |
|----------|---------|
| M Token | [`0x866A2BF4E572CbcF37D5071A7a58503Bfb36be1b`](https://etherscan.io/address/0x866A2BF4E572CbcF37D5071A7a58503Bfb36be1b) |
| Swap Facility | [`0xB6807116b3B1B321a390594e31ECD6e0076f6278`](https://etherscan.io/address/0xB6807116b3B1B321a390594e31ECD6e0076f6278) |
| Minter Gateway | [`0xf7f9638cb444D65e5A40bF5ff98ebE4ff319F04E`](https://etherscan.io/address/0xf7f9638cb444D65e5A40bF5ff98ebE4ff319F04E) |
| Validators | [`0xEe4d4938296E3BD4cD166b9b35EE1B8FeD2F93C1`](https://etherscan.io/address/0xEe4d4938296E3BD4cD166b9b35EE1B8FeD2F93C1) |
| USTB Chainlink Oracle | [`0x289B5036cd942e619E1Ee48670F98d214E745AAC`](https://etherscan.io/address/0x289B5036cd942e619E1Ee48670F98d214E745AAC) |

### Sepolia

> Not yet deployed. Fill in after deployment and verification.

| Contract | Address |
|----------|---------|
| USD1 Extension | _pending_ |
| Implementation | _pending_ |
| ProxyAdmin | _pending_ |

### M0 Protocol Contracts (Testnet)

| Contract | Sepolia | Arbitrum Sepolia |
|----------|---------|------------------|
| M Token | `0x866A2BF4E572CbcF37D5071A7a58503Bfb36be1b` | `0x866A2BF4E572CbcF37D5071A7a58503Bfb36be1b` |
| Swap Facility | `0xB6807116b3B1B321a390594e31ECD6e0076f6278` | `0xB6807116b3B1B321a390594e31ECD6e0076f6278` |
| Minter Gateway | `0x4eDfcfB5F9e55962EF1A2eEf0b56A8FaDbaBA289` | — |
| Validators | `0x827C1F791770063773e213864f0FA16e575cD3c7` | — |
| USTB Chainlink Oracle | `0x732d3C7515356eAB22E3F3DcA183c5c65102d518` | — |
| Wrapped M | `0x437cc33344a0B27A429f795ff6B469C72698B291` | `0x437cc33344a0B27A429f795ff6B469C72698B291` |
| M Token Faucet | `0x7017C274fe0d4614608070df98Fcd405348D4D95` | — |

## Deployment

The deploy script refuses to run on any chain other than Ethereum mainnet (1), Sepolia
(11155111), Arbitrum Sepolia (421614), or OP Sepolia (11155420), because those are the
chains where the M token and SwapFacility are known to live at the addresses it uses.

### Post-deployment prerequisites

Deploying the proxy is not enough for USD1 to work. Before `enableEarning()` can succeed
and before users can wrap M into USD1, M0 must:

1. Approve the USD1 proxy address as an earner (the TTG `earners` list on the Registrar).
2. List the USD1 proxy on the SwapFacility as a permissioned extension.

Both are M0 governance actions, not something this repo can perform. On testnet,
`script/testnet/Admin.s.sol`'s `isApprovedEarner` and `getExtensionStatus` show whether
they have happened.

### Sepolia

```bash
export DEPLOYER_ADDRESS=0x...
# plus the role addresses from .env.example

forge script script/v1/Deploy.s.sol:Deploy \
  --rpc-url sepolia \
  --sender $DEPLOYER_ADDRESS \
  --broadcast \
  --verify
```

### Mainnet (External Signing)

Mainnet deployments are signed by an external service (Palisade). Generate the unsigned
transaction data without a private key:

```bash
# Step 1: Set environment variables for role addresses
export DEPLOYER_ADDRESS=0x...
export ADMIN_ADDRESS=0x...
export YIELD_RECIPIENT_ADDRESS=0x...
export YIELD_RECIPIENT_MANAGER_ADDRESS=0x...
export FREEZE_MANAGER_ADDRESS=0x...
export PAUSER_ADDRESS=0x...
export FORCED_TRANSFER_MANAGER_ADDRESS=0x...

# Step 2: Simulate deployment to generate transaction data (no signing)
forge script script/v1/Deploy.s.sol:Deploy \
  --rpc-url mainnet \
  --sender $DEPLOYER_ADDRESS

# Step 3: View generated transaction data
cat broadcast/Deploy.s.sol/1/dry-run/run-latest.json | jq '.transactions'
```

Output contains all required fields for signing:

```json
[
  {
    "transactionType": "CREATE",
    "contractAddress": "0x...",
    "data": "0x608060...",
    "value": "0x0",
    "nonce": 0
  }
]
```

Alternatively, print the CreateX calldata for the proxy directly, given an already
deployed implementation:

```bash
forge script script/v1/Deploy.s.sol:Deploy \
  --sig "generateProxyDeployInput(address)" <IMPLEMENTATION> \
  --rpc-url mainnet
```

Provide the `data`, `value`, and target info to your signing service.

#### Palisade raw signing

Palisade's raw-signing input is **not** calldata and **not** an ordinary raw transaction —
it is the output of go-ethereum's `rlp.EncodeToBytes(types.Transaction)`:

```
RLP( 0x02 ‖ RLP([chainId, nonce, maxPriorityFeePerGas, maxFeePerGas,
                 gas, to, value, data, accessList, v, r, s]) )
```

Three details, each of which produces `PAL010.011 invalid encoded transaction` when wrong:

- **v/r/s are present and zero.** Twelve inner fields, not nine.
- **An outer RLP byte-string wraps the `0x02` envelope.** This is not the bare
  `MarshalBinary` form that `eth_sendRawTransaction` accepts.
- **Hex with no `0x` prefix.** All three variants were tested against the Palisade sandbox
  API; only the unprefixed, doubly-wrapped form returned `200`.

`scp-core`'s `scp-web3::evm::rlp::encode_eip1559_tx` is the reference implementation and is
covered by tests pinning each of these properties.

Palisade fills in nothing — nonce, gas, and fees are committed by the signature, so they must
be correct before signing. Regenerate if the signing address sends anything in between.
Contract creation (empty `to`) is supported. Destination addresses must be registered in the
Palisade address book; that check happens after parsing, so a policy rejection looks nothing
like an encoding rejection.

### Verification

```bash
# Implementation
forge verify-contract <IMPLEMENTATION> src/v1/USD1.sol:USD1 \
  --chain mainnet \
  --constructor-args $(cast abi-encode "constructor(address,address)" \
    0x866A2BF4E572CbcF37D5071A7a58503Bfb36be1b 0xB6807116b3B1B321a390594e31ECD6e0076f6278) \
  --watch

# Proxy. The script deploys OpenZeppelin 5.3.0's TransparentUpgradeableProxy from the nested
# path below, not the top-level 5.5.0 copy. <INIT_DATA> is the "Initializer Data" printed by
# generateProxyDeployInput.
forge verify-contract <PROXY> \
  lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy \
  --chain mainnet \
  --constructor-args $(cast abi-encode "constructor(address,address,bytes)" <IMPLEMENTATION> <ADMIN_ADDRESS> <INIT_DATA>) \
  --watch
```

## Testnet Interaction Scripts

Helper scripts for testnet interaction live in `script/testnet/`. These are **not** production contracts — they are convenience wrappers for manual testing on Sepolia, Arbitrum Sepolia, and OP Sepolia. Each takes the signing key as a function argument.

| Script | Purpose |
|--------|---------|
| `testnet/Admin.s.sol` | Enable/disable earning, claim yield, freeze/unfreeze, pause/unpause, status checks |
| `testnet/Swap.s.sol` | Swap M/wM to/from USD1 via the SwapFacility |
| `testnet/Faucet.sol` | Get M from the faucet and wrap to wM |

Run any script with no `--sig` to print its usage, for example:

```bash
forge script script/testnet/Admin.s.sol --rpc-url sepolia
```

## Resources

- [M0 Documentation](https://docs.m0.org)
- [M Extensions Guide](https://docs.m0.org/build/extensions/)
- [SwapFacility](https://docs.m0.org/build/extensions/core-components/swapfacility)
- [Foundry Book](https://book.getfoundry.sh/)
