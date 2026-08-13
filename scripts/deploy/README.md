# Astroport deploy scripts (Coreum)

Two files do the work:

- `lib.sh` — transaction wrappers, idempotency, deploy log
- `deploy.sh` — contract table, modes, argument parsing

Nothing is deployed without an explicit selection. `deploy.sh` with no
arguments refuses to run: the duplicate factory and pair currently on testnet
came from an unguarded full run of the old lendore bringup script.

## Before you start

1. **Build the artifacts.** The script reads `artifacts/*.wasm` and fails with a
   clear message if one is missing:

   ```bash
   ./scripts/build_release.sh
   ```

   This runs the cosmwasm optimizer in Docker, so Docker has to be running. It
   builds every contract in the workspace; there is no way to build a single
   one.

   The `-coreum` artifacts are not produced by a flag. Each contract that has a
   Coreum variant declares it in its own `Cargo.toml`:

   ```toml
   [package.metadata.optimizer]
   standard-build = true
   builds = [{ name = "coreum", features = ["coreum"] }]
   ```

   The optimizer reads that and emits both `astroport_pair.wasm` and
   `astroport_pair-coreum.wasm`. A contract without that block gets one
   artifact and no `-coreum` name — which is why registry, whitelist, tracker
   and oracle have none.

2. **Configure.**

   ```bash
   cp scripts/deploy/.env.example scripts/deploy/.env
   $EDITOR scripts/deploy/.env
   ```

   At minimum `ASTRO_DEPLOYER_KEY_NAME`. The tokenomics contracts additionally
   need `ASTRO_TOKEN_DENOM`. `.env` is gitignored.

3. **Check `cored` and funds.**

   ```bash
   cored keys show <your-key> --keyring-backend file
   cored query bank balances <address> --node https://full-node.testnet-1.coreum.dev:26657
   ```

## Usage

```bash
./scripts/deploy/deploy.sh --list                      # what can be deployed
./scripts/deploy/deploy.sh --only registry --dry-run   # inspect before signing
./scripts/deploy/deploy.sh --only registry,factory,pair
```

Always dry-run first. It prints every transaction and validates each init
message as JSON without broadcasting anything.

### Options

| Option | Effect |
| --- | --- |
| `--only a,b,c` | Deploy these contracts, in table order |
| `--all` | Deploy everything in the table |
| `--migrate` | Migrate the live pairs (see below) |
| `--migrate-factories <spec>` | Point factories at new pair code ids (see below) |
| `--store-only` | Upload wasm, skip every instantiate |
| `--resume <log>` | Reuse code ids and addresses from a previous run |
| `--dry-run` | Print transactions, broadcast nothing |
| `--list` | Show the contract table |

Selection order follows the table, not your argument order, so dependencies are
deployed before the contracts referencing them.

## Contracts

`--list` prints the authoritative table. Two things in it are easy to get wrong
by hand:

**Four contracts have no `-coreum` artifact** — registry, whitelist, tracker and
oracle contain no token-factory code. The table already carries the right
filename per contract.

**Five contracts are store-only.** The three pair types are instantiated by the
factory, the tracker by the staking contract, and the whitelist is held by the
factory as a code id. For these, "deploy" means upload and record the code id.

The pair wasms are listed before the factory on purpose: storing them first
lets the factory be instantiated with a populated `pair_configs` instead of an
empty one that needs `UpdatePairConfig` afterwards.

## Dependencies

Most contracts stand alone. Three couplings matter:

**Coin registry is required, not optional.** Pair contracts query it during
swaps via `query_token_precision`. A pool whose denom is not registered fails on
chain. Set `ASTRO_REGISTER_COINS` when deploying the registry; the script warns
if you don't.

**Factory and incentives are circular.** The factory's `generator_address`
points at incentives, whose `factory` points back. The script deploys the
factory with `generator_address: null` and sends `UpdateConfig` afterwards —
safe because every field of that message is optional.

**Deploying against an existing stack.** To deploy just the router against a
live factory, set `ASTRO_FACTORY_ADDR` in `.env` rather than redeploying, or
pass `--resume` with the earlier log.

## How the script learns about existing contracts

Three sources, applied in this order, each overriding the one before:

1. **`--resume <log>`** — a previous run's JSON log. Richest source: it carries
   both code ids and addresses for every contract it deployed. The resume file
   is only read, never written.
2. **`.env` address variables** — `ASTRO_FACTORY_ADDR`, `ASTRO_REGISTRY_ADDR`,
   `ASTRO_VESTING_ADDR`, `ASTRO_STAKING_ADDR`. Addresses only, no code ids, and
   only for these four. Enough to deploy a dependent contract against a live
   stack with no log at all.
