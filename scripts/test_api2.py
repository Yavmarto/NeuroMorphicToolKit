import requests
import json
import os
from dotenv import load_dotenv

load_dotenv()
SERVER_URL = os.getenv("MISSION_CONTROL_SERVER_URL")
API_KEY = os.getenv("MISSION_CONTROL_API_KEY")

HEADERS = {
    "Content-Type": "application/json",
    "x-api-key": API_KEY
}

# Test tasks for specific agent
res = requests.get(f"{SERVER_URL}/api/tasks?assigned_to=claude-code-worker", headers=HEADERS)
print("Querying tasks by assigned_to:")
try:
    print(json.dumps(res.json(), indent=2))
except Exception:
    print(res.text)

# Also test heartbeat for claude-code-worker
agent_id = "3"
conn_id = "test-conn-id"
headers_conn = {**HEADERS, "x-connection-id": conn_id}
print("\nHeartbeat:")
res = requests.post(f"{SERVER_URL}/api/agents/{agent_id}/heartbeat", headers=headers_conn)
try:
    print(json.dumps(res.json(), indent=2))
except Exception:
    print(res.text)
