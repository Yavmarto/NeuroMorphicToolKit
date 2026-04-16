import time
import requests
import subprocess
import uuid
import os
import sys
import shlex
from dotenv import load_dotenv

# --- ENVIRONMENT CONFIGURATION ---
# Load .env from the script's directory
script_dir = os.path.dirname(os.path.abspath(__file__))
env_path = os.path.join(script_dir, ".env")
load_dotenv(env_path)

SERVER_URL = os.getenv("MISSION_CONTROL_SERVER_URL")
API_KEY = os.getenv("MISSION_CONTROL_API_KEY")

if not SERVER_URL or not API_KEY:
    print("❌ Error: MISSION_CONTROL_SERVER_URL or MISSION_CONTROL_API_KEY not found in scripts/.env")
    print("Please check your .env file in the 'scripts' directory.")
    sys.exit(1)

# Easily add or remove agents here!
AGENTS_CONFIG = [
    {
        "agent_id": "3",
        "agent_name": "claude-code-worker",
        "tool_name": "claude-code",
        "role": "coder",
        "description_prefix": "Execute this task automatically: ",
        # How this specific agent executes tasks
        "command_template": 'claude {description}',
        "connection_id": f"cli-daemon-claude-{uuid.uuid4().hex[:8]}"
    },
    {
        "agent_id": "4",
        "agent_name": "codex-worker",
        "tool_name": "codex",
        "role": "coder",
        "description_prefix": "",
        # A different tool requires a different CLI syntax
        "command_template": 'codex exec --full-auto {description}',
        "connection_id": f"cli-daemon-codex-{uuid.uuid4().hex[:8]}"
    }
]

HEADERS = {
    "Content-Type": "application/json",
    "x-api-key": API_KEY
}

def register_agent(agent):
    """Registers the agent with the Mission Control server."""
    print(f"🔌 Registering {agent['agent_name']}...")
    try:
        res = requests.post(f"{SERVER_URL}/api/connect", headers=HEADERS, json={
            "tool_name": agent["tool_name"],
            "agent_name": agent["agent_name"],
            "agent_role": agent["role"]
        }, timeout=10)
        res.raise_for_status()
        print(f"✅ Registered {agent['agent_name']}.")
    except Exception as e:
        print(f"❌ Failed to register {agent['agent_name']}: {e}")

def process_agent_tasks(agent):
    """Polls for tasks and executes them for a specific agent."""
    headers_with_conn = {**HEADERS, "x-connection-id": agent["connection_id"]}
    
    try:
        # 1. Heartbeat to check in with the server
        res = requests.post(
            f"{SERVER_URL}/api/agents/{agent['agent_id']}/heartbeat", 
            headers=headers_with_conn,
            timeout=10
        )
        if res.status_code != 200:
            return
            
        # 2. Fetch assigned tasks actively
        task_res = requests.get(
            f"{SERVER_URL}/api/tasks?assigned_to={agent['agent_name']}&status=inbox",
            headers=HEADERS,
            timeout=10
        )
        if task_res.status_code != 200:
            return
            
        tasks = task_res.json().get("tasks", [])

        for task in tasks:
            task_id = task.get('id')
            print(f"\n⚡ [{agent['agent_name']}] Auto-dispatching Task: {task_id}")
            
            # 3. Mark as in_progress immediately
            try:
                requests.put(f"{SERVER_URL}/api/tasks/{task_id}", headers=HEADERS, json={
                    "status": "in_progress",
                    "assigned_to": agent["agent_name"]
                }, timeout=10)
                print(f"🔄 Task {task_id} marked as 'in_progress'")
            except Exception as e:
                print(f"⚠️ Failed to mark task {task_id} as in_progress: {e}")
            
            # 4. Format the CLI command
            # Note: Properly quote to prevent shell expansions and injections
            prefix = agent.get('description_prefix', '')
            raw_description = prefix + task.get('description', '')
            safe_description = shlex.quote(raw_description)
            command = agent["command_template"].format(description=safe_description)
            
            # 5. Execute the CLI tool locally and stream output
            print(f"🏃 Running: {command}")
            process = subprocess.Popen(
                command, 
                shell=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1
            )
            
            output_lines = []
            for line in iter(process.stdout.readline, ''):
                sys.stdout.write(line)
                sys.stdout.flush()
                output_lines.append(line)
                
            process.stdout.close()
            process.wait()
            
            result_output = "".join(output_lines)
            if process.returncode != 0:
                result_output += f"\nProcess exited with code {process.returncode}"
            
            # 6. Report the result back to Mission Control
            try:
                requests.put(f"{SERVER_URL}/api/tasks/{task_id}", headers=HEADERS, json={
                    "status": "done", 
                    "result": result_output
                }, timeout=10)
                print(f"\n✅ [{agent['agent_name']}] Task {task_id} completed and pushed to server.")
            except Exception as e:
                print(f"\n❌ [{agent['agent_name']}] Failed to push task {task_id} result to server: {e}")
            
    except Exception as e:
        print(f"⚠️ Error processing {agent['agent_name']}: {e}")

def main():
    print("🚀 Starting Multi-Agent Mission Control Worker...")
    
    # Register all agents on startup
    for agent in AGENTS_CONFIG:
        register_agent(agent)
        
    print(f"\n📡 All agents registered. Listening for tasks from {SERVER_URL}...")
    print(" (Polling every 10 seconds. Press Ctrl+C to stop.)\n")

    # Infinite polling loop
    while True:
        for agent in AGENTS_CONFIG:
            process_agent_tasks(agent)
            
        # Subtle heartbeat to show we're still alive
        sys.stdout.write(".")
        sys.stdout.flush()
        
        # Wait 10 seconds before polling the board again
        time.sleep(10) 

if __name__ == "__main__":
    main()
