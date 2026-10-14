# Aligned (ALIGN)

Aligned is a fixed-supply ERC-20 token. `src/Aligned.sol:Aligned` has a zero-argument
constructor that mints the entire supply once to `msg.sender`.

| Parameter | Value |
| --- | --- |
| Solidity contract | `Aligned` |
| Token name | `Aligned` |
| Token symbol | `ALIGN` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| Supply in base units | `1000000000000000000000000000` |
| Constructor arguments | None |
| Initial recipient | Immediate constructor caller |

## Behavior and assumptions

The contract uses the unmodified OpenZeppelin Contracts v5.1.0 ERC-20 implementation.
Transfers deliver exactly the requested base-unit amount and return `true` on success.
Invalid operations revert with ERC-6093 custom errors. Zero-value transfers are
valid and emit `Transfer`; transferring or approving to the zero address reverts.
Self-transfers preserve balances. Approvals replace the previous allowance;
finite allowances decrease when spent, while `type(uint256).max` allowances stay
unchanged. In this OpenZeppelin version, spending an allowance emits `Transfer`
without an additional `Approval` event.

The supply remains constant for the lifetime of each deployment. There are no
external mint or burn functions, owner, administrative roles, pause, blacklist,
taxes, fees, rebasing, proxy, upgrade mechanism, or receiver callbacks. The only
added code is the supply constant and constructor mint. The constructor makes no
external calls and needs no external addresses or service configuration.

## Build and check

Run these commands from the repository root with Foundry installed and Solidity
0.8.26 available:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x2bf3e9daa03712c67ccd2a59868591b30c4e9a624f37095118a2aff224596f42 forge test
forge fmt --check
```

`foundry.toml` pins Solidity 0.8.26, Cancun, optimization at 200 runs, and
`bytecode_hash = "none"`. All Solidity dependencies are included as ordinary
files under `lib/`; no package download, submodule initialization, RPC, wallet,
environment configuration, FFI, or filesystem cheatcodes are required by the
tests. The compiler and Foundry themselves are toolchain prerequisites.

The 28 tests cover metadata, constructor events, factory CREATE2 deployment,
exact transfers, full-balance and self-transfers, contract recipients, zero
amounts, approval overwrite/revocation, finite/infinite allowances, unauthorized
spending, insufficient balances/allowances, zero-address rejection, rollback on
failure, and rejection of common administrative entry points. Four fuzz tests
exercise transfer conservation, allowance accounting, overspending rejection,
and sequences of mixed transfers and delegated transfers. Each fuzz test runs
256 cases by default, with a fresh deployment per test case.

## Deployment and operations

Deploy the compiled `Aligned` creation bytecode with **no constructor arguments**
and no native currency. Under the specified Ethereum launch, the factory is the
immediate caller and receives all `1000000000000000000000000000` base units.
A direct deployment instead gives the entire supply to the account or contract
that executes CREATE/CREATE2; the token does not use `tx.origin` or forward tokens
to the transaction signer. The local factory test verifies this distinction.

The launch system is responsible for the later distribution, pool setup, manifest,
transaction execution, and explorer verification. This token has no launch
address dependencies, reserved allocations, or special transfer exemptions;
factory, distributor, pool manager, and trader transfers use identical ERC-20
rules. No application contracts are included or required.

After deployment, check the deployed bytecode and metadata, total supply, and
initial recipient balance before distribution. No initialization call or
owner-settable settings are needed. There is no administrator to maintain.
Holders are responsible for custody, recipient selection, and allowances.
Use approvals appropriate to the intended spend and revoke them when no longer
needed. When replacing a nonzero allowance for an untrusted spender, first
set it to zero and confirm that transaction before setting the new value to
reduce the usual ERC-20 approval race risk. Tokens sent to contracts unable to
transfer them, including the token itself, cannot be recovered by an admin.

## Review scope

Local validation uses Foundry build, unit/fuzz tests, and formatting checks.
The security reference was reviewed against this implementation: transfer and
approval paths make no external calls, arithmetic and input checks come from
the vendored ERC-20, and the deployed token exposes no privileged functions.
Slither and Mythril were not run. These checks are not an independent security
audit; independent review and deployed-source verification remain release
responsibilities of the launch operator.

## Vendored dependencies

- OpenZeppelin Contracts **v5.1.0**: only `ERC20.sol` and its transitive imports,
  plus the upstream MIT license, are included in `lib/openzeppelin-contracts/`.
  Source: `https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.1.0`.
- Forge Standard Library **v1.9.6**: upstream `src/` and licenses are included
  in `lib/forge-std/` for the tests.
  Source: `https://github.com/foundry-rs/forge-std/tree/v1.9.6`.

Vendored Solidity files are unmodified. Dependency licenses accompany the files.
