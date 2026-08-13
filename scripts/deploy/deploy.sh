#!/bin/bash
# Astroport on Coreum - deploy and migrate.
#
#   ./scripts/deploy/deploy.sh --only registry,factory,pair
#   ./scripts/deploy/deploy.sh --migrate --dry-run
#   ./scripts/deploy/deploy.sh --list
#
# Nothing is deployed without an explicit --only (or --all). See README.md.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

load_env_file

# ==========================================
# Network
# ==========================================
NODE="${ASTRO_NODE:-https://full-node.testnet-1.coreum.dev:26657}"
CHAIN_ID="${ASTRO_CHAIN_ID:-coreum-testnet-1}"
GAS_PRICES="${ASTRO_GAS_PRICES:-0.0625utestcore}"

# ==========================================
# Contract table
# ------------------------------------------
# One row per deployable contract:
#   <key>|<artifact>|<mode>|<description>
#
# mode:
#   store  - upload only; something else instantiates it (factory spawns pairs,
#            staking spawns the tracker, factory holds the whitelist code id)
#   full   - upload and instantiate, via init_msg_<key> below
#
# Artifact names matter. Four contracts have NO -coreum variant, because they
# contain no token-factory code: registry, whitelist, tracker, oracle. Using a
# non-existent -coreum name fails at the artifact check, not on chain.
# ==========================================
CONTRACT_TABLE=(
    "registry|astroport_native_coin_registry|full|Native coin registry (decimals; queried by pairs)"
    "whitelist|astroport_whitelist|store|cw1-whitelist, referenced by factory as a code id"
    "tracker|astroport_tokenfactory_tracker|store|Balance tracker, instantiated by staking"
    "pair|astroport_pair-coreum|store|XYK pair, instantiated by the factory"
    "pair_stable|astroport_pair_stable-coreum|store|Stableswap pair"
    "pair_concentrated|astroport_pair_concentrated-coreum|store|PCL pair"
    "factory|astroport_factory-coreum|full|Pair factory"
    "router|astroport_router-coreum|full|Multi-hop swap router"
    "vesting|astroport_vesting-coreum|full|ASTRO vesting"
    "incentives|astroport_incentives-coreum|full|Incentives (formerly 'generator')"
    "staking|astroport_staking-coreum|full|xASTRO staking"
    "maker|astroport_maker-coreum|full|Fee collector"
    "oracle|astroport_oracle|full|TWAP oracle for one pair"
)

table_field() {
    local key="$1" idx="$2" row
    for row in "${CONTRACT_TABLE[@]}"; do
        if [ "${row%%|*}" = "$key" ]; then
            echo "$row" | cut -d'|' -f"$idx"
            return 0
        fi
    done
    return 1
}

all_keys() {
    local row
    for row in "${CONTRACT_TABLE[@]}"; do echo "${row%%|*}"; done
}

# ==========================================
# Existing deployment (Coreum testnet-1)
# ------------------------------------------
# Measured on chain, not assumed. Used by --migrate. Override via .env when
# pointing this script at a different deployment.
# ==========================================
MIGRATE_PAIRS="${ASTRO_MIGRATE_PAIRS:-testcore1awuq9dc39uwvr8a4jckpx48luxp34pd7pjdykmjp6r7gu3g6n2fq32c027,testcore13lk84u23d7fq2f6cuswll9n7e6ypu548dgejr39x8n8fl7a2hagswacz28}"
MIGRATE_FACTORIES="${ASTRO_MIGRATE_FACTORIES:-testcore1j50sat6r0r6g9fypx8xg2e8dhd9m92sl6gj94z5xwy724y9km37q5g8ykc,testcore135e9xywpd2lzdh8unh28z3m3hljy9qq0nn8rrngzurelgj8s9f6qd03hpp}"

# Versions the new pair's migrate entry point accepts. Anything else aborts
# with MigrationError, so the precheck refuses to spend a transaction on it.
# Keep in sync with the match in contracts/pair/src/contract.rs::migrate.
PAIR_MIGRATABLE_FROM="2.2.0"

