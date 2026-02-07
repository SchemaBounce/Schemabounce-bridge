# CLAUDE.md

This file provides guidance to Claude Code when working in this repository.

## Repository Purpose

**SchemaBounce Bridge** is a public, open-source distribution of the SchemaBounce CDC (Change Data Capture) agent. It is deployed **inside customer networks** alongside their databases and streams change events to the SchemaBounce platform.

Published as a container image on **GitHub Container Registry (ghcr.io)**.

### 🚨 DATA PIPELINE ARCHITECTURE — SINGLE SOURCE OF TRUTH 🚨

**[`/mnt/c/git/core-api/docs/DATA_PIPELINE_ARCHITECTURE_MATRIX.md`](/mnt/c/git/core-api/docs/DATA_PIPELINE_ARCHITECTURE_MATRIX.md)**

This is the CUSTOMER-HOSTED, OPTIONAL CDC agent (connection type 3).
For SchemaBounce-hosted CDC pull, see **Database Connector Worker** (`/mnt/c/git/database-connector-worker/`).
For sink delivery (Redis → destinations), see **Sink Worker** (`/mnt/c/git/sink-worker/`).
ALL events go to SchemaBounce-hosted per-environment Redis — NEVER customer-hosted.
The Bridge pushes events OUT of the customer network into SchemaBounce infrastructure.

---

### Security Context

This binary runs inside customer infrastructure with direct access to production databases. Security and container hardening are non-negotiable:

- Customers trust this image to sit on their private network
- It has database credentials and replication access
- Any vulnerability is a direct risk to customer data

### Capture Modes

| Mode | Source | Method | Latency |
|------|--------|--------|---------|
| `wal` | PostgreSQL | Logical Replication | ~milliseconds |
| `mysql_outbox` | MySQL/MariaDB | Outbox Polling | ~3 seconds |
| `mssql_outbox` | SQL Server | Outbox Polling | ~3 seconds |
| `mongodb` | MongoDB | Change Streams | ~milliseconds |
| `kafka` | Kafka | Consumer (Debezium JSON) | ~milliseconds |
| `mysql_binlog` | MySQL/MariaDB | Binary Log Replication | ~milliseconds |

### Sender Modes

| Mode | Target | Status |
|------|--------|--------|
| `redis-direct` | Redis Streams (direct write) | Recommended |
| `http` | Ingest API (HTTP POST) | Deprecated |

## Security Requirements

### Container Image

- **Base image**: Distroless or minimal Alpine - no shells, no package managers in production
- **Non-root**: Container MUST run as non-root user (UID 1000)
- **Static binary**: Built with `CGO_ENABLED=0` - no shared library dependencies
- **No secrets baked in**: All credentials via environment variables or mounted secrets
- **Read-only filesystem**: Container should work with `readOnlyRootFilesystem: true` (data dir is a volume)
- **No capabilities**: Drop all Linux capabilities (`drop: [ALL]`)
- **Signed images**: Container images on ghcr.io should be signed with cosign

### Build Security

- **Reproducible builds**: Pinned Go version, deterministic compilation
- **SBOM**: Generate Software Bill of Materials with each release
- **Vulnerability scanning**: Trivy/Grype scan on every image build
- **No dev dependencies in image**: Multi-stage build, only the static binary in final image
- **Supply chain**: Verify go.sum integrity, use `go mod verify`

### Runtime Security

- **TLS everywhere**: mTLS for Redis connections, TLS for API endpoints
- **HMAC signing**: All API requests are HMAC-signed
- **Credential rotation**: Support for dynamic credential refresh
- **SSH tunnel**: Optional bastion/jump host support for database access
- **Audit logging**: Structured JSON logs for security event tracking
- **Health endpoints**: `/health`, `/health/ready`, `/health/live` for orchestrator probes

### What MUST NOT be in this repo

- Internal file paths or development tooling references
- Hardcoded credentials, API keys, or tokens
- References to internal infrastructure (IPs, hostnames, internal URLs)
- Customer-specific configuration
- Internal Claude plugin/skill configurations

## Repository Structure

```
bin/                    # Pre-compiled bridge binary (for quick testing)
deploy/
  kubernetes/           # Kubernetes deployment manifests
scripts/
  validate-bridge-build.sh  # Build validation (CGO_ENABLED=0 + go vet)
.pre-commit-config.yaml     # Pre-commit hooks
.golangci.yml               # Go linting configuration
```

