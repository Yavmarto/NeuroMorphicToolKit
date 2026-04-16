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

print(f"Fetching tasks from {SERVER_URL}/api/tasks...")
try:
    res = requests.get(f"{SERVER_URL}/api/tasks", headers=HEADERS)
    print(f"Status: {res.status_code}")
    print(json.dumps(res.json(), indent=2))
except Exception as e:
    print(f"Error fetching tasks: {e}")

print(f"\nFetching agents from {SERVER_URL}/api/agents...")
try:
    res = requests.get(f"{SERVER_URL}/api/agents", headers=HEADERS)
    print(f"Status: {res.status_code}")
    print(json.dumps(res.json(), indent=2))
except Exception as e:
    print(f"Error fetching agents: {e}")
