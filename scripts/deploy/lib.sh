#!/bin/bash
# Astroport on Coreum - shared deployment library.
#
# Sourced by deploy.sh. Contains the chain interaction wrappers, the deploy-log
# based idempotency primitives, and small helpers. No contract-specific knowledge
# lives here; that belongs in the contract table in deploy.sh.
#
# Convention throughout this file: progress and diagnostics go to stderr, VALUES
# (code ids, addresses, tx hashes) go to stdout. Callers capture values with
# command substitution, so a stray echo to stdout corrupts a code id.
#
# DO NOT commit secrets here. Use scripts/deploy/.env (git-ignored).

# Resolve this file's own directory, independent of the caller's location.
if [ -z "${DEPLOY_LIB_DIR:-}" ]; then
    DEPLOY_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# ==========================================
# Defaults (override via .env or environment)
# ==========================================
ARTIFACTS_DIR="${ARTIFACTS_DIR:-artifacts}"
DEFAULT_GAS="${DEFAULT_GAS:-auto}"
DEFAULT_GAS_ADJUSTMENT="${DEFAULT_GAS_ADJUSTMENT:-1.4}"
ASTRO_KEYRING_BACKEND="${ASTRO_KEYRING_BACKEND:-file}"

# Number of 6-second polls to wait for a tx to land before giving up.
TX_WAIT_ATTEMPTS="${TX_WAIT_ATTEMPTS:-10}"

# ==========================================
# Path helpers
# ==========================================
get_workspace_root() {
    (cd "$DEPLOY_LIB_DIR/../.." && pwd)
}

artifact_path() {
    echo "$(get_workspace_root)/$ARTIFACTS_DIR/$1.wasm"
}

# ==========================================
# Environment loading
# ------------------------------------------
# Priority: $ASTRO_ENV_FILE (hard error if set but missing), then .env.
# `set -a` auto-exports everything the file defines. Absent .env is fine --
# variables may be pre-exported by the caller or by CI.
# ==========================================
load_env_file() {
    local f=""
    if [ -n "${ASTRO_ENV_FILE:-}" ]; then
        f="$ASTRO_ENV_FILE"
        [ -f "$f" ] || { echo "Error: ASTRO_ENV_FILE not found: $f" >&2; return 1; }
    elif [ -f "$DEPLOY_LIB_DIR/.env" ]; then
        f="$DEPLOY_LIB_DIR/.env"
    fi
    if [ -n "$f" ]; then
        # The real environment wins over the file. Sourcing directly would let
        # an empty placeholder in .env clobber a variable set on the command
        # line or injected by CI, which reads as "the file is broken" rather
        # than as "your override was discarded".
        local line key val
        while IFS= read -r line || [ -n "$line" ]; do
            line="${line#"${line%%[![:space:]]*}"}"
            case "$line" in ''|'#'*) continue ;; esac
            case "$line" in *=*) ;; *) continue ;; esac
            key="${line%%=*}"
            val="${line#*=}"
            key="${key%"${key##*[![:space:]]}"}"
            case "$key" in export\ *) key="${key#export }" ;; esac
            [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
            # Already non-empty in the environment? Leave it alone.
            [ -n "${!key:-}" ] && continue
            val="${val#\"}"; val="${val%\"}"
            val="${val#\'}"; val="${val%\'}"
            export "$key=$val"
        done < "$f"
        echo "Loaded env: $f" >&2
    fi
}

validate_env() {
    local var
    for var in "$@"; do
        if [ -z "${!var}" ]; then
            echo "Error: required environment variable $var is not set" >&2
            exit 1
        fi
    done
}

check_cored() {
    if ! command -v cored &> /dev/null; then
        echo "Error: cored (Coreum CLI) is not installed or not in PATH" >&2
        echo "Install from: https://docs.coreum.dev/docs/tools/cored" >&2
        exit 1
    fi
    if ! command -v jq &> /dev/null; then
        echo "Error: jq is not installed or not in PATH" >&2
        exit 1
    fi
}

# ==========================================
# Keyring handling
# ------------------------------------------
# The `file` backend prompts for a passphrase on every signing operation. Ask
# once, then pipe it into each cored invocation.
# ==========================================
prompt_keyring_passphrase() {
    if [ "$ASTRO_KEYRING_BACKEND" = "file" ] && [ -z "${KEYRING_PASSPHRASE:-}" ]; then
        echo "Enter keyring passphrase:" >&2
        read -rs KEYRING_PASSPHRASE
        echo "" >&2
        export KEYRING_PASSPHRASE
    fi
}