Source code lives in a separate private repository. This repo contains:
- Pre-compiled binaries
- Deployment manifests and configuration templates
- Container image build/publish automation
- Documentation

## Build Constraints

The bridge binary MUST build with `CGO_ENABLED=0` to produce a static binary for distroless/Alpine containers. This means:

- No C dependencies allowed in the bridge import chain
- Oracle driver (`godror`) is excluded via build tags (`//go:build !cgo`)
- All database drivers used by the bridge must be pure Go
- MongoDB driver (`go.mongodb.org/mongo-driver`) is pure Go - compatible
- Kafka library (`github.com/segmentio/kafka-go`) is pure Go - compatible (do NOT use `confluent-kafka-go` which requires CGO)
- MySQL binlog library (`github.com/go-mysql-org/go-mysql`) is pure Go - compatible
- Pre-commit hook `bridge-build-quick` validates this on every commit

### Build-tagged executor files

In the source repo, executor registrations are split by CGO availability:

| File | Build Tag | Executors |
|------|-----------|-----------|
| `executors_cgo.go` | `//go:build cgo` | postgres, mysql, mssql, oracle |
| `executors_nocgo.go` | `//go:build !cgo` | postgres, mysql, mssql |

## Container Image Publishing

Images are published to `ghcr.io/schemabounce/bridge`.

### Tagging Strategy

- `latest` - latest stable release
- `vX.Y.Z` - semantic version tags
- `sha-<commit>` - commit-pinned images for traceability

### Image Hardening Checklist

When modifying the Dockerfile or image build:

- [ ] Multi-stage build (builder stage discarded)
- [ ] `CGO_ENABLED=0` static binary
- [ ] Non-root user (UID 1000)
- [ ] No shell in final image (prefer distroless, or Alpine with shell removed)
- [ ] `HEALTHCHECK` instruction present
- [ ] No secrets in image layers
- [ ] Minimal attack surface (no unnecessary packages)
- [ ] Image scanned with Trivy/Grype before publish
- [ ] SBOM generated and attached

## Configuration

All configuration via environment variables (no config files baked into the image):

### Core

| Variable | Description | Required |
|----------|-------------|----------|
| `BRIDGE_MODE` | `wal`, `mysql_outbox`, `mssql_outbox`, `mongodb`, `kafka`, or `mysql_binlog` | Yes |
| `SENDER_MODE` | `redis-direct` (recommended) or `http` | Yes |
| `LOG_LEVEL` | `debug`, `info`, `warn`, `error` | No (default: `info`) |
| `LOG_FORMAT` | `json` or `text` | No (default: `json`) |
| `HEALTH_PORT` | Health check port | No (default: `8081`) |
| `DATA_DIR` | Cursor persistence directory | No (default: `/var/lib/schemabounce-bridge`) |

### PostgreSQL WAL Mode

| Variable | Description |
|----------|-------------|
| `DB_HOST` | PostgreSQL host |
| `DB_PORT` | PostgreSQL port (default: 5432) |
| `DB_NAME` | Database name |
| `DB_USER` | Replication user |
| `DB_PASSWORD` | Password |
| `REPLICATION_SLOT` | Logical replication slot name |

### Redis Direct Mode

| Variable | Description |
|----------|-------------|
| `REDIS_DIRECT_URL` | Redis connection URL |
| `WORKSPACE_ID` | SchemaBounce workspace ID |
| `ENVIRONMENT_ID` | SchemaBounce environment ID |
| `REDIS_TLS_ENABLED` | Enable mTLS (`true`/`false`) |
| `REDIS_CA_CERT_FILE` | CA certificate path |
| `REDIS_CLIENT_CERT_FILE` | Client certificate path |
| `REDIS_CLIENT_KEY_FILE` | Client key path |

### MongoDB Change Streams Mode

| Variable | Description |
|----------|-------------|
| `MONGODB_URI` | MongoDB connection string |
| `MONGODB_DATABASE` | Database to watch for changes |
| `MONGODB_POLL_TIMEOUT` | Max wait time for next event (default: `10s`) |
| `MONGODB_BATCH_SIZE` | Change stream batch size (default: `100`) |
| `MONGODB_FULL_DOCUMENT` | Full document option: `updateLookup`, `whenAvailable` (default: `updateLookup`) |

### Kafka Consumer Mode

