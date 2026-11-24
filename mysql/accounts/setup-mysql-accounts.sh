#!/usr/bin/env bash
# Creates the application and deployer accounts of the lower environments and of the shared
# marketplace_pricing schema on rasppi5-01, with exactly the rights each needs (HOMELAB-126).
#
#   lcms_sandbox_app        SELECT, INSERT, UPDATE, DELETE on lego_sandbox; the pricing rights below.
#   lcms_dev_app            the same on lego_dev.
#   lcms_sandbox_deployer   ALL on lego_sandbox. For lego-database-deployer only.
#   lcms_dev_deployer       ALL on lego_dev. For lego-database-deployer only.
#   lcms_pricing_deployer   ALL on marketplace_pricing and marketplace_pricing_scratch.
#   lcms_pricing_crawler    SELECT, INSERT, UPDATE, DELETE on marketplace_pricing. The price crawler's
#                           own connection. Nothing on any environment schema.
#   lcms_prod_app           (exists) gets the one pricing right it lacks: INSERT on canonical_item.
#
# Pricing rights of an application account: SELECT on marketplace_pricing, INSERT, UPDATE, DELETE
# on want_list_item (each environment keeps its own want list), INSERT on canonical_item (the
# want-list job adds an item the first time an environment wants it).
#
# None of these accounts can reach lego_prod_legacy, and no lower-environment account can reach
# lego_prod. No application account can change a table's structure or grant rights.
#
# It does NOT touch legomgr, tvattima or any other existing account: see narrow-accounts.sh.
#
# Run on rasppi5-01 as a user that can `sudo mysql` (root via auth_socket):
#   DRY_RUN=1 bash setup-mysql-accounts.sh      # prints the SQL, changes nothing
#   bash setup-mysql-accounts.sh
#
# Passwords: an account that does not exist yet gets a generated password. An account that exists
# keeps its password, unless it is named in ROTATE. Generated passwords are shown ONCE at the end,
# with where each one goes, and are never written to disk.
#
# Optional:
#   ROTATE        accounts to give a new password, space separated, e.g. ROTATE="lcms_dev_app"
#   CLIENT_HOST   host pattern the accounts may connect from (default: 10.0.% -> homelab LAN and VPN)
#   MYSQL_CMD     command used to run SQL as root (default: sudo mysql)
#   DRY_RUN=1     print the SQL with passwords hidden and change nothing
#
# Re-running is safe: each account's grants are re-applied from scratch (lcms_prod_app: added only).
set -euo pipefail

CLIENT_HOST="${CLIENT_HOST:-10.0.%}"
MYSQL_CMD="${MYSQL_CMD:-sudo mysql}"
DRY_RUN="${DRY_RUN:-0}"
ROTATE="${ROTATE:-}"
PROD_APP_USER="lcms_prod_app"

[[ "$CLIENT_HOST" =~ ^[A-Za-z0-9.%_-]{1,255}$ ]] || { echo "Not a plain host pattern: $CLIENT_HOST" >&2; exit 1; }

# name | kind | schemas | MAX_USER_CONNECTIONS | where the password goes
# App accounts, 100 connections: lego-data-ingress pools up to 40 and lego-data-service up to 10,
# with room for a rolling restart and a run from the owner's PC. The deployer pools 5.
ACCOUNTS="
lcms_sandbox_app|app|lego_sandbox|100|Infisical Sandbox, database-configuration.yml, key rasppi5-01-lego-sandbox. Also D:\\dev\\config\\database-configuration.yml, same key.
lcms_dev_app|app|lego_dev|100|Infisical Development, database-configuration.yml, key rasppi5-01-lego-dev.
lcms_sandbox_deployer|deployer|lego_sandbox|10|D:\\dev\\config\\database-configuration.yml, key rasppi5-01-lego-sandbox-deployer.
lcms_dev_deployer|deployer|lego_dev|10|D:\\dev\\config\\database-configuration.yml, key rasppi5-01-lego-dev-deployer.
lcms_pricing_deployer|deployer|marketplace_pricing marketplace_pricing_scratch|10|D:\\dev\\config\\database-configuration.yml, keys rasppi5-01-marketplace-pricing and rasppi5-01-marketplace-pricing-scratch.
lcms_pricing_crawler|crawler|marketplace_pricing|10|Infisical Sandbox, database-configuration.yml, key rasppi5-01-marketplace-pricing-crawler.
"

query() {
  $MYSQL_CMD -N -B -e "$1"
}

