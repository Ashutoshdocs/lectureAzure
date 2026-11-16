#!/usr/bin/env bash
# =============================================================================
# passwordgenerator.sh
#
# Generates a strong VM admin password and stores BOTH the admin username and
# the password as secrets in the manually created Key Vault. The Bicep
# deployment (mainresource.bicep) later reads them with getSecret().
#
# The password is never printed and never passed on the command line
# (it is written to a temp file with 600 permissions and removed afterwards).
#
# Usage (easiest - read vault + secret names from the environment JSON):
#   ./scripts/passwordgenerator.sh --param-file environments/dev/dev.parameters.json --username azureadmin
#
# Usage (explicit):
#   ./scripts/passwordgenerator.sh --vault kv-myapp-shared \
#       --username azureadmin \
#       --username-secret vm-dev-admin-username \
#       --password-secret vm-dev-admin-password
#
# Options:
#   -f, --param-file FILE      Environment parameter JSON (reads keyVaultName,
#                              adminUsernameSecretName, adminPasswordSecretName,
#                              subscriptionId)
#   -v, --vault NAME           Key Vault name (overrides param file)
#   -u, --username NAME        VM admin username (default: azureadmin)
#       --username-secret NAME Secret name for the username
#       --password-secret NAME Secret name for the password
#   -l, --length N             Password length 16-72 (default: 24)
#   -s, --subscription ID      Subscription to use for az (optional)
#       --force                Overwrite / rotate an existing password secret
#   -h, --help                 Show help
#
# Requirements: az CLI (logged in), jq (only with --param-file), openssl or /dev/urandom
# Caller needs "Key Vault Secrets Officer" on the vault (RBAC) or set/get
# secret permissions (access policies).
# =============================================================================
set -euo pipefail

PARAM_FILE=""
VAULT=""
USERNAME="azureadmin"
USERNAME_SECRET=""
PASSWORD_SECRET=""
LENGTH=24
SUBSCRIPTION=""
FORCE="false"

log()  { echo "[passwordgenerator] $*"; }
fail() { echo "[passwordgenerator] ERROR: $*" >&2; exit 1; }
usage() { sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--param-file)      PARAM_FILE="$2"; shift 2 ;;
    -v|--vault)           VAULT="$2"; shift 2 ;;
    -u|--username)        USERNAME="$2"; shift 2 ;;
    --username-secret)    USERNAME_SECRET="$2"; shift 2 ;;
    --password-secret)    PASSWORD_SECRET="$2"; shift 2 ;;
    -l|--length)          LENGTH="$2"; shift 2 ;;
    -s|--subscription)    SUBSCRIPTION="$2"; shift 2 ;;
    --force)              FORCE="true"; shift ;;
    -h|--help)            usage ;;
    *) fail "Unknown argument: $1 (use --help)" ;;
  esac
done

# ---------------------------------------------------- read param file ------
if [[ -n "$PARAM_FILE" ]]; then
  [[ -f "$PARAM_FILE" ]] || fail "Parameter file not found: $PARAM_FILE"
  command -v jq >/dev/null || fail "jq is required with --param-file"
  pf() { jq -r ".parameters.$1.value // empty" "$PARAM_FILE"; }
  [[ -z "$VAULT" ]]           && VAULT="$(pf keyVaultName)"
  [[ -z "$USERNAME_SECRET" ]] && USERNAME_SECRET="$(pf adminUsernameSecretName)"
  [[ -z "$PASSWORD_SECRET" ]] && PASSWORD_SECRET="$(pf adminPasswordSecretName)"
  [[ -z "$SUBSCRIPTION" ]]    && SUBSCRIPTION="$(pf subscriptionId)"
fi

