import os
import requests
from collections import defaultdict
import sys
from dotenv import load_dotenv

# Load environment variables from .env if it exists
load_dotenv()

# Configuration
API_KEY = os.getenv("JULES_API_KEY")
if not API_KEY:
    print(
        "Error: Please set the JULES_API_KEY environment variable in a .env file or export it."
    )
    sys.exit(1)

BASE_URL = "https://jules.googleapis.com/v1alpha"
HEADERS = {"x-goog-api-key": API_KEY}


def get_all_sessions():
    """Fetches all sessions, handling pagination."""
    sessions = []
    page_token = None

    print("Fetching sessions...")
    while True:
        params = {"pageSize": 100}
        if page_token:
            params["pageToken"] = page_token

        response = requests.get(f"{BASE_URL}/sessions", headers=HEADERS, params=params)
        response.raise_for_status()
        data = response.json()

        sessions.extend(data.get("sessions", []))

        page_token = data.get("nextPageToken")
        if not page_token:
            break

    return sessions


def main():
    try:
        sessions = get_all_sessions()
    except requests.exceptions.RequestException as e:
        print(f"Failed to fetch sessions: {e}")
        return

    if not sessions:
        print("No sessions found.")
        return

    # 1. Sort sessions chronologically (oldest first)
    sessions.sort(key=lambda x: x.get("createTime", ""))

    # 2. Group sessions by Date (YYYY-MM-DD)
    grouped_sessions = defaultdict(list)
    for session in sessions:
        create_time = session.get("createTime", "")
        date_str = create_time.split("T")[0] if create_time else "Unknown Date"
        grouped_sessions[date_str].append(session)

    print("\n--- Sessions Grouped by Date (Oldest First) ---")
    for date_str, sess_list in grouped_sessions.items():
        print(f"\n📅 {date_str}")
        for s in sess_list:
            state = s.get("state", "UNKNOWN")
            title = s.get("title", "Untitled")
            name = s.get("name")
            print(f"  - [{state}] {title} ({name})")

    # 3. Prompt for batch deletion
    total_sessions = len(sessions)
    print(f"\nTotal sessions found: {total_sessions}")

    batch_input = (
        input(
            "How many of the oldest sessions would you like to delete? (Enter a number, 'all', or '0' to cancel): "
        )
        .strip()
        .lower()
    )

    if batch_input in ["0", "", "none"]:
        print("Deletion canceled. No sessions were removed.")
        return

    if batch_input == "all":
        limit = total_sessions
    else:
        try:
            limit = int(batch_input)
            if limit < 0:
                print("Please enter a positive number.")
                return
            if limit > total_sessions:
                limit = total_sessions
        except ValueError:
            print("Invalid input. Deletion canceled.")
            return

    # 4. Slice the list to get your batch
    sessions_to_delete = sessions[:limit]

    confirm = input(
        f"Are you sure you want to permanently delete the oldest {limit} session(s)? (y/N): "
    )

    if confirm.lower() == "y":
        print(f"\nDeleting {limit} sessions...")
        success_count = 0

        for session in sessions_to_delete:
            name = session.get("name")
            if not name:
                continue

            delete_url = f"{BASE_URL}/{name}"

            try:
                del_resp = requests.delete(delete_url, headers=HEADERS)
                del_resp.raise_for_status()
                print(f"  ✅ Deleted {name}")
                success_count += 1
            except requests.exceptions.RequestException as e:
                print(f"  ❌ Failed to delete {name}: {e}")

        print(
            f"\nCleanup complete. Successfully deleted {success_count} out of {limit} attempted."
        )
    else:
        print("Deletion canceled. No sessions were removed.")


if __name__ == "__main__":
    main()
