import pytest

pytest.importorskip("playwright")
from playwright.sync_api import Page


def test_screenshot(page: Page):
    page.goto("http://localhost:8000")
    # Set the server URL in local storage
    page.evaluate("window.localStorage.setItem('server_url', 'http://localhost:8000')")
    # Reload to apply
    page.goto("http://localhost:8000")
    page.wait_for_timeout(5000)
    page.screenshot(path="debug_studio_ls.png")