# Fee parameters of the live xyk pair config. UpdatePairConfig overwrites the
# whole struct, so every field has to be restated or it silently falls back to
# zero -- a 30 bps pool would start trading at 0 bps.
XYK_TOTAL_FEE_BPS="${ASTRO_XYK_TOTAL_FEE_BPS:-30}"
XYK_MAKER_FEE_BPS="${ASTRO_XYK_MAKER_FEE_BPS:-3333}"
STABLE_TOTAL_FEE_BPS="${ASTRO_STABLE_TOTAL_FEE_BPS:-5}"
STABLE_MAKER_FEE_BPS="${ASTRO_STABLE_MAKER_FEE_BPS:-5000}"
CONCENTRATED_TOTAL_FEE_BPS="${ASTRO_CONCENTRATED_TOTAL_FEE_BPS:-0}"
CONCENTRATED_MAKER_FEE_BPS="${ASTRO_CONCENTRATED_MAKER_FEE_BPS:-5000}"

# Coreum charges an Asset-FT issue fee. The factory forwards funds attached to
# CreatePair to the pair so it can mint its LP denom.
LP_DENOM_CREATION_FEE="${ASTRO_LP_DENOM_CREATION_FEE:-10000000utestcore}"

# ==========================================
# Pair type lookup, used by --migrate-factories
# ------------------------------------------
# UpdatePairConfig overwrites the entire PairConfig struct rather than merging,
# so every field is restated by the caller. Omitting total_fee_bps /
# maker_fee_bps would silently reset the pool's fees to zero.
# ==========================================

# The pair_type JSON for a table key. Kept next to the fee lookup below so a
# new pair type means adding one case to each, not hunting through the file.
pair_type_json() {
    case "$1" in
        xyk)          echo '{"xyk":{}}' ;;
        stable)       echo '{"stable":{}}' ;;
        concentrated) echo '{"custom":"concentrated"}' ;;
        *)            return 1 ;;
    esac
}

# Echoes "<total_fee_bps> <maker_fee_bps>" for a pair type. Defaults are the
# values measured on the live factories; override per type through .env.
pair_type_fees() {
    case "$1" in
        xyk)          echo "$XYK_TOTAL_FEE_BPS $XYK_MAKER_FEE_BPS" ;;
        stable)       echo "$STABLE_TOTAL_FEE_BPS $STABLE_MAKER_FEE_BPS" ;;
        concentrated) echo "$CONCENTRATED_TOTAL_FEE_BPS $CONCENTRATED_MAKER_FEE_BPS" ;;
        *)            return 1 ;;
    esac
}

PAIR_TYPE_KEYS="xyk stable concentrated"

# Parses the --migrate-factories argument into PARSED_TYPE_SPECS as
# "<type> <code_id>" entries. Accepts either a bare code id (xyk only, the
# original form) or a comma-separated list of type=code_id pairs.
#
# Everything is validated before the caller broadcasts anything: a typo in the
# third pair must not surface after the first two have already been sent.
PARSED_TYPE_SPECS=()
parse_type_specs() {
    local spec="$1"
    PARSED_TYPE_SPECS=()

    if [[ "$spec" =~ ^[0-9]+$ ]]; then
        PARSED_TYPE_SPECS=("xyk $spec")
        return 0
    fi

    local -a parts
    IFS=',' read -ra parts <<< "$spec"

    local part type code seen=""
    for part in "${parts[@]}"; do
        part="${part// /}"
        [ -n "$part" ] || continue

        if [[ "$part" != *=* ]]; then
            echo "Error: expected <type>=<code_id>, got '$part'." >&2
            echo "       Valid types: $PAIR_TYPE_KEYS" >&2
            echo "       A bare number is also accepted and means xyk only." >&2
            return 1
        fi

        type="${part%%=*}"
        code="${part#*=}"

        if ! pair_type_json "$type" >/dev/null; then
            echo "Error: unknown pair type '$type'. Valid types: $PAIR_TYPE_KEYS" >&2
            return 1
        fi
        if ! [[ "$code" =~ ^[0-9]+$ ]]; then
            echo "Error: code id for '$type' must be numeric, got '$code'" >&2
            return 1
        fi
        case " $seen " in
            *" $type "*)
                echo "Error: pair type '$type' given more than once" >&2
                return 1 ;;
        esac
        seen="$seen $type"

        PARSED_TYPE_SPECS+=("$type $code")
    done

    if [ ${#PARSED_TYPE_SPECS[@]} -eq 0 ]; then
        echo "Error: --migrate-factories needs at least one <type>=<code_id> pair" >&2
        echo "       Valid types: $PAIR_TYPE_KEYS" >&2
        return 1
    fi
    return 0
}

# ==========================================
# Arguments
# ==========================================
DRY_RUN=false
MIGRATE_MODE=false
MIGRATE_FACTORIES_CODE=""
STORE_ONLY=false
RESUME_LOG=""
ONLY_LIST=""
DEPLOY_ALL=false

usage() {
    cat <<'EOF'
Usage: deploy.sh [options]

Selection (one is required unless --migrate or --list):
  --only <a,b,c>     Deploy only these contracts (see --list)
  --all              Deploy every contract in the table

Modes:
  --migrate          Store the pair wasm and migrate the live pairs. Stops
                     before touching the factories -- run the withdraw test
                     first. Combine with --dry-run.
  --migrate-factories <spec>
                     Point the factories at new pair code ids so newly created
                     pairs get the fix. Run only after the withdraw test
                     passes. <spec> is a comma-separated list of
                     type=code_id pairs, type one of xyk, stable,
                     concentrated (e.g. xyk=3872,stable=3873). A bare number
                     is shorthand for xyk=<number>.
  --store-only       Upload wasm only; skip every instantiate
  --resume <log>     Reuse code ids / addresses recorded in a previous log
  --dry-run          Print every transaction without broadcasting
  --list             Show the contract table and exit
  -h, --help         This message

Examples:
  deploy.sh --list
  deploy.sh --migrate --dry-run
  deploy.sh --migrate-factories xyk=3872,stable=3873,concentrated=3874
  deploy.sh --migrate-factories <code-id-printed-by---migrate>   # xyk only
  deploy.sh --only registry,factory,pair --dry-run
  deploy.sh --only incentives,vesting --resume deployments/deploy_20260101_120000.json
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)    DRY_RUN=true; shift ;;
        --migrate)    MIGRATE_MODE=true; shift ;;
        --migrate-factories) MIGRATE_FACTORIES_CODE="$2"; shift 2 ;;
        --store-only) STORE_ONLY=true; shift ;;
        --resume)     RESUME_LOG="$2"; shift 2 ;;
        --only)       ONLY_LIST="$2"; shift 2 ;;
        --all)        DEPLOY_ALL=true; shift ;;
        --list)
            printf '%-20s %-40s %-6s %s\n' "KEY" "ARTIFACT" "MODE" "DESCRIPTION"
            for row in "${CONTRACT_TABLE[@]}"; do
                IFS='|' read -r k a m d <<< "$row"
                printf '%-20s %-40s %-6s %s\n' "$k" "$a" "$m" "$d"
            done
            exit 0 ;;
        -h|--help)    usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
