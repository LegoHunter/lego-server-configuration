#!/usr/bin/env bash
# Creates the read-only MySQL account the nightly backup dumps with, on rasppi5-01 (HOMELAB-125).
#
#   lcms_backup   On each backed-up schema: SELECT, SHOW VIEW, TRIGGER, EVENT (what mysqldump reads).
#                 Server-wide: RELOAD and REPLICATION CLIENT, which mysqldump needs to record the
#                 binary log position of the dump (--source-data), and SHOW_ROUTINE, to read stored
#                 routines. None of these can change data.
#
# The account can read everything in the schemas it backs up, including the live lego_prod_legacy.
# It cannot write anywhere. Its password goes ONLY into Infisical Production, secret mysql-backup.
#
# Run on rasppi5-01 as a user that can `sudo mysql` (root via auth_socket):
#   bash setup-mysql-backup-account.sh
#
# Optional:
#   BACKUP_USER   account name (default: lcms_backup)
#   SCHEMAS       schemas to back up, space separated (default: the five application schemas).
#                 Keep it equal to SCHEMAS in job/kustomization.yaml.
#   CLIENT_HOST   host pattern the account may connect from (default: 10.0.% -> homelab LAN, which
#                 covers the cluster nodes)
#   MYSQL_CMD     command used to run SQL as root (default: sudo mysql)
#   DRY_RUN=1     print the SQL with the password hidden and change nothing
#
# Password: press Enter to generate one, or type "keep" to leave an existing account's password as
# it is. A generated password is shown ONCE at the end and is never written to disk. Re-running is
# safe: the account's grants are re-applied from scratch, so a schema removed from SCHEMAS loses
# its grant.
set -euo pipefail

BACKUP_USER="${BACKUP_USER:-lcms_backup}"
SCHEMAS="${SCHEMAS:-lego_prod_legacy lego_prod lego_sandbox lego_dev marketplace_pricing}"
CLIENT_HOST="${CLIENT_HOST:-10.0.%}"
MYSQL_CMD="${MYSQL_CMD:-sudo mysql}"
DRY_RUN="${DRY_RUN:-0}"

NAME_PATTERN='^[A-Za-z0-9_]{1,32}$'
[[ "$BACKUP_USER" =~ $NAME_PATTERN ]] || { echo "Not a plain MySQL user name: $BACKUP_USER" >&2; exit 1; }
[[ "$CLIENT_HOST" =~ ^[A-Za-z0-9.%_-]{1,255}$ ]] || { echo "Not a plain host pattern: $CLIENT_HOST" >&2; exit 1; }
for schema in $SCHEMAS; do
  [[ "$schema" =~ ^[A-Za-z0-9_]{1,64}$ ]] || { echo "Not a plain schema name: $schema" >&2; exit 1; }
done

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

# A schema that does not exist yet can still be granted, but say so: it is probably a typing error.
for schema in $SCHEMAS; do
  if [[ "$(query "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = '$schema'")" != "1" ]]; then
    echo "NOTE: schema $schema does not exist on this server (granted anyway)." >&2
  fi
done

read -rsp "Password for ${BACKUP_USER} (Enter = generate, \"keep\" = leave unchanged): " PW </dev/tty
echo >/dev/tty
if [[ -z "$PW" ]]; then
  PW="$(gen_password)"
elif [[ "$PW" == "keep" ]]; then
  [[ "$(query "SELECT COUNT(*) FROM mysql.user WHERE User = '${BACKUP_USER}' AND Host = '${CLIENT_HOST}'")" == "1" ]] \
    || { echo "${BACKUP_USER}@${CLIENT_HOST} does not exist yet, so there is no password to keep." >&2; exit 1; }
  PW=""
elif [[ ! "$PW" =~ ^[A-Za-z0-9]{16,}$ ]]; then
  echo "Password must be >= 16 alphanumeric characters (or press Enter to generate)." >&2
  exit 1
fi

SQL=""
if [[ -n "$PW" ]]; then
  SQL+="CREATE USER IF NOT EXISTS '${BACKUP_USER}'@'${CLIENT_HOST}' IDENTIFIED BY '${PW}';
ALTER USER '${BACKUP_USER}'@'${CLIENT_HOST}' IDENTIFIED BY '${PW}' WITH MAX_USER_CONNECTIONS 5;
"
else
  SQL+="ALTER USER '${BACKUP_USER}'@'${CLIENT_HOST}' WITH MAX_USER_CONNECTIONS 5;
"
fi
# Start from nothing, so a re-run cannot leave an old grant behind.
SQL+="REVOKE ALL PRIVILEGES, GRANT OPTION FROM '${BACKUP_USER}'@'${CLIENT_HOST}';
GRANT RELOAD, REPLICATION CLIENT, SHOW_ROUTINE ON *.* TO '${BACKUP_USER}'@'${CLIENT_HOST}';
"
# In GRANT ... ON `db`.*, '_' is a wildcard; escape it so the grant matches the exact schema.
for schema in $SCHEMAS; do
  escaped="$(printf '%s' "$schema" | sed 's/_/\\_/g')"
  SQL+="GRANT SELECT, SHOW VIEW, TRIGGER, EVENT ON \`${escaped}\`.* TO '${BACKUP_USER}'@'${CLIENT_HOST}';
"
done

if [[ "$DRY_RUN" == "1" ]]; then
  echo "DRY RUN: nothing is changed. The SQL that would run (password hidden):"
  echo
  hidden="$SQL"
  [[ -n "$PW" ]] && hidden="${hidden//$PW/<hidden>}"
  printf '%s' "$hidden"
  exit 0
fi

$MYSQL_CMD <<<"$SQL"

echo
echo "Done. Grants:"
query "SHOW GRANTS FOR '${BACKUP_USER}'@'${CLIENT_HOST}'"

echo
echo "================================================================================"
echo " Shown once and not saved anywhere. Clear the terminal when done."
echo
if [[ -n "$PW" ]]; then
  echo " Infisical, environment Production, secret mysql-backup:"
  echo "   {\"username\": \"${BACKUP_USER}\", \"password\": \"${PW}\"}"
else
  echo " ${BACKUP_USER}: password unchanged."
fi
echo "================================================================================"
