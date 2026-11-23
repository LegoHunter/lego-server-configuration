#!/bin/bash
# MySQL backup, step 1 of 2 (HOMELAB-125): dump each schema to a gzip file.
#
# Runs in the official mysql image as the first container of the CronJob mysql-backup/mysql-backup.
# upload.sh, the second container, sends the files to the object store.
#
# For each schema in $SCHEMAS it writes /dumps/<schema>.sql.gz and, only when the dump is complete,
# /dumps/<schema>.ok with "<seconds taken> <bytes>". A schema whose dump fails gets no .ok file and
# its partial file is removed; the others are still dumped. This script always exits 0, so that the
# upload step runs and reports: upload.sh fails the job when any .ok file is missing.
#
# The dump:
#   --single-transaction  one consistent snapshot of the InnoDB tables, without locking them
#   --source-data=2       the binary log file and position of that snapshot, as a comment at the top
#                         of the dump. A restore can be rolled forward from there with the binary
#                         logs. Costs a global read lock for an instant at the start.
#   no --databases        the dump has no CREATE DATABASE or USE, so it can be loaded into a schema
#                         of any name (the restore test relies on that)
#
# Environment: MYSQL_HOST, MYSQL_PORT, SCHEMAS (space separated) from the ConfigMap
# mysql-backup-settings; MYSQL_USER, MYSQL_PASSWORD from the Secret mysql-backup-db.
set -uo pipefail
# Group-readable, so the upload step (another user, same group) can read the dumps. Nothing else can.
umask 027

OUT=/dumps
date -u +%Y%m%dT%H%M%SZ > "$OUT/stamp"

# The password goes into a client option file in memory-backed /tmp, never onto a command line.
CLIENT_CNF=/tmp/client.cnf
( umask 077; : > "$CLIENT_CNF" )
cat > "$CLIENT_CNF" <<CNF
[client]
host=${MYSQL_HOST}
port=${MYSQL_PORT}
user=${MYSQL_USER}
password="${MYSQL_PASSWORD}"
CNF

for schema in $SCHEMAS; do
    started=$(date +%s)
    file="$OUT/$schema.sql.gz"
    errors="/tmp/$schema.err"
    mysqldump --defaults-extra-file="$CLIENT_CNF" \
        --single-transaction --source-data=2 --no-tablespaces --set-gtid-purged=OFF \
        --routines --triggers --events --hex-blob --default-character-set=utf8mb4 \
        "$schema" 2> "$errors" | gzip -6 > "$file"
    dump_status=${PIPESTATUS[0]}
    # mysqldump writes this line last; a dump cut short does not have it.
    if [ "$dump_status" -eq 0 ] && gzip -t "$file" 2>/dev/null \
            && zcat "$file" | tail -n 1 | grep -q '^-- Dump completed'; then
        seconds=$(( $(date +%s) - started ))
        bytes=$(stat -c %s "$file")
        echo "$seconds $bytes" > "$OUT/$schema.ok"
        echo "mysql_backup.dumped schema=$schema seconds=$seconds bytes=$bytes"
    else
        rm -f "$file"
        echo "mysql_backup.dump_failed schema=$schema exit=$dump_status message=$(tr '\n' ' ' < "$errors" | cut -c1-500)"
    fi
done
exit 0
