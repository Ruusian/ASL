#!/usr/bin/env python3
"""
ASL & OpenClaude Native Multi-Engine Web Search & Crawler
Prioritizes keyless search & web scraping (DDG HTML, DDG Lite, Mojeek) to conserve Brave API usage.
Uses Brave API strictly as a final fallback when keyless engines return no results.
"""

import sys
import os
import json
import urllib.request
import urllib.parse
import re
from html import unescape

def search_ddg_html(query, max_results=5):
    url = "https://html.duckduckgo.com/html/"
    data = urllib.parse.urlencode({"q": query}).encode("utf-8")
    headers = {
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.5",
        "Content-Type": "application/x-www-form-urlencoded"
    }

    req = urllib.request.Request(url, data=data, headers=headers)
    results = []

    try:
        with urllib.request.urlopen(req, timeout=8) as resp:
            html_text = resp.read().decode("utf-8", errors="ignore")

            items = re.findall(
                r'<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>([\s\S]*?)</a>[\s\S]*?<a[^>]*class="result__snippet"[^>]*>([\s\S]*?)</a>',
                html_text
            )

            if not items:
                items = re.findall(
                    r'<a[^>]*class="result__snippet"[^>]*href="([^"]+)"[^>]*>([\s\S]*?)</a>',
                    html_text
                )
                for raw_url, raw_snippet in items[:max_results]:
                    clean_snippet = unescape(re.sub(r"<[^>]+>", "", raw_snippet)).strip()
                    m_url = re.search(r"uddg=(https?%3A%2F%2F[^&]+)", raw_url)
                    final_url = urllib.parse.unquote(m_url.group(1)) if m_url else raw_url
                    results.append({
                        "title": final_url,
                        "url": final_url,
                        "snippet": clean_snippet
                    })
                return results

            for raw_url, raw_title, raw_snippet in items[:max_results]:
                clean_title = unescape(re.sub(r"<[^>]+>", "", raw_title)).strip()
                clean_snippet = unescape(re.sub(r"<[^>]+>", "", raw_snippet)).strip()
                m_url = re.search(r"uddg=(https?%3A%2F%2F[^&]+)", raw_url)
                final_url = urllib.parse.unquote(m_url.group(1)) if m_url else raw_url

                results.append({
                    "title": clean_title,
                    "url": final_url,
                    "snippet": clean_snippet
                })

    except Exception as e:
        sys.stderr.write(f"DDG HTML Error: {e}\n")

    return results

def search_ddg_lite(query, max_results=5):
    url = "https://lite.duckduckgo.com/lite/"
    data = urllib.parse.urlencode({"q": query}).encode("utf-8")
    headers = {
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0",
        "Content-Type": "application/x-www-form-urlencoded"
    }

    req = urllib.request.Request(url, data=data, headers=headers)
    results = []

    try:
        with urllib.request.urlopen(req, timeout=8) as resp:
            html_text = resp.read().decode("utf-8", errors="ignore")
            rows = re.findall(r'<a[^>]+href="([^"]+)"[^>]*class="result-snippet"[^>]*>([\s\S]*?)</a>', html_text)
            for raw_url, raw_snippet in rows[:max_results]:
                clean_snippet = unescape(re.sub(r"<[^>]+>", "", raw_snippet)).strip()
                m_url = re.search(r"uddg=(https?%3A%2F%2F[^&]+)", raw_url)
                final_url = urllib.parse.unquote(m_url.group(1)) if m_url else raw_url
                results.append({
                    "title": final_url,
                    "url": final_url,
                    "snippet": clean_snippet
                })
    except Exception as e:
        sys.stderr.write(f"DDG Lite Error: {e}\n")

    return results