# --------------------------------------------------------- validation ------
[[ -n "$VAULT" && "$VAULT" != \<* ]]  || fail "Key Vault name not set (--vault or keyVaultName in the param file)"
[[ -n "$USERNAME_SECRET" ]]           || fail "Username secret name not set"
[[ -n "$PASSWORD_SECRET" ]]           || fail "Password secret name not set"
[[ "$LENGTH" =~ ^[0-9]+$ ]] && (( LENGTH >= 16 && LENGTH <= 72 )) || fail "Length must be 16-72"
[[ "$SUBSCRIPTION" == \<* ]] && SUBSCRIPTION=""   # placeholder not filled in yet

# Azure VM username rules (common to Linux and Windows)
[[ "$USERNAME" =~ ^[a-zA-Z][a-zA-Z0-9_-]{0,19}$ ]] || fail "Username must start with a letter, 1-20 chars, letters/digits/_/-"
RESERVED="administrator admin user user1 test user2 test1 user3 admin1 1 123 a actuser adm admin2 aspnet backup console david guest john owner root server sql support support_388945a0 sys test2 test3 user4 user5"
for r in $RESERVED; do
  [[ "${USERNAME,,}" == "$r" ]] && fail "Username '$USERNAME' is reserved by Azure. Choose another."
done

command -v az >/dev/null || fail "Azure CLI (az) not found"
az account show >/dev/null 2>&1 || fail "Not logged in. Run 'az login' first."
if [[ -n "$SUBSCRIPTION" ]]; then
  az account set --subscription "$SUBSCRIPTION"
fi
log "Subscription : $(az account show --query name -o tsv)"
log "Key Vault    : $VAULT"

# ------------------------------------------------------ generate password --
rand_from() {  # rand_from <charset> <count>
  LC_ALL=C tr -dc "$1" < /dev/urandom | head -c "$2" || true
}

generate_password() {
  local upper='A-HJ-NP-Z' lower='a-km-z' digits='2-9' special='!@#%^*_+=?-'
  local all="${upper}${lower}${digits}${special}"
  local pw
  # Guarantee at least 2 of each class (Azure requires 3 of 4), then fill & shuffle
  pw="$(rand_from "$upper" 2)$(rand_from "$lower" 2)$(rand_from "$digits" 2)$(rand_from "$special" 2)"
  pw+="$(rand_from "$all" $(( LENGTH - 8 )))"
  echo -n "$pw" | fold -w1 | shuf | tr -d '\n'
}

PASSWORD="$(generate_password)"
[[ ${#PASSWORD} -eq $LENGTH ]] || fail "Password generation failed"
[[ "$PASSWORD" =~ [A-Z] && "$PASSWORD" =~ [a-z] && "$PASSWORD" =~ [0-9] && "$PASSWORD" =~ [^a-zA-Z0-9] ]] \
  || fail "Generated password does not meet complexity requirements"

# --------------------------------------------------------- store secrets ---
TMP="$(mktemp)"
chmod 600 "$TMP"
trap 'rm -f "$TMP"; unset PASSWORD' EXIT

secret_exists() {
  az keyvault secret show --vault-name "$VAULT" --name "$1" --query id -o tsv >/dev/null 2>&1
}

set_secret() {  # set_secret <name> <value> <content-type>
  printf '%s' "$2" > "$TMP"
  az keyvault secret set \
    --vault-name "$VAULT" \
    --name "$1" \
    --file "$TMP" \
    --encoding utf-8 \
    --content-type "$3" \
    --tags managedBy=passwordgenerator.sh createdOn="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --output none
  : > "$TMP"
}

if secret_exists "$PASSWORD_SECRET" && [[ "$FORCE" != "true" ]]; then
  log "Secret '$PASSWORD_SECRET' already exists - leaving it unchanged (use --force to rotate)."
else
  set_secret "$PASSWORD_SECRET" "$PASSWORD" "vm-admin-password"
  log "Stored password in secret '$PASSWORD_SECRET' (${LENGTH} chars)."
fi

set_secret "$USERNAME_SECRET" "$USERNAME" "vm-admin-username"
log "Stored username '$USERNAME' in secret '$USERNAME_SECRET'."

log "Done. The Bicep pipeline will read these secrets when it creates the VM."
log "NOTE: rotating the password secret does NOT change the password of an already-deployed VM."