done

if [[ "$CHAIN_ID" == *"mainnet"* ]]; then
    echo "Error: chain id '$CHAIN_ID' looks like mainnet." >&2
    echo "This script carries hardcoded testnet addresses. Review before removing this guard." >&2
    exit 1
fi

# Refuse to run with no selection. An unguarded full run is exactly how the
# current duplicate factory + pair came to exist.
if [ "$MIGRATE_MODE" = false ] && [ "$DEPLOY_ALL" = false ] \
   && [ -z "$ONLY_LIST" ] && [ -z "$MIGRATE_FACTORIES_CODE" ]; then
    echo "Error: nothing selected. Pass --only <list>, --all, or --migrate." >&2
    echo "" >&2
    usage >&2
    exit 1
fi

# Validate the whole --migrate-factories spec before anything is printed or
# broadcast. A typo in the third pair must not surface after the first two
# have already gone out.
if [ -n "$MIGRATE_FACTORIES_CODE" ]; then
    parse_type_specs "$MIGRATE_FACTORIES_CODE" || exit 1
fi

# Resolve the selection against the table, preserving table order so that
# dependencies are deployed before the contracts that reference them.
SELECTED=()
if [ "$DEPLOY_ALL" = true ]; then
    mapfile -t SELECTED < <(all_keys)
elif [ -n "$ONLY_LIST" ]; then
    IFS=',' read -ra REQUESTED <<< "$ONLY_LIST"
    for req in "${REQUESTED[@]}"; do
        req="${req// /}"
        if ! table_field "$req" 1 >/dev/null; then
            echo "Error: unknown contract '$req'" >&2
            echo "Known: $(all_keys | tr '\n' ' ')" >&2
            exit 1
        fi
    done
    while read -r key; do
        for req in "${REQUESTED[@]}"; do
            [ "${req// /}" = "$key" ] && SELECTED+=("$key") && break
        done
    done < <(all_keys)
fi

DRY() { if [ "$DRY_RUN" = true ]; then echo "  [dry-run] $*" >&2; return 0; fi; return 1; }

# ==========================================
# Setup
# ==========================================
validate_env "ASTRO_DEPLOYER_KEY_NAME"
check_cored
[ "$DRY_RUN" = true ] || prompt_keyring_passphrase

