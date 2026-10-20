import sys
import os
import time

url = sys.argv[1] if len(sys.argv) > 1 else ""
output_file = sys.argv[2] if len(sys.argv) > 2 else ""

if not url:
    print("Usage: python stealth_fetch.py <URL> [output_file]")
    sys.exit(1)

html_content = ""
success = False

# Strategy 1: Try curl_cffi browser TLS impersonation
try:
    from curl_cffi import requests
    resp = requests.get(url, impersonate="chrome120", timeout=15, verify=False)
    if resp.status_code == 200 and "Just a moment..." not in resp.text and len(resp.content) > 1000:
        html_content = resp.text
        success = True
        print(f"[STEALTH_FETCH][curl_cffi] Success! Downloaded {len(html_content)} bytes", file=sys.stderr)
    else:
        print(f"[STEALTH_FETCH][curl_cffi] Status {resp.status_code}, length {len(resp.content)}. Trying Playwright...", file=sys.stderr)
except Exception as e:
    print(f"[STEALTH_FETCH][curl_cffi] Error: {e}. Trying Playwright...", file=sys.stderr)

# Strategy 2: If Strategy 1 didn't produce full page, try Playwright headless browser
if not success:
    try:
        from playwright.sync_api import sync_playwright
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True)
            context = browser.new_context(
                user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
                viewport={'width': 1280, 'height': 800}
            )
            page = context.new_page()
            page.goto(url, wait_until="domcontentloaded", timeout=30000)
            time.sleep(3) # allow JS execution & Cloudflare redirect
            html_content = page.content()
            browser.close()
            if len(html_content) > 1000:
                success = True
                print(f"[STEALTH_FETCH][playwright] Success! Downloaded {len(html_content)} bytes", file=sys.stderr)
    except Exception as e:
        print(f"[STEALTH_FETCH][playwright] Error: {e}", file=sys.stderr)

if output_file and html_content:
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write(html_content)
    print(f"[STEALTH_FETCH] Saved HTML to {output_file}", file=sys.stderr)
elif html_content:
    sys.stdout.buffer.write(html_content.encode('utf-8', errors='ignore'))
else:
    print("[STEALTH_FETCH] Failed to fetch page content.", file=sys.stderr)
    sys.exit(1)
