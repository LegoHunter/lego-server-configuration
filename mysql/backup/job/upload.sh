#!/bin/sh
# MySQL backup, step 2 of 2 (HOMELAB-125): send the dumps to the object store and report.
#
# Runs in the curl image as the main container of the CronJob mysql-backup/mysql-backup, after
# dump.sh. For each schema with a complete dump it puts the file in the bucket three ways:
#
#   daily/<schema>/<schema>-<UTC time>.sql.gz    every night; the bucket expires these after 14 days
#   weekly/<schema>/<schema>-<UTC time>.sql.gz   Sundays only; expired after 56 days
#   latest/<schema>.sql.gz                       overwritten every night; what the restore test reads
#
# Expiry is done by the object store's own rules (see ../README.md), not here: this job's user
# cannot delete. Each upload is checked: the store answers with the MD5 of what it received, and
# that must equal the MD5 of the file.
#
# For each schema uploaded it tells the Pushgateway when, how big and how long, and the alert
# MysqlBackupMissing fires when a schema has not succeeded for 26 hours. A schema that failed is
# not reported, so its last success stays as it was.
#
# Exit code 0 only when every schema was dumped and uploaded.
#
# Environment: SCHEMAS, S3_ENDPOINT, S3_BUCKET, S3_REGION, PUSHGATEWAY_URL from the ConfigMap
# mysql-backup-settings; S3_ACCESS_KEY, S3_SECRET_KEY from the Secret mysql-backup-s3.
set -u

IN=/dumps
STAMP="$(cat "$IN/stamp")"
DAY_OF_WEEK="$(date -u +%u)"    # 7 = Sunday. The job runs at 03:00 Eastern, which is the same day in UTC.

# Puts file $1 at key $2. The credentials reach curl on standard input, not on the command line.
put() {
    file="$1"; key="$2"; sha="$3"; md5="$4"
    etag="$(printf 'user = "%s:%s"\n' "$S3_ACCESS_KEY" "$S3_SECRET_KEY" \
        | curl -sS --fail --max-time 900 -K - \
            --aws-sigv4 "aws:amz:${S3_REGION}:s3" \
            -H "x-amz-content-sha256: $sha" \
            -T "$file" -o /dev/null -D - \
            "$S3_ENDPOINT/$S3_BUCKET/$key" \
        | tr -d '\r"' | awk 'tolower($1) == "etag:" { print $2 }')"
    if [ "$etag" != "$md5" ]; then
        echo "mysql_backup.upload_failed key=$key expected_md5=$md5 answered=${etag:-nothing}"
        return 1
    fi
    echo "mysql_backup.uploaded key=$key"
}

report() {
    schema="$1"; seconds="$2"; bytes="$3"
    cat <<METRICS | curl -sS --fail --max-time 30 -o /dev/null --data-binary @- "$PUSHGATEWAY_URL/metrics/job/mysql_backup/schema/$schema"
# HELP mysql_backup_last_success_timestamp_seconds When this schema was last dumped and stored (epoch seconds).
# TYPE mysql_backup_last_success_timestamp_seconds gauge
mysql_backup_last_success_timestamp_seconds $(date +%s)
# HELP mysql_backup_size_bytes Size of the last stored dump of this schema, compressed.
# TYPE mysql_backup_size_bytes gauge
mysql_backup_size_bytes $bytes
# HELP mysql_backup_dump_duration_seconds How long the last dump of this schema took.
# TYPE mysql_backup_dump_duration_seconds gauge
mysql_backup_dump_duration_seconds $seconds
METRICS
}

failed=0
for schema in $SCHEMAS; do
    file="$IN/$schema.sql.gz"
    if [ ! -f "$IN/$schema.ok" ] || [ ! -f "$file" ]; then
        echo "mysql_backup.not_stored schema=$schema reason=dump_failed"
        failed=1
        continue
    fi
    read -r seconds bytes < "$IN/$schema.ok"
    sha="$(sha256sum < "$file" | cut -d' ' -f1)"
    md5="$(md5sum < "$file" | cut -d' ' -f1)"

    keys="daily/$schema/$schema-$STAMP.sql.gz latest/$schema.sql.gz"
    if [ "$DAY_OF_WEEK" = "7" ]; then
        keys="$keys weekly/$schema/$schema-$STAMP.sql.gz"
    fi
    stored=1
    for key in $keys; do
        put "$file" "$key" "$sha" "$md5" || stored=0
    done
    if [ "$stored" = "1" ]; then
        if ! report "$schema" "$seconds" "$bytes"; then
            echo "mysql_backup.report_failed schema=$schema"
            failed=1
        fi
    else
        failed=1
    fi
done

if [ "$failed" = "0" ]; then
    echo "mysql_backup.completed stamp=$STAMP"
else
    echo "mysql_backup.incomplete stamp=$STAMP"
fi
exit "$failed"