DEPLOYER_ADDR="${ASTRO_DEPLOYER_ADDR:-}"
if [ -z "$DEPLOYER_ADDR" ]; then
    DEPLOYER_ADDR=$(run_cored cored keys show "$ASTRO_DEPLOYER_KEY_NAME" -a \
        --keyring-backend "$ASTRO_KEYRING_BACKEND" --chain-id "$CHAIN_ID" 2>/dev/null || echo "")
fi
if [ -z "$DEPLOYER_ADDR" ]; then
    echo "Error: could not resolve an address for key '$ASTRO_DEPLOYER_KEY_NAME'." >&2
    echo "Set ASTRO_DEPLOYER_ADDR in .env to run --dry-run without keyring access." >&2
    exit 1
fi

OWNER="${ASTRO_OWNER:-$DEPLOYER_ADDR}"
ADMIN="${ASTRO_ADMIN:-$DEPLOYER_ADDR}"

# The ASTRO token. On a testnet without a real ASTRO this is whatever denom the
# tokenomics contracts should treat as the reward asset.
ASTRO_DENOM="${ASTRO_TOKEN_DENOM:-}"

echo "=========================================="
echo "Astroport on Coreum - deploy"
echo "=========================================="
echo "Mode:      $([ "$DRY_RUN" = true ] && echo 'DRY RUN (no broadcast)' || echo 'LIVE BROADCAST')"
echo "Node:      $NODE"
echo "Chain ID:  $CHAIN_ID"
echo "Deployer:  $DEPLOYER_ADDR"
echo "Owner:     $OWNER"
echo "Admin:     $ADMIN"
if [ "$MIGRATE_MODE" = true ]; then
    echo "Action:    MIGRATE existing pairs"
elif [ -n "$MIGRATE_FACTORIES_CODE" ]; then
    echo "Action:    Point factories at pair code ids:"
    for entry in "${PARSED_TYPE_SPECS[@]}"; do
        echo "             ${entry% *} -> ${entry#* }"
    done
else
    echo "Deploying: ${SELECTED[*]}"
    [ "$STORE_ONLY" = true ] && echo "           (store only, no instantiate)"
fi
echo "=========================================="
echo ""

WORKSPACE_ROOT=$(get_workspace_root)
OUT_DIR="$WORKSPACE_ROOT/deployments/${CHAIN_ID}"
mkdir -p "$OUT_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG="$OUT_DIR/deploy_${TIMESTAMP}.json"

[ -z "$RESUME_LOG" ] || [ -f "$RESUME_LOG" ] || {
    echo "Error: --resume log not found: $RESUME_LOG" >&2; exit 1; }