run_cored() {
    if [ -n "${KEYRING_PASSPHRASE:-}" ]; then
        printf '%s\n' "$KEYRING_PASSPHRASE" | "$@"
    else
        "$@"
    fi
}

# Extract the JSON object from mixed output. cored prints informational lines
# ("gas estimate: 123") to stderr; with 2>&1 they get interleaved with the JSON.
extract_json() {
    grep '^\{' | tail -1
}

# ==========================================
# wait_for_tx - Poll until a tx is indexed, fail hard on a non-zero code.
# Args: $1=txhash, $2=node, $3=max_attempts (default $TX_WAIT_ATTEMPTS)
# Returns: tx result JSON on stdout
# ==========================================
wait_for_tx() {
    local txhash="$1"
    local node="$2"
    local max_attempts="${3:-$TX_WAIT_ATTEMPTS}"

    local i tx_result code raw_log
    for i in $(seq 1 "$max_attempts"); do
        sleep 6
        tx_result=$(cored query tx "$txhash" --node "$node" --output json 2>/dev/null || echo "")
        if [ -n "$tx_result" ]; then
            code=$(echo "$tx_result" | jq -r '.code // 0')
            if [ "$code" != "0" ]; then
                raw_log=$(echo "$tx_result" | jq -r '.raw_log // "unknown error"')
                echo "Error: transaction failed with code $code: $raw_log" >&2
                return 1
            fi
            echo "$tx_result"
            return 0
        fi
        echo "  Waiting for confirmation (attempt $i/$max_attempts)..." >&2
    done

    echo "Error: transaction $txhash not found after $max_attempts attempts" >&2
    return 1
}

# broadcast_and_wait - Shared tail of every tx wrapper: pull the hash out of
# cored's output, wait for the tx, echo the full tx result JSON.
# Args: $1=raw cored output, $2=node, $3=human label for error messages
broadcast_and_wait() {
    local result="$1" node="$2" label="$3"

    local txhash
    txhash=$(echo "$result" | extract_json | jq -r '.txhash' 2>/dev/null)

    if [ -z "$txhash" ] || [ "$txhash" = "null" ]; then
        echo "Error: failed to get transaction hash for $label" >&2
        echo "Result: $result" >&2
        return 1
    fi

    echo "  TX: $txhash" >&2

    local tx_result
    if ! tx_result=$(wait_for_tx "$txhash" "$node"); then
        echo "Error: transaction failed for $label" >&2
        return 1
    fi

    echo "$tx_result"
}

# ==========================================
# store_contract - Upload a WASM artifact.
# Args: $1=artifact_name (without .wasm), $2=node, $3=chain_id, $4=gas_prices, $5=from
# Returns: code_id on stdout
# ==========================================
store_contract() {
    local artifact_name="$1" node="$2" chain_id="$3" gas_prices="$4" from="$5"

    local wasm_path
    wasm_path=$(artifact_path "$artifact_name")

    if [ ! -f "$wasm_path" ]; then
        echo "Error: artifact not found: $wasm_path" >&2
        echo "Run the optimizer build first (see scripts/deploy/README.md)" >&2
        return 1
    fi

    echo "Storing: $artifact_name" >&2

    local result
    result=$(run_cored cored tx wasm store "$wasm_path" \
        --from "$from" \
        --node "$node" \
        --chain-id "$chain_id" \
        --keyring-backend "$ASTRO_KEYRING_BACKEND" \
        --gas "$DEFAULT_GAS" \
        --gas-adjustment "$DEFAULT_GAS_ADJUSTMENT" \
        --gas-prices "$gas_prices" \
        --broadcast-mode sync \
        --yes \
        --output json 2>&1) || true

    local tx_result
    tx_result=$(broadcast_and_wait "$result" "$node" "store $artifact_name") || return 1

    local code_id
    code_id=$(echo "$tx_result" | jq -r '.events[] | select(.type=="store_code") | .attributes[] | select(.key=="code_id") | .value' 2>/dev/null)

    if [ -z "$code_id" ] || [ "$code_id" = "null" ]; then
        echo "Error: could not extract code_id for $artifact_name" >&2
        return 1
    fi

    echo "  Code ID: $code_id" >&2
    echo "$code_id"
}

