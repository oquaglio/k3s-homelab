# pg-backup - PostgreSQL Backup & Restore

Automated PostgreSQL backup and restore using any S3-compatible cloud storage (Cloudflare R2, AWS S3, Backblaze B2, MinIO, etc.).

## How It Works

- **Scheduled backups** via a Kubernetes CronJob (daily at 2 AM UTC by default)
- **Pre-destroy backup** triggered automatically by `destroy.sh` before tearing down the cluster
- **Post-deploy restore** triggered automatically by `deploy.sh` after PostgreSQL is up
- Uses `pg_dump`/`pg_restore` (custom format, compressed) and [MinIO Client (mc)](https://min.io/docs/minio/linux/reference/minio-mc.html) for S3 operations

## Architecture

```
┌─────────────┐     pg_dump      ┌──────────┐    mc cp     ┌─────────────────┐
│  PostgreSQL  │ ──────────────> │  /tmp/*.dump │ ────────> │  S3 Bucket       │
│  (in-cluster)│                 │  (pod local) │           │  (Cloudflare R2) │
└─────────────┘                 └──────────┘            └─────────────────┘
       ▲                                                        │
       │            pg_restore           mc cp                  │
       └──────────────────────── /tmp/restore.dump <────────────┘
```

Two CronJobs are created:
1. **pg-backup-pg-backup-backup** - Active, runs on schedule
2. **pg-backup-pg-backup-restore** - Suspended, only triggered manually via `kubectl create job`

## Setup

### 1. Create your `.env` file

Copy the example and fill in your S3 credentials:

```bash
cp .env.example .env
# Edit .env with your real credentials
```

The `.env` file is gitignored and will never be committed. It contains:

```bash
S3_ENDPOINT="https://<account-id>.r2.cloudflarestorage.com"
S3_ACCESS_KEY="your-access-key"
S3_SECRET_KEY="your-secret-key"
S3_BUCKET="pg-backups"
```

### 2. Deploy

`deploy.sh` automatically sources `.env` and passes credentials to Helm via `--set`.
If `.env` is missing or S3 credentials are empty, the pg-backup step is skipped gracefully.

### Manual deploy (without deploy.sh)

```bash
helm upgrade --install pg-backup ./charts/pg-backup \
  --namespace postgresql \
  --set s3.endpoint=https://xxxx.r2.cloudflarestorage.com \
  --set s3.accessKey=YOUR_KEY \
  --set s3.secretKey=YOUR_SECRET \
  --set s3.bucket=pg-backups
```

## Configuration

Non-secret settings can be changed in `values.yaml`:

```yaml
# Backup schedule (cron format)
schedule: "0 2 * * *"    # Daily at 2 AM UTC

# Retention
backup:
  retentionDays: 30       # Auto-delete backups older than this

# S3 bucket name (can also be set via .env S3_BUCKET)
s3:
  bucket: "pg-backups"
```

## Manual Operations

### Trigger a backup now

```bash
kubectl create job manual-backup \
  --from=cronjob/pg-backup-pg-backup-backup -n postgresql
```

### Trigger a restore now

```bash
kubectl create job manual-restore \
  --from=cronjob/pg-backup-pg-backup-restore -n postgresql
```

### Watch backup/restore logs

```bash
kubectl logs -f job/manual-backup -n postgresql
kubectl logs -f job/manual-restore -n postgresql
```

### List backups in S3

The backup job logs list all current backups. You can also check directly via the mc CLI or your cloud provider's dashboard.

## Backup File Naming

Backups are stored as: `homelab-YYYYMMDD-HHMMSS.dump`

Example: `homelab-20260208-020000.dump`

The naming convention ensures alphabetical sorting equals chronological sorting, so the restore script always picks the most recent backup.

## Integration with deploy.sh / destroy.sh

### On deploy (Step 8)
1. Deploys the pg-backup Helm chart
2. Creates a one-off restore job from the suspended CronJob
3. The restore script checks S3 for existing backups
4. If a backup exists, downloads and restores it
5. If no backup exists (fresh install), exits gracefully

### On destroy (Step 1)
1. Before any teardown, triggers a one-off backup job
2. Waits up to 5 minutes for the backup to complete
3. If pg-backup isn't deployed, skips gracefully
4. Then proceeds with normal destroy steps

## Files

```
charts/pg-backup/
├── Chart.yaml                          # Chart metadata
├── README.md                           # This file
├── values.yaml                         # Configuration defaults
├── scripts/
│   ├── backup.sh                       # Backup script (pg_dump + mc upload)
│   └── restore.sh                      # Restore script (mc download + pg_restore)
└── templates/
    ├── _helpers.tpl                    # Template helpers
    ├── configmap-scripts.yaml          # Mounts scripts into pods
    ├── cronjob-backup.yaml             # Scheduled backup CronJob
    ├── cronjob-restore.yaml            # Suspended restore CronJob
    └── secret.yaml                     # S3 credentials (base64 encoded)
```