# Seed the working log from --resume without ever writing to the resume file.
if [ "$DRY_RUN" != true ]; then
    if [ -n "$RESUME_LOG" ]; then
        echo "Resume: seeding new log from $RESUME_LOG"
        echo ""
        jq --arg net "$CHAIN_ID" --arg deployer "$DEPLOYER_ADDR" --arg ts "$(date -Iseconds)" \
            '{network:$net, deployer:$deployer, timestamp:$ts,
              contracts:(.contracts // {}), steps:(.steps // {})}' \
            "$RESUME_LOG" > "$LOG"
    else
        jq -n --arg net "$CHAIN_ID" --arg deployer "$DEPLOYER_ADDR" --arg ts "$(date -Iseconds)" \
            '{network:$net, deployer:$deployer, timestamp:$ts, contracts:{}, steps:{}}' > "$LOG"
    fi
    echo "Deploy log: $LOG"
    echo ""
fi

# Read recorded values from the resume source under --dry-run (where no working
# log exists), otherwise from the seeded working log.
RSRC="${RESUME_LOG:-$LOG}"

declare -A CODE_IDS
declare -A ADDRS

# Preload anything the resume log already knows, so init messages that reference
# a sibling contract can be built without re-deploying it.
if [ -f "$RSRC" ]; then
    while read -r k; do
        [ -n "$k" ] || continue
        cid=$(log_get "$RSRC" ".contracts[\"$k\"].code_id")
        addr=$(log_get "$RSRC" ".contracts[\"$k\"].address")
        [ -n "$cid" ] && CODE_IDS[$k]="$cid"
        [ -n "$addr" ] && ADDRS[$k]="$addr"
    done < <(jq -r '.contracts | keys[]?' "$RSRC" 2>/dev/null)
fi

# Allow pre-existing deployments to be referenced without a resume log, e.g.
# deploying only the router against a factory that is already live.
[ -n "${ASTRO_FACTORY_ADDR:-}" ]  && ADDRS[factory]="$ASTRO_FACTORY_ADDR"
[ -n "${ASTRO_REGISTRY_ADDR:-}" ] && ADDRS[registry]="$ASTRO_REGISTRY_ADDR"
[ -n "${ASTRO_VESTING_ADDR:-}" ]  && ADDRS[vesting]="$ASTRO_VESTING_ADDR"
[ -n "${ASTRO_STAKING_ADDR:-}" ]  && ADDRS[staking]="$ASTRO_STAKING_ADDR"

# need_addr / need_code - fail with a usable message instead of emitting an
# init message containing an empty string, which the chain rejects obscurely.
need_addr() {
    local key="$1" for_what="$2"
    if [ -z "${ADDRS[$key]:-}" ]; then
        echo "Error: $for_what needs the $key address." >&2
        echo "Deploy $key in the same run, pass --resume, or set ASTRO_${key^^}_ADDR." >&2
        return 1
    fi
    echo "${ADDRS[$key]}"
}

need_code() {
    local key="$1" for_what="$2"
    if [ -z "${CODE_IDS[$key]:-}" ]; then
        echo "Error: $for_what needs the $key code id." >&2
        echo "Include $key in --only, or pass --resume with a log that has it." >&2
        return 1
    fi
    echo "${CODE_IDS[$key]}"
}

# Under --dry-run nothing is ever stored or instantiated, so dependent init
# messages would fail on every lookup. Substitute a visible placeholder: the
# point of a dry run is to inspect message shape, not to resolve addresses.
# Code ids must stay numeric even here: they are fed to jq --argjson, which
# rejects a placeholder string. 0 is never a real code id, so it reads as
# obviously-fake in the printed message rather than as a plausible value.
if [ "$DRY_RUN" = true ]; then
    need_addr() { echo "${ADDRS[$1]:-<$1-address-from-this-run>}"; }
    need_code() { echo "${CODE_IDS[$1]:-0}"; }
fi

# ==========================================
# Init message builders
# ------------------------------------------
# One per 'full' contract, named init_msg_<key>. Every message is built with jq
# so quoting and numeric types are correct by construction. Field names are
# taken from the InstantiateMsg definitions in packages/astroport/.
# ==========================================

init_msg_registry() {
    jq -nc --arg owner "$OWNER" '{owner: $owner}'
}

init_msg_factory() {
    local registry whitelist_cid tracker_cid pair_cid
    registry=$(need_addr registry "factory") || return 1
    whitelist_cid=$(need_code whitelist "factory") || return 1
    tracker_cid=$(need_code tracker "factory") || return 1

    # pair_configs may be empty: the factory accepts it and UpdatePairConfig
    # fills it in later. Include the xyk config only when the pair wasm was
    # stored in this run (or is known from the resume log).
    local pair_configs='[]'
    if [ -n "${CODE_IDS[pair]:-}" ]; then
        pair_cid="${CODE_IDS[pair]}"
        pair_configs=$(jq -nc \
            --argjson cid "$pair_cid" \
            --argjson total "$XYK_TOTAL_FEE_BPS" \
            --argjson maker "$XYK_MAKER_FEE_BPS" \
            '[{code_id: $cid, pair_type: {xyk: {}}, total_fee_bps: $total,
               maker_fee_bps: $maker, is_disabled: false,
               is_generator_disabled: false, permissioned: false,
               whitelist: null}]')
    fi

    # generator_address stays null here; incentives does not exist yet and
    # points back at the factory. UpdateConfig wires it afterwards.
    jq -nc \
        --arg owner "$OWNER" \
        --arg registry "$registry" \
        --arg tf "$OWNER" \
        --argjson whitelist_cid "$whitelist_cid" \
        --argjson tracker_cid "$tracker_cid" \
        --argjson pair_configs "$pair_configs" \
        '{pair_configs: $pair_configs,
          token_code_id: 0,
          fee_address: null,
          generator_address: null,
          owner: $owner,
          whitelist_code_id: $whitelist_cid,
          coin_registry_address: $registry,
          tracker_config: {code_id: $tracker_cid, token_factory_addr: $tf}}'
}

init_msg_router() {
    local factory
    factory=$(need_addr factory "router") || return 1
    jq -nc --arg f "$factory" '{astroport_factory: $f}'
}

