import asyncio

try:
    from playwright.async_api import async_playwright  # type: ignore[import-not-found]
except ImportError:
    async_playwright = None  # type: ignore[assignment]


async def run_integration_test() -> None:
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        # Create a persistent context to handle potential websocket/storage needs
        context = await browser.new_context(viewport={"width": 1280, "height": 800})
        page = await context.new_page()

        # Log console messages
        page.on("console", lambda msg: print(f"CONSOLE: {msg.text}"))
        page.on("pageerror", lambda err: print(f"PAGE ERROR: {err}"))

        print("Navigating to app...")
        await page.goto("http://localhost:8080", timeout=60000)

        print("Waiting for Flutter to initialize...")
        await asyncio.sleep(20)
        await page.screenshot(path="screenshot_01_initial.png")

        print("Connecting to Synthetic Board via coordinate click...")
        # Try clicking exactly on the 'Connect' button for the first item
        await page.mouse.click(912, 210)

        await asyncio.sleep(5)  # Wait for connection
        await page.screenshot(path="screenshot_02_connected.png")

        print("Starting Recording via coordinate click...")
        # Scroll more to be safe
        await page.mouse.wheel(0, 1000)
        await asyncio.sleep(2)
        await page.screenshot(path="screenshot_03_scrolled.png")

        # Click Start Recording
        # Assume it's visible now.
        # Let's try to click multiple times around the suspected area
        await page.mouse.click(150, 680)
        await page.mouse.click(150, 700)

        await asyncio.sleep(5)  # Let recording start
        await page.screenshot(path="screenshot_04_recording_start.png")

        print("Inserting Marker...")
        # Marker text field
        await page.mouse.click(250, 770)
        await asyncio.sleep(1)
        await page.keyboard.type("test_marker")
        await asyncio.sleep(1)
        # Add Marker button
        await page.mouse.click(550, 770)

        await asyncio.sleep(2)
        await page.screenshot(path="screenshot_05_marker.png")

        print("Waiting for quality data...")
        await asyncio.sleep(10)
        await page.screenshot(path="screenshot_06_quality.png")

        print("Stopping Recording...")
        # Stop Recording button
        await page.mouse.click(150, 680)

        await asyncio.sleep(3)
        await page.screenshot(path="screenshot_07_stopped.png")

        print("Integration test finished.")
        await browser.close()


if __name__ == "__main__":
    asyncio.run(run_integration_test())
