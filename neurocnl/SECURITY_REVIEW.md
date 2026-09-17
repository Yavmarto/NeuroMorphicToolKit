# Security & Code Review Report

## 1. High-Level Summary
Overall, the `neurocnl` project is well-structured, utilizing FastAPI effectively for REST routing and isolating pipeline logic within its core components. The application leverages modern typing and tools. However, several critical and medium severity issues were discovered, notably relating to security configurations (CORS, API key validation) and minor information leaks. Implementing the fixes detailed below significantly hardens the server logic against common attacks while making the architecture more resilient.

## 2. Detailed Findings

### 🔴 Critical: Security Flaw in CORS Configuration
**File/Location:** `backend/app/main.py`
**The Issue:** The middleware was configured with `allow_origins=["*"]` while strictly forcing `allow_credentials=True`. This is typically disallowed in Starlette/FastAPI but if the backend dynamically accepts a wildcard it essentially creates a critical risk allowing cross-origin requests with credentials.
**Actionable Fix:** Prevent `allow_credentials=True` when `allow_origins` includes `"*"`.
**Code Example:**
*Before:*
```python
cors_allowed_origins = [
    origin.strip() for origin in os.getenv("CORS_ALLOWED_ORIGINS", "*").split(",") if origin.strip()
]
app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
```

*After:*
```python
cors_allowed_origins = [
    origin.strip() for origin in os.getenv("CORS_ALLOWED_ORIGINS", "*").split(",") if origin.strip()
]

# Starlette prevents allow_credentials=True if allow_origins=["*"]
allow_credentials = "*" not in cors_allowed_origins

app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_allowed_origins,
    allow_credentials=allow_credentials,
    allow_methods=["*"],
    allow_headers=["*"],
)
```

### 🟠 High: Timing Attack Vulnerability in API Key Validation
**File/Location:** `backend/app/middleware/auth.py`
**The Issue:** The API key verification relies on a simple string equality check (`api_key != expected_key`). Simple comparisons evaluate character by character, exiting upon the first mismatch. This can be exploited using timing attacks to infer the API key.
**Actionable Fix:** Use a constant-time comparison mechanism (`hmac.compare_digest`).
**Code Example:**
*Before:*
```python
        api_key = request.headers.get("X-API-Key")
        if api_key != expected_key:
            return JSONResponse(...)
```

*After:*
```python
import hmac

api_key = request.headers.get("X-API-Key")
if not api_key or not hmac.compare_digest(api_key.encode(), expected_key.encode()):
    return JSONResponse(...)
```

### 🟡 Medium: Information Leak in Health Check Endpoint
**File/Location:** `backend/app/main.py` -> `health_check`
**The Issue:** The server's health status endpoint returns details about the underlying system's total, used, and free disk space. Exposing low-level system metrics publicly could provide attackers with insights about the deployment environment.
**Actionable Fix:** Remove disk space reporting from the unauthenticated `/health` endpoint.
**Code Example:**
*Before:*
```python
import shutil

total, used, free = shutil.disk_usage("/")
result["disk"] = {
    "total_gb": round(total / (2**30), 2),
    "used_gb": round(used / (2**30), 2),
    "free_gb": round(free / (2**30), 2),
}
```

*After:*
```python
    # Disk usage logic entirely removed to avoid information leakage.
```