gen_password() {
  # head closes the pipe after 32 characters, so tr dies of SIGPIPE. Under pipefail that makes the
  # pipeline "fail" and set -e would end the script silently: ignore the status, check the length.
  local pw
  pw="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32 || true)"
  [[ ${#pw} -eq 32 ]] || { echo "Could not generate a password" >&2; exit 1; }
  printf '%s' "$pw"
}

account_exists() {
  [[ "$(query "SELECT COUNT(*) FROM mysql.user WHERE User = '$1' AND Host = '${CLIENT_HOST}'")" == "1" ]]
}

# In GRANT ... ON `db`.*, '_' is a wildcard; escape it so the grant matches the exact schema.
# Table-level grants (`db`.`table`) take the name literally and must not be escaped.
escaped() {
  printf '%s' "$1" | sed 's/_/\\_/g'
}

for name in $ROTATE; do
  grep -q "^${name}|" <<<"$ACCOUNTS" || { echo "ROTATE names an account this script does not manage: $name" >&2; exit 1; }
done

# The table-level pricing grants need the tables to exist.
for table in want_list_item canonical_item; do
  [[ "$(query "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = 'marketplace_pricing' AND TABLE_NAME = '$table'")" == "1" ]] \
    || { echo "marketplace_pricing.$table does not exist. Build the pricing schema with the deployer first." >&2; exit 1; }
done
for schema in lego_sandbox lego_dev marketplace_pricing marketplace_pricing_scratch; do
  [[ "$(query "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = '$schema'")" == "1" ]] \
    || { echo "Schema $schema does not exist on this server." >&2; exit 1; }
done

pricing_rights_sql() {
  local user="$1"
  printf "GRANT SELECT ON \`marketplace\\_pricing\`.* TO '%s'@'%s';\n" "$user" "$CLIENT_HOST"
  printf "GRANT INSERT, UPDATE, DELETE ON \`marketplace_pricing\`.\`want_list_item\` TO '%s'@'%s';\n" "$user" "$CLIENT_HOST"
  printf "GRANT INSERT ON \`marketplace_pricing\`.\`canonical_item\` TO '%s'@'%s';\n" "$user" "$CLIENT_HOST"
}

SQL=""
GENERATED=""          # lines "name|password|where"
PASSWORDS=()          # for hiding in the dry run
while IFS='|' read -r name kind schemas max_connections where; do
  [[ -n "$name" ]] || continue
  pw=""
  if ! account_exists "$name" || grep -qw "$name" <<<"$ROTATE"; then
    pw="$(gen_password)"
    PASSWORDS+=("$pw")
    GENERATED+="${name}|${pw}|${where}"$'\n'
    SQL+="CREATE USER IF NOT EXISTS '${name}'@'${CLIENT_HOST}' IDENTIFIED BY '${pw}';
ALTER USER '${name}'@'${CLIENT_HOST}' IDENTIFIED BY '${pw}' WITH MAX_USER_CONNECTIONS ${max_connections};
"
  else
    SQL+="ALTER USER '${name}'@'${CLIENT_HOST}' WITH MAX_USER_CONNECTIONS ${max_connections};
"
  fi
  # Start from nothing, so a re-run cannot leave an old grant behind.
  SQL+="REVOKE ALL PRIVILEGES, GRANT OPTION FROM '${name}'@'${CLIENT_HOST}';
"
  for schema in $schemas; do
    case "$kind" in
      app|crawler) rights="SELECT, INSERT, UPDATE, DELETE" ;;
      deployer)    rights="ALL PRIVILEGES" ;;
      *) echo "Unknown kind: $kind" >&2; exit 1 ;;
    esac
    SQL+="GRANT ${rights} ON \`$(escaped "$schema")\`.* TO '${name}'@'${CLIENT_HOST}';
"
  done
  if [[ "$kind" == "app" ]]; then
    SQL+="$(pricing_rights_sql "$name")
"
  fi
done <<<"$ACCOUNTS"

# The PROD application account is created by setup-lego-prod.sh. Add the right it lacks; change
# nothing else about it.
if account_exists "$PROD_APP_USER"; then
  SQL+="GRANT INSERT ON \`marketplace_pricing\`.\`canonical_item\` TO '${PROD_APP_USER}'@'${CLIENT_HOST}';
"
else
  echo "NOTE: ${PROD_APP_USER}@${CLIENT_HOST} does not exist; skipped." >&2
fi

if [[ "$DRY_RUN" == "1" ]]; then
  echo "DRY RUN: nothing is changed. The SQL that would run (passwords hidden):"
  echo
  hidden="$SQL"
  for pw in "${PASSWORDS[@]:-}"; do
    [[ -n "$pw" ]] && hidden="${hidden//$pw/<hidden>}"
  done
  printf '%s' "$hidden"
  exit 0
fi

$MYSQL_CMD <<<"$SQL"

echo
echo "Done. Grants:"
while IFS='|' read -r name _; do
  [[ -n "$name" ]] || continue
  echo "--- ${name}"
  query "SHOW GRANTS FOR '${name}'@'${CLIENT_HOST}'" | sed 's/^/  /'
done <<<"$ACCOUNTS"
if account_exists "$PROD_APP_USER"; then
  echo "--- ${PROD_APP_USER}"
  query "SHOW GRANTS FOR '${PROD_APP_USER}'@'${CLIENT_HOST}'" | sed 's/^/  /'
fi

echo
echo "================================================================================"
if [[ -n "$GENERATED" ]]; then
  echo " New passwords. Shown once and not saved anywhere. Clear the terminal when done."
  while IFS='|' read -r name pw where; do
    [[ -n "$name" ]] || continue
    echo
    echo " ${name}"
    echo "   password: ${pw}"
    echo "   goes in:  ${where}"
  done <<<"$GENERATED"
else
  echo " No password was changed."
fi
echo "================================================================================"