| Variable | Description |
|----------|-------------|
| `KAFKA_BROKERS` | Comma-separated broker addresses |
| `KAFKA_TOPIC` | Topic to consume (Debezium JSON format) |
| `KAFKA_GROUP_ID` | Consumer group ID (default: `schemabounce-bridge`) |
| `KAFKA_START_OFFSET` | `earliest` or `latest` (default: `latest`) |
| `KAFKA_COMMIT_INTERVAL` | Offset commit interval (default: `1s`) |
| `KAFKA_TLS_ENABLED` | Enable TLS (`true`/`false`) |
| `KAFKA_CA_CERT_FILE` | CA certificate path |
| `KAFKA_CLIENT_CERT_FILE` | Client certificate path |
| `KAFKA_CLIENT_KEY_FILE` | Client key path |
| `KAFKA_SASL_ENABLED` | Enable SASL authentication (`true`/`false`) |
| `KAFKA_SASL_MECHANISM` | `PLAIN`, `SCRAM-SHA-256`, or `SCRAM-SHA-512` |
| `KAFKA_SASL_USERNAME` | SASL username |
| `KAFKA_SASL_PASSWORD` | SASL password |

### MySQL Binlog Mode

| Variable | Description |
|----------|-------------|
| `MYSQL_BINLOG_HOST` | MySQL host |
| `MYSQL_BINLOG_PORT` | MySQL port (default: 3306) |
| `MYSQL_BINLOG_USER` | Replication user (needs REPLICATION SLAVE, REPLICATION CLIENT) |
| `MYSQL_BINLOG_PASSWORD` | Password |
| `MYSQL_BINLOG_DATABASE` | Database name (for INFORMATION_SCHEMA queries) |
| `MYSQL_BINLOG_SERVER_ID` | Unique server ID for replication (required, must be > 0) |
| `MYSQL_BINLOG_FLAVOR` | `mysql` or `mariadb` (default: `mysql`) |
| `MYSQL_BINLOG_GTID_ENABLED` | Use GTID-based replication (`true`/`false`) |
| `MYSQL_BINLOG_START_POSITION` | Start position as `file:pos` (e.g., `mysql-bin.000001:4`) |
| `MYSQL_BINLOG_START_GTID` | Start GTID set (e.g., `uuid:1-5`) |
| `MYSQL_BINLOG_TLS_ENABLED` | Enable TLS (`true`/`false`) |
| `MYSQL_BINLOG_CA_CERT_FILE` | CA certificate path |
| `MYSQL_BINLOG_CLIENT_CERT_FILE` | Client certificate path |
| `MYSQL_BINLOG_CLIENT_KEY_FILE` | Client key path |
| `MYSQL_BINLOG_HEARTBEAT_PERIOD` | Heartbeat interval (default: `30s`) |
| `MYSQL_BINLOG_INCLUDE_DATABASES` | Comma-separated list of databases to include |
| `MYSQL_BINLOG_EXCLUDE_DATABASES` | Comma-separated list of databases to exclude |
| `MYSQL_BINLOG_INCLUDE_TABLES` | Comma-separated list of tables to include |
| `MYSQL_BINLOG_EXCLUDE_TABLES` | Comma-separated list of tables to exclude |

### SSH Tunnel (Optional)

| Variable | Description |
|----------|-------------|
| `SSH_TUNNEL_ENABLED` | Enable SSH tunnel (`true`/`false`) |
| `SSH_BASTION_HOST` | Bastion/jump host address |
| `SSH_BASTION_PORT` | SSH port (default: 22) |
| `SSH_BASTION_USER` | SSH username |
| `SSH_PRIVATE_KEY` | PEM-encoded private key |

## Pre-commit Hooks

```bash
# Install
pip install pre-commit && pre-commit install

# Run build validation manually
pre-commit run bridge-build-validate --hook-stage manual

# Run all hooks
pre-commit run --all-files
```

### Hooks

| Hook | Stage | Purpose |
|------|-------|---------|
| `bridge-build-quick` | commit | Validates `CGO_ENABLED=0` build compiles |
| `bridge-build-validate` | manual | Full validation: build + go vet + static link check |
| `gitleaks` | commit | Secret detection |
| `detect-private-key` | commit | Prevents committing private keys |
| `check-added-large-files` | commit | Blocks files > 1MB |
| `no-commit-to-branch` | commit | Prevents direct commits to main |
