# Create Root docker-compose.yml for Full Suite Startup

**Priority:** Critical — POC Blocker  
**Type:** Infrastructure  
**Tier:** 1 (Must Do)  
**Estimated Effort:** 1 day  

## Description

Each module has its own Dockerfile and docker-compose.yml, but there is no root-level orchestration file to bring up the entire suite with a single command. This is needed for both development convenience and POC demonstration.

## Requirements

1. **Root `docker-compose.yml`:**
   - Define services for each backend module using their existing Dockerfiles
   - Assign the canonical ports:
     | Service | Port | Build Context |
     |---------|------|---------------|
     | neurocnl | 8000 | `./neurocnl` |
     | neurosim | 8001 | `./Neurosim` |
     | neurochip | 8002 | `./Neurochip` |
     | neurobench | 8003 | `./Neurobench` |
     | neurosense | 8004 | `./Neurosense` |
     | neurohub | 8005 | `./Neurohub` |
   - Use a shared network so modules can discover each other by service name
   - Add health checks using each service's `/health` endpoint
   - Add a `depends_on` chain where appropriate (neurohub depends on others)

2. **Profiles for Optional Services:**
   - `--profile physics` to include MuJoCo-enabled services
   - `--profile full` to include all services
   - Default profile starts core services only (neurocnl, neurosim, neurochip)

3. **Environment Variables:**
   - Externalize port assignments via `.env` file
   - Pass `API_BASE_URL` to frontends if needed

## Acceptance Criteria

- `docker compose up` starts at least neurocnl, neurosim, and neurochip
- `docker compose --profile full up` starts all six backends
- All services are healthy within 60 seconds
- Services can communicate via Docker network DNS names

## Files Affected

```
docker-compose.yml                ← new (root level)
.env                              ← new (port definitions)
```