init_msg_vesting() {
    [ -n "$ASTRO_DENOM" ] || {
        echo "Error: vesting needs ASTRO_TOKEN_DENOM (the reward denom)." >&2; return 1; }
    jq -nc --arg owner "$OWNER" --arg denom "$ASTRO_DENOM" \
        '{owner: $owner, vesting_token: {native_token: {denom: $denom}}}'
}

init_msg_incentives() {
    local factory vesting
    factory=$(need_addr factory "incentives") || return 1
    vesting=$(need_addr vesting "incentives") || return 1
    [ -n "$ASTRO_DENOM" ] || {
        echo "Error: incentives needs ASTRO_TOKEN_DENOM (the reward denom)." >&2; return 1; }
    jq -nc \
        --arg owner "$OWNER" \
        --arg factory "$factory" \
        --arg vesting "$vesting" \
        --arg denom "$ASTRO_DENOM" \
        '{owner: $owner,
          factory: $factory,
          astro_token: {native_token: {denom: $denom}},
          vesting_contract: $vesting,
          incentivization_fee_info: null,
          guardian: null}'
}

init_msg_staking() {
    local tracker_cid
    tracker_cid=$(need_code tracker "staking") || return 1
    [ -n "$ASTRO_DENOM" ] || {
        echo "Error: staking needs ASTRO_TOKEN_DENOM (the deposit denom)." >&2; return 1; }
    # Staking instantiates the tracker itself from this code id, which is why
    # the tracker is store-only in the contract table.
    jq -nc \
        --arg denom "$ASTRO_DENOM" \
        --arg admin "$ADMIN" \
        --arg tf "${ASTRO_TOKEN_FACTORY_ADDR:-$OWNER}" \
        --argjson cid "$tracker_cid" \
        '{deposit_token_denom: $denom,
          tracking_admin: $admin,
          tracking_code_id: $cid,
          token_factory_addr: $tf}'
}

init_msg_maker() {
    local factory staking
    factory=$(need_addr factory "maker") || return 1
    staking=$(need_addr staking "maker") || return 1
    [ -n "$ASTRO_DENOM" ] || {
        echo "Error: maker needs ASTRO_TOKEN_DENOM." >&2; return 1; }
    jq -nc \
        --arg owner "$OWNER" \
        --arg factory "$factory" \
        --arg staking "$staking" \
        --arg denom "$ASTRO_DENOM" \
        '{owner: $owner,
          default_bridge: null,
          astro_token: {native_token: {denom: $denom}},
          factory_contract: $factory,
          staking_contract: $staking,
          governance_contract: null,
          governance_percent: null,
          max_spread: "0.5",
          second_receiver_params: null,
          collect_cooldown: null}'
}

init_msg_oracle() {
    local factory
    factory=$(need_addr factory "oracle") || return 1
    # The oracle tracks exactly one pair, so its two asset infos must be given.
    [ -n "${ASTRO_ORACLE_ASSET_1:-}" ] && [ -n "${ASTRO_ORACLE_ASSET_2:-}" ] || {
        echo "Error: oracle needs ASTRO_ORACLE_ASSET_1 and ASTRO_ORACLE_ASSET_2 (denoms)." >&2
        return 1; }
    jq -nc \
        --arg f "$factory" \
        --arg a1 "$ASTRO_ORACLE_ASSET_1" \
        --arg a2 "$ASTRO_ORACLE_ASSET_2" \
        '{factory_contract: $f,
          asset_infos: [{native_token: {denom: $a1}}, {native_token: {denom: $a2}}]}'
}

