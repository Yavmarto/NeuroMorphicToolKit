# NMTK Production Deployment Playbook

**Version:** 1.0.0
**Module:** root-infrastructure
**Phase:** Production

This document provides comprehensive instructions for deploying, managing, and recovering the NeuroMorphicToolkit (NMTK) in production environments.

---

## 1. Introduction

NeuroMorphicToolkit (NMTK) is a distributed system consisting of a Flutter-based desktop launcher and multiple micro-service backend modules. Production deployment varies depending on whether the toolkit is used as a cloud-hosted suite or distributed as standalone desktop applications.

---

## 2. Deployment Strategies

### 2.1 Bare Metal / Virtual Machines (VMs)

The primary method for server-side deployment is using Docker Compose.

#### Prerequisites
- Docker 24.0+
- Docker Compose v2.20+

#### Deployment Steps
1. **Clone the repository with submodules**:
   ```bash
   git clone --recurse-submodules https://github.com/Completed-Spoon-6/NeuroMorphicToolKit.git
   cd NeuroMorphicToolKit
   ```

2. **Configure Environment**:
   Edit the `.env` file to set production ports and secrets. Ensure `PYTHONUNBUFFERED=1` is set for logging.

3. **Launch Services**:
   Use profiles to start the required subset of services.
   ```bash
   # Core services (neurocnl, neurosim, neurochip)
   docker compose up -d --build

   # All services
   docker compose --profile full up -d --build

   # Physics-enabled services
   docker compose --profile physics up -d --build
   ```

#### Persistence and Restarts
All services in `docker-compose.yml` are configured with `restart: unless-stopped`. This ensures they automatically restart after a crash or system reboot.

### 2.2 Cloud (Container-based PaaS)

For managed container platforms like **Google Cloud Run**, **Railway**, or **AWS ECS**, each module can be deployed as an independent service.

#### General Pattern
1. **Build the module image**:
   The Dockerfile context for all modules is the repository root.
   ```bash
   docker build -t nmtk-neurocnl -f neurocnl/backend/Dockerfile .
   ```

2. **Deploy to Cloud Run**:
   ```bash
   gcloud run deploy neurocnl --image gcr.io/your-project/nmtk-neurocnl --platform managed
   ```

#### Configuration
- **CORS_ORIGINS**: Set this to the public URL of your frontend to allow cross-origin requests.
- **Internal Service Discovery**: When deploying modules separately in the cloud, you must update the service discovery URLs for `Neurohub`.
  - `NEUROCNL_URL`
  - `NEUROSIM_URL`
  - `NEUROCHIP_URL`
  - `NEUROBENCH_URL`
  - `NEUROSENSE_URL`
- **Secrets Management**: Use your cloud provider's secrets manager for sensitive environment variables.

### 2.3 Desktop Production Artifacts

For end-user distribution, use the platform-specific installer scripts in `nmtk/installer/`.

- **macOS**: `nmtk/installer/macos/build-standalone.sh --dmg`
- **Linux**: `nmtk/installer/linux/appimage.sh`
- **Windows**: `nmtk/installer/windows/build-standalone.ps1` (followed by `setup.iss` in Inno Setup)

---

## 3. Backup and Restore

### 3.1 SQLite Database (`neurohub.db`)

`Neurohub` stores orchestration state in a SQLite database.

#### Backup
```bash
# Direct file copy
cp Neurohub/neurohub/neurohub.db /path/to/backups/neurohub_$(date +%F).db

# Safe backup using sqlite3 (if installed on host)
sqlite3 Neurohub/neurohub/neurohub.db ".backup '/path/to/backups/neurohub_$(date +%F).db'"
```

#### Restore
```bash
# Stop the neurohub service
docker compose stop neurohub

# Replace the database file
cp /path/to/backups/neurohub_latest.db Neurohub/neurohub/neurohub.db

# Restart the service
docker compose start neurohub
```

### 3.2 Docker Volumes

If persistent volumes are used (e.g., for model storage in Neurohub), back them up using a temporary container:

```bash
docker run --rm -v neurohub_data:/volume -v $(pwd):/backup alpine \
  tar -czf /backup/neurohub_data_backup.tar.gz -C /volume .
```

### 3.3 Recovery Verification
After restoring a backup:
1. Verify database integrity: `sqlite3 neurohub.db "PRAGMA integrity_check;"`.
2. Check the logs for `Neurohub` for startup errors related to database connection or migrations.

---

## 4. Scaling Considerations

### 4.1 Vertical Scaling
Modules like **neurocnl** and **neurosim** perform intensive SNN simulations on the CPU.
- **Recommendation**: Allocate at least 2 vCPUs and 4GB RAM per active simulation service in production.

### 4.2 Horizontal Scaling
The backends are largely stateless (except for `Neurohub`).
- **Stateless Modules**: Multiple instances can be run behind a load balancer (Nginx/HAProxy).
- **Worker Counts**: Increase uvicorn workers for higher concurrency:
  ```bash
  # In Dockerfile or environment
  CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "4"]
  ```

### 4.3 Database Scaling
As traffic grows, migration from SQLite to a dedicated database (e.g., PostgreSQL) for `Neurohub` is recommended. This allows for:
- Connection pooling.
- High Availability (HA) configurations.
- Independent database backups.

---

## 5. Disaster Recovery Plan

### 5.1 Recovery Steps
In the event of total infrastructure failure:
1. **Provision a new host** (Bare metal or VM).
2. **Clone the repository**: `git clone --recurse-submodules ...`
3. **Restore Data**: Copy the latest `neurohub.db` backup to the appropriate directory.
4. **Deploy**: Run `docker compose --profile full up -d --build`.
5. **Verify Health**:
   ```bash
   bash scripts/validate_docker_compose.sh
   bash scripts/demo_smoke_test.sh
   ```

### 5.2 RPO/RTO
- **Recovery Point Objective (RPO)**: 24 hours (assuming daily database backups).
- **Recovery Time Objective (RTO)**: < 1 hour (automated deployment via Docker Compose).

### 5.3 Communication Protocol
In case of a production outage:
1. Notify stakeholders (Internal Team, User Support).
2. Update the status page or project dashboard.
3. Once recovered, conduct a post-mortem to identify and mitigate the root cause.

---

## 6. Operational Runbook

### 6.1 Port Conflicts
NMTK uses the `8000-8006` range.
- **Issue**: "Bind for 0.0.0.0:8000 failed: port is already allocated."
- **Solution**: Check running processes with `lsof -i :8000` or change port mappings in `.env`.

### 6.2 Health Check Failures
- **Issue**: Container is "unhealthy" in `docker ps`.
- **Check**: `docker compose logs <service_name>`.
- **Common Cause**: Submodules not properly initialized. Run `git submodule update --init --recursive`.

### 6.3 Docker Resource Exhaustion
- **Issue**: Containers exit with code 137 (OOMKilled).
- **Solution**: Increase memory limits in `docker-compose.yml` or the host machine RAM.

### 6.4 Slow Response Times (Latency)
- **Check**: Backend logs for slow database queries or simulation durations.
- **Tools**: `htop` to check system load, `iotop` for disk I/O.
- **Action**: Check if CPU is pegged at 100%. Consider scaling the affected service vertically or adding more uvicorn workers.

### 6.5 Submodule Version Mismatch
- **Issue**: "Module not found" or "AttributeError" in a backend.
- **Cause**: Repository pulled without updated submodules.
- **Action**: `git submodule update --init --recursive` from the root.
