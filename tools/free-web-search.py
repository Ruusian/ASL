#!/usr/bin/env python3
"""
ASL & OpenClaude Keyless Free Web Search Engine
Fetches live web search results without requiring third-party API keys or authentication.
"""

import sys
import json
import urllib.request
import urllib.parse
import re
from html import unescape

def search_ddg_html(query, max_results=5):
    url = "https://html.duckduckgo.com/html/"
    data = urllib.parse.urlencode({"q": query}).encode("utf-8")
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Content-Type": "application/x-www-form-urlencoded"
    }

    req = urllib.request.Request(url, data=data, headers=headers)
    results = []

    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            html_text = resp.read().decode("utf-8", errors="ignore")
            # Find result blocks
            matches = re.findall(
                r'<a class="result__snippet"[^>]*href="([^"]+)"[^>]*>(.*?)</a>',
                html_text,
                re.DOTALL
            )

            if not matches:
                # Alternative regex pattern for DDG HTML layout
                links = re.findall(r'<a class="result__url" href="([^"]+)".*?<a class="result__snippet"[^>]*>(.*?)</a>', html_text, re.DOTALL)
                for href, snippet in links:
                    matches.append((href, snippet))

            for raw_url, raw_snippet in matches[:max_results]:
                clean_snippet = unescape(re.sub(r"<[^>]+>", "", raw_snippet)).strip()
                # Parse actual target URL from uddg param
                m_url = re.search(r"uddg=(https?%3A%2F%2F[^&]+)", raw_url)
                final_url = urllib.parse.unquote(m_url.group(1)) if m_url else raw_url

                # Extract title if possible
                title_match = re.search(r'<a class="result__a"[^>]*>(.*?)</a>', html_text)
                title = unescape(re.sub(r"<[^>]+>", "", title_match.group(1))).strip() if title_match else final_url

                results.append({
                    "title": title,
                    "url": final_url,
                    "snippet": clean_snippet
                })

    except Exception as e:
        sys.stderr.write(f"Web Search Error: {e}\n")

    return results

def main():
    if len(sys.argv) < 2:
        print("Usage: free-web-search <query>")
        sys.exit(1)

    query = " ".join(sys.argv[1:])
    res = search_ddg_html(query)
    if res:
        print(json.dumps(res, indent=2))
    else:
        print(json.dumps([{"error": "No results found or rate limited"}]))

if __name__ == "__main__":
    main()