# ==========================================
# Migration mode
# ------------------------------------------
# Order matters and is not negotiable:
#   1. store the fixed pair wasm
#   2. simulate, then migrate every live pair
#   3. STOP -- a human confirms withdraw_liquidity works
#   4. only then point the factories at the new code id
#
# Step 4 is deliberately last. Rolling back is impossible: the currently
# deployed pair code has unimplemented!() as its migrate entry point, so there
# is no way back to it. The withdraw test is the only real proof the fix works.
# ==========================================
run_migrate() {
    echo "--- Migration: Coreum MsgBurn tag fix ---"
    echo ""

    local pair_cid
    if [ "$DRY_RUN" = true ]; then
        DRY "cored tx wasm store $(artifact_path astroport_pair-coreum)"
        pair_cid="<new-pair-code-id>"
    else
        pair_cid=$(maybe_store pair "$LOG" "astroport_pair-coreum" \
            "$NODE" "$CHAIN_ID" "$GAS_PRICES" "$ASTRO_DEPLOYER_KEY_NAME") || return 1
    fi
    echo ""

    local -a pairs
    IFS=',' read -ra pairs <<< "$MIGRATE_PAIRS"

    local pair
    for pair in "${pairs[@]}"; do
        pair="${pair// /}"
        [ -n "$pair" ] || continue
        echo "Pair $pair"

        if DRY "cored tx wasm migrate $pair $pair_cid '{}'"; then
            continue
        fi

        if step_done "$RSRC" "migrate_$pair"; then
            echo "  [skip] already migrated" >&2
            continue
        fi

        # Checked without a signer on purpose: `tx wasm migrate --dry-run`
        # resolves --from against the keyring even in simulation, and fails
        # on both a key name and an address. See precheck_migrate in lib.sh.
        precheck_migrate "$pair" "$NODE" "$CHAIN_ID" \
            "astroport-pair" "$PAIR_MIGRATABLE_FROM" "$DEPLOYER_ADDR" || return 1

        migrate_contract "$pair" "$pair_cid" '{}' "$NODE" "$CHAIN_ID" \
            "$GAS_PRICES" "$ASTRO_DEPLOYER_KEY_NAME" >/dev/null || return 1
        mark_step "$LOG" "migrate_$pair"

        echo "  New version: $(contract_cw2_version "$pair" "$NODE" "$CHAIN_ID")"
        echo ""
    done

    echo ""
    echo "=========================================="
    echo "Pairs migrated. STOP HERE."
    echo "=========================================="
    echo ""
    echo "Verify the fix with a small withdraw_liquidity on:"
    echo "  ${pairs[0]}"
    echo ""
    echo "That withdrawal is the only real proof the burn now encodes correctly."
    echo "Rolling back is not possible: the old pair code has an unimplemented"
    echo "migrate entry point, so there is no path back to it."
    echo ""
    echo "Once the withdrawal succeeds, point the factories at the new code id:"
    echo ""
    echo "  ./scripts/deploy/deploy.sh --migrate-factories $pair_cid"
    echo ""
}

# ==========================================
# Factory repoint (separate invocation, on purpose)
# ==========================================
run_migrate_factories() {
    echo "--- Pointing factories at the new pair code ids ---"
    echo ""

    local -a factories
    IFS=',' read -ra factories <<< "$MIGRATE_FACTORIES"

    local factory entry type code total maker cfg
    for factory in "${factories[@]}"; do
        factory="${factory// /}"
        [ -n "$factory" ] || continue
        echo "Factory $factory"

        for entry in "${PARSED_TYPE_SPECS[@]}"; do
            read -r type code <<< "$entry"
            read -r total maker <<< "$(pair_type_fees "$type")"

            cfg=$(jq -nc \
                --argjson cid "$code" \
                --argjson ptype "$(pair_type_json "$type")" \
                --argjson total "$total" \
                --argjson maker "$maker" \
                '{update_pair_config: {config: {
                    code_id: $cid,
                    pair_type: $ptype,
                    total_fee_bps: $total,
                    maker_fee_bps: $maker,
                    is_disabled: false,
                    is_generator_disabled: false,
                    permissioned: false,
                    whitelist: null
                }}}')

            echo "  $type -> code_id $code (fees $total / $maker)"
            if DRY "cored tx wasm execute $factory '$cfg'"; then
                continue
            fi
            maybe_exec "$LOG" "update_pair_config_${factory}_${type}" \
                "$factory" "$cfg" "$NODE" "$CHAIN_ID" "$GAS_PRICES" \
                "$ASTRO_DEPLOYER_KEY_NAME" || return 1
        done
        echo ""
    done

    echo "Verify with:"
    for factory in "${factories[@]}"; do
        echo "  cored query wasm contract-state smart ${factory// /} '{\"config\":{}}' --node $NODE"
    done
    echo ""
    echo "Confirm each entry below shows the new code id AND the stated fees --"
    echo "UpdatePairConfig overwrites the whole struct, so a dropped field reads"
    echo "back as zero rather than as an error:"
    for entry in "${PARSED_TYPE_SPECS[@]}"; do
        read -r type code <<< "$entry"
        read -r total maker <<< "$(pair_type_fees "$type")"
        echo "  $type: code_id $code, total_fee_bps $total, maker_fee_bps $maker"
    done
}