# ==========================================
# instantiate_contract - Instantiate a stored code id.
# Args: $1=code_id, $2=init_msg, $3=label, $4=node, $5=chain_id, $6=gas_prices,
#       $7=from, $8=admin (default: $from), $9=funds (optional, e.g. "10000000utestcore")
# Returns: contract address on stdout
# ==========================================
instantiate_contract() {
    local code_id="$1" init_msg="$2" label="$3" node="$4" chain_id="$5"
    local gas_prices="$6" from="$7" admin="${8:-$7}" funds="${9:-}"

    echo "Instantiating: $label (code_id $code_id)" >&2

    # Fail before broadcasting rather than after: cored's error for malformed
    # init JSON arrives only after the gas simulation and is easy to misread.
    if ! jq -e . >/dev/null 2>&1 <<< "$init_msg"; then
        echo "Error: init message for $label is not valid JSON:" >&2
        echo "$init_msg" >&2
        return 1
    fi

    local funds_flag=()
    [ -n "$funds" ] && funds_flag=(--amount "$funds")

    local result
    result=$(run_cored cored tx wasm instantiate "$code_id" "$init_msg" \
        --label "$label" \
        --admin "$admin" \
        --from "$from" \
        --node "$node" \
        --chain-id "$chain_id" \
        --keyring-backend "$ASTRO_KEYRING_BACKEND" \
        --gas "$DEFAULT_GAS" \
        --gas-adjustment "$DEFAULT_GAS_ADJUSTMENT" \
        --gas-prices "$gas_prices" \
        --broadcast-mode sync \
        --yes \
        --output json \
        "${funds_flag[@]}" 2>&1) || true

    local tx_result
    tx_result=$(broadcast_and_wait "$result" "$node" "instantiate $label") || return 1

    local contract_addr
    contract_addr=$(echo "$tx_result" | jq -r '.events[] | select(.type=="instantiate") | .attributes[] | select(.key=="_contract_address") | .value' 2>/dev/null | head -1)

    if [ -z "$contract_addr" ] || [ "$contract_addr" = "null" ]; then
        echo "Error: could not extract contract address for $label" >&2
        return 1
    fi

    echo "  Address: $contract_addr" >&2
    echo "$contract_addr"
}

# ==========================================
# execute_contract - Execute a message on a contract.
# Args: $1=contract_addr, $2=exec_msg, $3=node, $4=chain_id, $5=gas_prices,
#       $6=from, $7=funds (optional)
# Returns: txhash on stdout
# ==========================================
execute_contract() {
    local contract_addr="$1" exec_msg="$2" node="$3" chain_id="$4"
    local gas_prices="$5" from="$6" funds="${7:-}"

    echo "Executing on $contract_addr" >&2

    if ! jq -e . >/dev/null 2>&1 <<< "$exec_msg"; then
        echo "Error: execute message is not valid JSON:" >&2
        echo "$exec_msg" >&2
        return 1
    fi

    local funds_flag=()
    [ -n "$funds" ] && funds_flag=(--amount "$funds")

    local result
    result=$(run_cored cored tx wasm execute "$contract_addr" "$exec_msg" \
        --from "$from" \
        --node "$node" \
        --chain-id "$chain_id" \
        --keyring-backend "$ASTRO_KEYRING_BACKEND" \
        --gas "$DEFAULT_GAS" \
        --gas-adjustment "$DEFAULT_GAS_ADJUSTMENT" \
        --gas-prices "$gas_prices" \
        --broadcast-mode sync \
        --yes \
        --output json \
        "${funds_flag[@]}" 2>&1) || true

    local tx_result
    tx_result=$(broadcast_and_wait "$result" "$node" "execute on $contract_addr") || return 1

    echo "$tx_result" | jq -r '.txhash'
}

# ==========================================
# migrate_contract - Migrate a contract to a new code id.
# Args: $1=contract_addr, $2=new_code_id, $3=migrate_msg, $4=node, $5=chain_id,
#       $6=gas_prices, $7=from
# Returns: txhash on stdout
# ==========================================
migrate_contract() {
    local contract_addr="$1" new_code_id="$2" migrate_msg="$3" node="$4"
    local chain_id="$5" gas_prices="$6" from="$7"

    echo "Migrating $contract_addr to code_id $new_code_id" >&2

    local result
    result=$(run_cored cored tx wasm migrate "$contract_addr" "$new_code_id" "$migrate_msg" \
        --from "$from" \
        --node "$node" \
        --chain-id "$chain_id" \
        --keyring-backend "$ASTRO_KEYRING_BACKEND" \
        --gas "$DEFAULT_GAS" \
        --gas-adjustment "$DEFAULT_GAS_ADJUSTMENT" \
        --gas-prices "$gas_prices" \
        --broadcast-mode sync \
        --yes \
        --output json 2>&1) || true

    local tx_result
    tx_result=$(broadcast_and_wait "$result" "$node" "migrate $contract_addr") || return 1

    echo "$tx_result" | jq -r '.txhash'
}