3. **This run** — anything deployed in the current invocation.

Because `.env` outranks the resume log, an address pinned there wins over one
that was just deployed. That is deliberate for the common case (`--only router`
against a live factory), but note the consequence for `--only registry`: the
coin-decimal registration targets `ASTRO_REGISTRY_ADDR`, not the registry the
same run just created. Clear that variable when the intent is to populate a
fresh registry.

Anything outside those four keys — incentives, maker, the pair code ids — has
no `.env` equivalent and must come from `--resume` or the same run. `need_addr`
and `need_code` fail with the missing key named rather than emitting an init
message containing an empty string.

Note that the real environment always wins over `.env`, so a one-off override
works as expected:

```bash
ASTRO_FACTORY_ADDR=testcore1other... ./scripts/deploy/deploy.sh --only router
```

## Migration mode

`--migrate` exists for one specific fix: `MsgBurn.coin` was encoded on protobuf
tag 2, and Coreum expects tag 3. wasmd drops unknown fields silently, so the
burn reached the chain with an empty coin and `withdraw_liquidity` failed with
`invalid denom:`.

```bash
./scripts/deploy/deploy.sh --migrate --dry-run   # inspect first
./scripts/deploy/deploy.sh --migrate
```

This stores the fixed pair wasm, prechecks each pair, then migrates the live
pairs. It deliberately **stops there** and does not touch the factories.

The precheck reads the chain instead of simulating a transaction, verifying
that the contract has an admin, that the admin is you, that it really is an
`astroport-pair`, and that its cw2 version is one the new code's `migrate`
accepts. `cored tx wasm migrate --dry-run` cannot be used for this: on
cosmos-sdk v0.50 it resolves `--from` against the keyring even in simulation
mode, and fails on both a key name (bech32 decode error) and an address
(`.info: key not found`).

### Why it stops

Rolling back is impossible. The currently deployed pair code has
`unimplemented!()` as its migrate entry point, so there is no path back to it
once you migrate away. The only real proof the fix works is a withdrawal:

```bash
cored tx wasm execute <pair> \
  '{"withdraw_liquidity":{}}' \
  --amount <small-amount>factory/<pair>/astroport/share \
  --from <key> --gas auto --gas-adjustment 1.4 \
  --chain-id coreum-testnet-1 --node $ASTRO_NODE
```

Once that succeeds, point the factories at the new code ids:

```bash
./scripts/deploy/deploy.sh --migrate-factories xyk=3872,stable=3873,concentrated=3874 --dry-run
./scripts/deploy/deploy.sh --migrate-factories xyk=3872,stable=3873,concentrated=3874
```

Valid types are `xyk`, `stable` and `concentrated`. A bare code id is still
accepted and means xyk only, so the earlier single-type form keeps working:

```bash
./scripts/deploy/deploy.sh --migrate-factories 3872
```

**All three types need this, not just xyk.** Each factory carries a separate
`PairConfig` per pair type, and `CreatePair` reads the code id fresh from that
entry every time. Leaving `stable` and `concentrated` pointed at pre-fix code
means any stable or PCL pair created later ships the `MsgBurn` bug again, even
though xyk pairs are fine.

The whole argument is validated before the first transaction goes out — an
unknown type, a non-numeric code id or a repeated type aborts with nothing
broadcast, rather than surfacing after the first two updates have landed.

Each update restates the full `PairConfig` struct, every field of it.
`UpdatePairConfig` overwrites rather than merges, so omitting `total_fee_bps`
or `maker_fee_bps` would silently reset a 30 bps pool to zero fees. Fee values
come from the per-type variables in `.env`
(`ASTRO_XYK_TOTAL_FEE_BPS`, `ASTRO_STABLE_TOTAL_FEE_BPS`, and so on); the
defaults match what is live on testnet today.

Which factories are targeted comes from `ASTRO_MIGRATE_FACTORIES`, which
defaults to **both** factory A and factory B. Since nothing depends on factory
B, set it to factory A alone to leave the duplicate untouched:

```bash
ASTRO_MIGRATE_FACTORIES=testcore1j50sat6r0r6g9fypx8xg2e8dhd9m92sl6gj94z5xwy724y9km37q5g8ykc \
  ./scripts/deploy/deploy.sh --migrate-factories xyk=3872,stable=3873,concentrated=3874
```

