#!/bin/sh
# Restore test, step 1 of 2 (HOMELAB-125): fetch the latest stored dump of each schema.
#
# Runs in the curl image as the first container of the Job mysql-backup/mysql-restore-test.
# It reads latest/<schema>.sql.gz from the bucket, which the nightly job overwrites every night,
# into /dumps. It fails when any dump is missing, so the test never passes on a partial set.
#
# Environment: SCHEMAS, S3_ENDPOINT, S3_BUCKET, S3_REGION from the ConfigMap mysql-backup-settings;
# S3_ACCESS_KEY, S3_SECRET_KEY from the Secret mysql-backup-s3.
set -u

# A signed request must state the SHA-256 of its body; a GET has none, so this is the hash of nothing.
EMPTY_BODY_SHA256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855

failed=0
for schema in $SCHEMAS; do
    key="latest/$schema.sql.gz"
    if printf 'user = "%s:%s"\n' "$S3_ACCESS_KEY" "$S3_SECRET_KEY" \
        | curl -sS --fail --max-time 900 -K - \
            --aws-sigv4 "aws:amz:${S3_REGION}:s3" \
            -H "x-amz-content-sha256: $EMPTY_BODY_SHA256" \
            -o "/dumps/$schema.sql.gz" \
            "$S3_ENDPOINT/$S3_BUCKET/$key"; then
        echo "restore_test.fetched key=$key bytes=$(wc -c < "/dumps/$schema.sql.gz")"
    else
        echo "restore_test.fetch_failed key=$key"
        failed=1
    fi
done
exit "$failed"