# ==========================================
# precheck_migrate - Verify a migration can succeed, without signing anything.
#
# What this replaces, and why. The obvious approach is `cored tx wasm migrate
# --dry-run`, but that is a dead end on cosmos-sdk v0.50: --from is resolved
# against the keyring even in simulation mode, and neither form works.
#   * a key name  -> "decoding bech32 failed: invalid separator index -1"
#   * an address  -> "<addr>.info: key not found"
# The address form fails because the keyring indexes keys by name; an address
# only resolves if that exact address was imported under its own entry.
#
# The two things a simulation would actually catch are checkable without a
# signer, so check those directly:
#   1. the contract is admin-migratable at all
#   2. its current cw2 version is one the new code's migrate accepts
#
# Args: $1=contract_addr, $2=node, $3=chain_id, $4=expected_contract_name,
#       $5=accepted_versions (space-separated), $6=admin (optional)
# ==========================================
precheck_migrate() {
    local contract_addr="$1" node="$2" chain_id="$3"
    local expect_name="$4" accepted="$5" admin="${6:-}"

    echo "  Prechecking $contract_addr" >&2

    local info
    info=$(cored query wasm contract "$contract_addr" \
        --node "$node" ${chain_id:+--chain-id "$chain_id"} \
        --output json 2>&1) || {
        echo "Error: cannot query $contract_addr" >&2
        echo "$info" >&2
        return 1
    }

    local on_chain_admin
    on_chain_admin=$(echo "$info" | jq -r '.contract_info.admin // empty')
    if [ -z "$on_chain_admin" ]; then
        echo "Error: $contract_addr has no admin and can never be migrated." >&2
        echo "       The only route is a new pair plus a liquidity move." >&2
        return 1
    fi
    if [ -n "$admin" ] && [ "$on_chain_admin" != "$admin" ]; then
        echo "Error: $contract_addr is admin-migratable, but not by you." >&2
        echo "       admin on chain: $on_chain_admin" >&2
        echo "       signing as:     $admin" >&2
        return 1
    fi

    local cw2 name version
    cw2=$(contract_cw2_version "$contract_addr" "$node" "$chain_id")
    if [ -z "$cw2" ]; then
        echo "Error: $contract_addr exposes no cw2 version; refusing to migrate blind." >&2
        return 1
    fi
    name=$(echo "$cw2" | jq -r '.contract // empty')
    version=$(echo "$cw2" | jq -r '.version // empty')

    if [ -n "$expect_name" ] && [ "$name" != "$expect_name" ]; then
        echo "Error: $contract_addr is a '$name', expected '$expect_name'." >&2
        return 1
    fi

    # The migrate entry point accepts an explicit set of prior versions and
    # aborts on anything else. Catching that here keeps a doomed migration
    # from costing a transaction.
    local ok=false v
    for v in $accepted; do
        [ "$version" = "$v" ] && ok=true && break
    done
    if [ "$ok" != true ]; then
        echo "Error: $contract_addr is at version '$version'." >&2
        echo "       The new code only migrates from: $accepted" >&2
        return 1
    fi

    echo "  OK: $name $version, admin $on_chain_admin" >&2
    return 0
}

# ==========================================
# query_contract - Smart-query a contract.
# Args: $1=contract_addr, $2=query_msg, $3=node, $4=chain_id (optional)
# Returns: the .data payload on stdout
#
# chain_id is not optional to cored: without it, cored falls back to the
# bech32 prefix in its own client config, which on a mainnet-configured
# install rejects every testcore address. Defaults to $CHAIN_ID.
# ==========================================
query_contract() {
    local contract_addr="$1" query_msg="$2" node="$3" chain_id="${4:-${CHAIN_ID:-}}"
    cored query wasm contract-state smart "$contract_addr" "$query_msg" \
        --node "$node" ${chain_id:+--chain-id "$chain_id"} \
        --output json 2>/dev/null | jq -r '.data'
}

