from pathlib import Path

try:
    from playwright.sync_api import sync_playwright  # type: ignore[import-not-found]
except ImportError:
    sync_playwright = None  # type: ignore[assignment]


def run_cuj(page):
    print("Navigating to app...")
    page.goto("http://localhost:8004")
    page.wait_for_timeout(5000)

    # Take screenshot of initial state
    page.screenshot(path="/home/jules/verification/screenshots/initial_load.png")

    print("Refresh devices...")
    page.get_by_role("button").first.click()  # Refresh button
    page.wait_for_timeout(2000)

    print("Connecting to Synthetic Board...")
    # Click Connect
    connect_button = page.get_by_text("Connect")
    if connect_button.count() > 0:
        connect_button.first.click()
    else:
        # Fallback to coordinate from integration_test.py
        page.mouse.click(912, 210)

    page.wait_for_timeout(5000)
    page.screenshot(path="/home/jules/verification/screenshots/connected.png")

    print("Opening Troubleshooting Guide...")
    # It might be in the Signal Quality card
    troubleshoot_button = page.get_by_text("Troubleshooting")
    if troubleshoot_button.count() > 0:
        troubleshoot_button.first.click()
        page.wait_for_timeout(2000)
        page.screenshot(path="/home/jules/verification/screenshots/troubleshooting_dialog.png")
    else:
        print("Troubleshooting button not found via text")

    page.wait_for_timeout(1000)


if __name__ == "__main__":
    Path("/home/jules/verification/screenshots").mkdir(parents=True, exist_ok=True)
    Path("/home/jules/verification/videos").mkdir(parents=True, exist_ok=True)
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        context = browser.new_context(record_video_dir="/home/jules/verification/videos")
        page = context.new_page()
        try:
            run_cuj(page)
        finally:
            context.close()
            browser.close()
