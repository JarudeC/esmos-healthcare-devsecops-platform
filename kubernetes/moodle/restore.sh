#!/bin/bash
# ─────────────────────────────────────────────────────────
# Moodle MariaDB Restore Script
# ─────────────────────────────────────────────────────────
# Usage: bash kubernetes/moodle/restore.sh [backup-filename]
# Example: bash kubernetes/moodle/restore.sh moodle-backup-20260314-020000.sql
#
# Lists available backups if no filename provided.
# ─────────────────────────────────────────────────────────

BUCKET="esmos-healthcare-tfstate"
BACKUP_PATH="gs://$BUCKET/moodle-backups"

if [ -z "$1" ]; then
  echo "Available backups:"
  gcloud storage ls "$BACKUP_PATH/"
  echo ""
  echo "Usage: bash kubernetes/moodle/restore.sh <backup-filename>"
  exit 0
fi

BACKUP_FILE="$1"
echo "Downloading $BACKUP_FILE..."
gcloud storage cp "$BACKUP_PATH/$BACKUP_FILE" /tmp/restore.sql

echo "Restoring to Moodle MariaDB..."
MARIADB_POD=$(kubectl get pods -n moodle -l app.kubernetes.io/name=mariadb -o jsonpath='{.items[0].metadata.name}')
kubectl cp /tmp/restore.sql "moodle/$MARIADB_POD:/tmp/restore.sql"
kubectl exec -n moodle "$MARIADB_POD" -- bash -c 'mysql -u root -p"$MARIADB_ROOT_PASSWORD" moodle < /tmp/restore.sql'

echo "Restore complete. Restarting Moodle pods..."
kubectl rollout restart deployment -n moodle -l app.kubernetes.io/name=moodle

rm /tmp/restore.sql
echo "Done."