# ==========================================
# contract_cw2_version - Read the cw2 version of a live contract.
# Reads the raw state key `contract_info`, which cw2 writes on instantiate and
# on every set_contract_version. Used to verify a migration actually landed.
# Args: $1=contract_addr, $2=node
# Returns: e.g. {"contract":"astroport-pair","version":"2.2.1"}
# ==========================================
contract_cw2_version() {
    local contract_addr="$1" node="$2" chain_id="${3:-${CHAIN_ID:-}}"
    # Two flags that both fail silently when missing:
    #   --ascii     lets cored encode the key; a bare string is otherwise read
    #               as base64 and returns nothing.
    #   --chain-id  selects the bech32 prefix. Without it cored uses its own
    #               client config, which on a mainnet-configured install
    #               rejects testcore addresses -- and 2>/dev/null hides why,
    #               leaving an empty version that reads as "not deployed".
    cored query wasm contract-state raw "$contract_addr" 'contract_info' --ascii \
        --node "$node" ${chain_id:+--chain-id "$chain_id"} \
        --output json 2>/dev/null \
        | jq -r '.data // empty' | base64 -d 2>/dev/null
}

# ==========================================
# Deploy log + idempotency primitives
# ------------------------------------------
# The log records, per contract, `.contracts.<key>.{code_id,address}` and, per
# one-shot wiring action, `.steps.<key> = true`. A fresh run creates everything;
# a re-run pointed at a prior log with --resume reuses recorded values and only
# fills the gaps.
#
# These helpers must only run on the live branch. Callers gate them behind their
# DRY() check so --dry-run never mutates a log.
# ==========================================

update_deploy_log() {
    local deploy_log="$1" jq_expr="$2"
    shift 2
    local tmp
    tmp=$(mktemp)
    jq "$jq_expr" "$@" "$deploy_log" > "$tmp" && mv "$tmp" "$deploy_log"
}

# log_get <log> <jq_path> -> recorded value, or "" if absent / null / no file.
log_get() {
    local log="$1" path="$2"
    [ -f "$log" ] || { echo ""; return 0; }
    jq -r "$path // empty" "$log" 2>/dev/null
}

step_done() {
    [ "$(log_get "$1" ".steps[\"$2\"]")" = "true" ]
}

mark_step() {
    update_deploy_log "$1" --arg k "$2" '.steps[$k] = true'
}

# maybe_store <key> <log> <artifact_name> <node> <chain_id> <gas_prices> <from>
# Reuse .contracts[<key>].code_id if recorded, else store and record it.
# Sets CODE_IDS[<key>]; echoes the code id.
maybe_store() {
    local key="$1" log="$2"
    shift 2
    declare -gA CODE_IDS
    local cid
    cid=$(log_get "$log" ".contracts[\"$key\"].code_id")
    if [ -n "$cid" ]; then
        echo "  [skip] $key already stored: code_id $cid" >&2
        CODE_IDS[$key]="$cid"
        echo "$cid"
        return 0
    fi
    cid=$(store_contract "$@") || return 1
    CODE_IDS[$key]="$cid"
    update_deploy_log "$log" --arg k "$key" --arg c "$cid" '.contracts[$k].code_id = $c'
    echo "$cid"
}

# maybe_instantiate <key> <log> <instantiate_contract args...>
# Reuse .contracts[<key>].address if recorded, else instantiate and record it.
# The jq assignment preserves the sibling .code_id written by maybe_store.
# Sets ADDRS[<key>]; echoes the address.
maybe_instantiate() {
    local key="$1" log="$2"
    shift 2
    declare -gA ADDRS
    local addr
    addr=$(log_get "$log" ".contracts[\"$key\"].address")
    if [ -n "$addr" ]; then
        echo "  [skip] $key already instantiated: $addr" >&2
        ADDRS[$key]="$addr"
        echo "$addr"
        return 0
    fi
    addr=$(instantiate_contract "$@") || return 1
    if [ -z "$addr" ]; then
        echo "Error: no address returned for $key" >&2
        return 1
    fi
    ADDRS[$key]="$addr"
    update_deploy_log "$log" --arg k "$key" --arg a "$addr" '.contracts[$k].address = $a'
    echo "$addr"
}

# maybe_exec <log> <step_key> <execute_contract args...>
# Skip if .steps[<step_key>] is already true, else execute and mark the step.
# An empty <log> is tolerated: the exec fires but nothing is recorded.
maybe_exec() {
    local log="$1" step="$2"
    shift 2
    if [ -n "$log" ] && step_done "$log" "$step"; then
        echo "  [skip] step $step already done" >&2
        return 0
    fi
    execute_contract "$@" >/dev/null || return 1
    [ -n "$log" ] && mark_step "$log" "$step"
    return 0
}