# ==========================================
# Deployment
# ==========================================
run_deploy() {
    local key artifact mode init_msg funds cid addr

    for key in "${SELECTED[@]}"; do
        artifact=$(table_field "$key" 2)
        mode=$(table_field "$key" 3)

        echo "--- $key ($artifact) ---"

        if [ "$DRY_RUN" = true ]; then
            DRY "cored tx wasm store $(artifact_path "$artifact")"
        else
            # Assign from the captured value: maybe_store runs in a subshell
            # here, so the CODE_IDS entry it sets internally does not survive.
            cid=$(maybe_store "$key" "$LOG" "$artifact" \
                "$NODE" "$CHAIN_ID" "$GAS_PRICES" "$ASTRO_DEPLOYER_KEY_NAME") || return 1
            CODE_IDS[$key]="$cid"
        fi

        if [ "$mode" = "store" ]; then
            echo "  (store only; instantiated by another contract)"
            echo ""
            continue
        fi

        if [ "$STORE_ONLY" = true ]; then
            echo "  (--store-only: skipping instantiate)"
            echo ""
            continue
        fi

        init_msg=$("init_msg_$key") || return 1

        funds=""
        if [ "$DRY_RUN" = true ]; then
            DRY "cored tx wasm instantiate <$key code id> '$init_msg' --label astroport-$key"
        else
            addr=$(maybe_instantiate "$key" "$LOG" \
                "${CODE_IDS[$key]}" "$init_msg" "astroport-$key" \
                "$NODE" "$CHAIN_ID" "$GAS_PRICES" "$ASTRO_DEPLOYER_KEY_NAME" \
                "$ADMIN" "$funds") || return 1
            ADDRS[$key]="$addr"
        fi
        echo ""
    done

    post_deploy_wiring
}

# ==========================================
# Wiring that can only happen after instantiation
# ==========================================
post_deploy_wiring() {
    local selected_str=" ${SELECTED[*]} "

    # The factory is deployed with generator_address: null because incentives
    # references the factory and vice versa. Close the loop here. Every field
    # of UpdateConfig is Option, so sending just this one is safe.
    if [[ "$selected_str" == *" incentives "* ]] && [ -n "${ADDRS[factory]:-}" ]; then
        echo "--- Wiring: factory.generator_address -> incentives ---"
        local incentives msg
        incentives=$(need_addr incentives "factory wiring") || return 1
        msg=$(jq -nc --arg a "$incentives" '{update_config: {generator_address: $a}}')
        if ! DRY "cored tx wasm execute ${ADDRS[factory]} '$msg'"; then
            maybe_exec "$LOG" "factory_set_generator" \
                "${ADDRS[factory]}" "$msg" "$NODE" "$CHAIN_ID" "$GAS_PRICES" \
                "$ASTRO_DEPLOYER_KEY_NAME" || return 1
        fi
        echo ""
    fi

    # Pair contracts query the registry for token decimals during swaps
    # (query_token_precision). A denom that is not registered makes the pool
    # fail on chain, so registering is part of deploying, not an afterthought.
    if [[ "$selected_str" == *" registry "* ]] && [ -n "${ASTRO_REGISTER_COINS:-}" ]; then
        echo "--- Registering coin decimals ---"
        local registry coins msg
        registry=$(need_addr registry "coin registration") || return 1

        # ASTRO_REGISTER_COINS format: "denom1:6,denom2:8"
        coins=$(jq -nc --arg spec "$ASTRO_REGISTER_COINS" \
            '[$spec | split(",")[] | select(length > 0) | split(":")
              | [.[0], (.[1] | tonumber)]]')
        msg=$(jq -nc --argjson c "$coins" '{add: {native_coins: $c}}')

        if ! DRY "cored tx wasm execute $registry '$msg'"; then
            maybe_exec "$LOG" "registry_add_coins" \
                "$registry" "$msg" "$NODE" "$CHAIN_ID" "$GAS_PRICES" \
                "$ASTRO_DEPLOYER_KEY_NAME" || return 1
        fi
        echo ""
    elif [[ "$selected_str" == *" registry "* ]]; then
        echo "Note: registry deployed but ASTRO_REGISTER_COINS is not set."
        echo "Pairs query this registry for token decimals; a pool whose denom is"
        echo "missing here fails on chain. Register denoms before creating pairs."
        echo ""
    fi
}

# ==========================================
# Main
# ==========================================
if [ "$MIGRATE_MODE" = true ]; then
    run_migrate
elif [ -n "$MIGRATE_FACTORIES_CODE" ]; then
    # Already validated into PARSED_TYPE_SPECS above.
    run_migrate_factories
else
    run_deploy
fi

echo "=========================================="
if [ "$DRY_RUN" = true ]; then
    echo "Dry run complete. Nothing was broadcast."
else
    echo "Done. Deploy log: $LOG"
fi
echo "=========================================="