def search_mojeek(query, max_results=5):
    url = f"https://www.mojeek.com/search?q={urllib.parse.quote(query)}"
    headers = {
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0"
    }
    req = urllib.request.Request(url, headers=headers)
    results = []
    try:
        with urllib.request.urlopen(req, timeout=8) as resp:
            html_text = resp.read().decode("utf-8", errors="ignore")
            items = re.findall(r'<a[^>]+class="title"[^>]+href="([^"]+)"[^>]*>([\s\S]*?)</a>[\s\S]*?<p[^>]+class="s"[^>]*>([\s\S]*?)</p>', html_text)
            for raw_url, raw_title, raw_snippet in items[:max_results]:
                clean_title = unescape(re.sub(r"<[^>]+>", "", raw_title)).strip()
                clean_snippet = unescape(re.sub(r"<[^>]+>", "", raw_snippet)).strip()
                results.append({
                    "title": clean_title,
                    "url": raw_url,
                    "snippet": clean_snippet
                })
    except Exception as e:
        sys.stderr.write(f"Mojeek Error: {e}\n")
    return results

def search_brave(query, api_key, max_results=5):
    url = f"https://api.search.brave.com/res/v1/web/search?q={urllib.parse.quote(query)}&count={max_results}"
    req = urllib.request.Request(url, headers={
        "Accept": "application/json",
        "X-Subscription-Token": api_key
    })
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            results = []
            web_results = data.get("web", {}).get("results", [])
            for r in web_results:
                results.append({
                    "title": r.get("title"),
                    "url": r.get("url"),
                    "snippet": r.get("description", "")
                })
            if results:
                return results
    except Exception as e:
        sys.stderr.write(f"Brave Search API Notice: {e}\n")
    return None

def search_bing(query, max_results=5):
    url = f"https://www.bing.com/search?q={urllib.parse.quote(query)}"
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36",
        "Accept-Language": "en-US,en;q=0.9"
    }
    req = urllib.request.Request(url, headers=headers)
    results = []
    try:
        with urllib.request.urlopen(req, timeout=8) as resp:
            html_text = resp.read().decode("utf-8", errors="ignore")
            items = re.findall(r'<h2[^>]*><a[^>]+href="([^"]+)"[^>]*>([\s\S]*?)</a></h2>[\s\S]*?<p[^>]*>([\s\S]*?)</p>', html_text)
            for raw_url, raw_title, raw_snippet in items[:max_results]:
                clean_title = unescape(re.sub(r"<[^>]+>", "", raw_title)).strip()
                clean_snippet = unescape(re.sub(r"<[^>]+>", "", raw_snippet)).strip()
                final_url = raw_url
                m_u = re.search(r"u=a1([A-Za-z0-9_-]+)", raw_url)
                if m_u:
                    try:
                        b64_str = m_u.group(1)
                        b64_str += "=" * (-len(b64_str) % 4)
                        import base64
                        final_url = base64.b64decode(b64_str).decode("utf-8", errors="ignore")
                    except Exception:
                        pass
                results.append({
                    "title": clean_title,
                    "url": final_url,
                    "snippet": clean_snippet
                })
    except Exception as e:
        sys.stderr.write(f"Bing Error: {e}\n")
    return results

def main():
    if len(sys.argv) < 2:
        print("Usage: free-web-search <query>")
        sys.exit(1)

    query = " ".join(sys.argv[1:])

    # 1. Try Keyless Search Engines First (Conserves Brave API limit)
    res = search_ddg_html(query)
    if not res:
        res = search_ddg_lite(query)
    if not res:
        res = search_mojeek(query)
    if not res:
        res = search_bing(query)

    # 2. Final Fallback to Brave API if keyless engines return empty
    if not res:
        api_key = os.environ.get("BRAVE_API_KEY")
        key_path = os.path.expanduser("~/.asl/brave_key")
        if not api_key and os.path.exists(key_path):
            try:
                with open(key_path, "r") as f:
                    api_key = f.read().strip()
            except Exception:
                pass
        if api_key:
            res = search_brave(query, api_key)

    if res:
        print(json.dumps(res, indent=2))
    else:
        print(json.dumps([{"error": "No web results found across keyless & fallback engines"}]))

if __name__ == "__main__":
    main()