Note that `permissioned` and `whitelist` carry `#[serde(default)]`, so leaving
them out would deserialize rather than error. The script sends them anyway --
a silent default is what resets fees, and this message is the wrong place to
trust one.

Migrating the pairs repairs existing pools; updating the factory config means
newly created pairs get the fix too. Both are needed.

## Deploy log and resuming

Each run writes `deployments/<chain-id>/deploy_<timestamp>.json` recording every
code id, address and completed wiring step. To continue an interrupted run:

```bash
./scripts/deploy/deploy.sh --only factory,router \
  --resume deployments/coreum-testnet-1/deploy_20260101_120000.json
```

Anything already recorded is skipped and reused; only gaps are filled. The
resume file is read, never written — a new log is always created, so a failed
retry cannot corrupt the record of a successful run.

## Verifying a migration

```bash
cored query wasm contract-state raw <pair> contract_info --ascii \
  --node $ASTRO_NODE --output json | jq -r '.data' | base64 -d
```

Expect `{"contract":"astroport-pair","version":"2.2.1"}`.

The migrate entry point accepts only an exact prior version, so re-running a
migration on an already-migrated pair fails loudly instead of silently
succeeding — useful when you lose track partway through a multi-pair rollout.

After `--migrate-factories`, query `{"config":{}}` on each factory and confirm
every updated entry shows the new code id **and** still has its fees:

| pair_type | expected fees (total / maker) |
| --- | --- |
| `xyk` | 30 / 3333 |
| `stable` | 5 / 5000 |
| `custom("concentrated")` | 0 / 5000 |

A zero where a fee should be is the failure mode to look for — it deserializes
happily and only shows up as pools trading for free.

## Live on coreum-testnet-1

Verified on chain after the rollout of 2026-08-08, not copied from a run log.

| contract | address | code id |
| --- | --- | --- |
| factory A | `testcore1j50sat6r0r6g9fypx8xg2e8dhd9m92sl6gj94z5xwy724y9km37q5g8ykc` | — |
| factory B | `testcore135e9xywpd2lzdh8unh28z3m3hljy9qq0nn8rrngzurelgj8s9f6qd03hpp` | — |
| registry A | `testcore1xdqye2qh386t49qwyj49z0nkunmnz3dd3qfp9apw6fpeznc4juas86ktga` | — |
| pair TX/USDC | `testcore1awuq9dc39uwvr8a4jckpx48luxp34pd7pjdykmjp6r7gu3g6n2fq32c027` | 3862 |
| pair (second) | `testcore13lk84u23d7fq2f6cuswll9n7e6ypu548dgejr39x8n8fl7a2hagswacz28` | 3862 |
| router | `testcore1yc4fn6lk30eqjdl6gt72cqpfdf4365rfx0p4qzgk4z37yyw8sfgsysly8a` | — |
| vesting | `testcore1d8tx9vvj73w3yy5j4604y5zshc9y7jc3zx64u3v9m7kcqhl7aa3qq076x5` | 3863 |
| incentives | `testcore1523c422yz0ahw2dwknstzkv7agdznpvf0g8z70nmxk5cypq3msrq53cxz9` | 3864 |
| oracle (TX/USDC) | `testcore1fxqzpfhxcw0mavrpn66h5z7dptsu7hh3fnqeg9v6hprnu50x80tqlv40tu` | 3865 |

Both pairs run `astroport-pair 2.2.1` (the MsgBurn tag fix) and both factories
point their xyk config at code id 3862 with fees intact at 30 / 3333.

The frontend's "generator" is the incentives contract. Only factory A has
`generator_address` set; factory B still has `null`, which is deliberate —
factory B is a duplicate from an earlier double bringup and nothing depends
on it.

Two things about incentives worth knowing before anyone builds on it:

- `astro_token` is set to USDC as a stand-in, because the field is required at
  instantiate. It is not permanent: `UpdateConfig` takes
  `astro_token: Option<AssetInfo>`. **Do not fund vesting with USDC** on the
  assumption that the placeholder is inert.
- `incentivization_fee_info` is `null`, so `ExecuteMsg::Incentivize` charges no
  fee for registering an external reward token
  ([utils.rs:250](../../contracts/tokenomics/incentives/src/utils.rs#L250) skips
  the whole check when it is unset). Fine on testnet; set a fee before mainnet
  or anyone can spam reward denoms into a pool for free.

## Conventions

Progress and diagnostics go to stderr; values (code ids, addresses, tx hashes)
go to stdout. Callers capture values with command substitution, so a stray echo
to stdout corrupts a code id. Keep this in mind when editing either script.
