#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import time

REPO = "Ruusian/ASL"

def get_token():
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token:
        return token
    # Search common credential files
    paths = [
        os.path.expanduser("~/.config/gh/hosts.yml"),
        os.path.expanduser("~/.git-credentials"),
        "/data/local/tmp/chrootDebian/root/.config/gh/hosts.yml",
        "/data/local/tmp/chrootDebian/root/.git-credentials"
    ]
    for p in paths:
        if os.path.isfile(p):
            try:
                with open(p, "r") as f:
                    content = f.read()
                    for line in content.splitlines():
                        if "oauth_token:" in line:
                            return line.split("oauth_token:")[1].strip()
                        elif "gho_" in line:
                            for part in line.split(":"):
                                if "gho_" in part:
                                    sub = part.split("@")[0]
                                    for word in sub.split():
                                        if word.startswith("gho_"):
                                            return word
            except Exception:
                pass
    return ""

def gh_api(endpoint, method="GET", data=None, content_type="application/json"):
    token = get_token()
    url = f"https://api.github.com/repos/{REPO}/{endpoint}" if not endpoint.startswith("https://") else endpoint
    cmd = ["curl", "-sSL", "-X", method,
           "-H", "User-Agent: ASL-Release-Tool",
           "-H", f"Content-Type: {content_type}"]
    if token:
        cmd.extend(["-H", f"Authorization: token {token}"])
    if data is not None:
        if isinstance(data, (dict, list)):
            cmd.extend(["-d", json.dumps(data)])
        elif isinstance(data, str):
            cmd.extend(["-d", data])
    cmd.append(url)
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    out, err = proc.communicate()
    return out.decode("utf-8", errors="ignore")

def list_releases():
    res = gh_api("releases")
    try:
        data = json.loads(res)
        for rel in data:
            print(f"Release: {rel.get('tag_name')} (ID: {rel.get('id')}), Name: {rel.get('name')}, Draft: {rel.get('draft')}")
            for asset in rel.get('assets', []):
                sz_mb = asset.get('size', 0) / (1024 * 1024)
                print(f"  - Asset: {asset.get('name')} ({sz_mb:.2f} MB), ID: {asset.get('id')}")
        return data
    except Exception as e:
        print("Error parsing releases:", e, "\nRaw output:", res[:300])
        return []

def get_release_by_tag(tag):
    res = gh_api(f"releases/tags/{tag}")
    try:
        data = json.loads(res)
        if "id" in data:
            return data
    except Exception:
        pass
    return None

def create_release(tag, name, body, prerelease=False):
    payload = {
        "tag_name": tag,
        "target_commitish": "master",
        "name": name,
        "body": body,
        "draft": False,
        "prerelease": prerelease
    }
    res = gh_api("releases", method="POST", data=payload)
    try:
        data = json.loads(res)
        if "id" in data:
            print(f"[✓] Created release {tag} (ID: {data['id']})")
            return data
        else:
            print("[!] Release creation response:", data)
    except Exception as e:
        print("[!] Error creating release:", e, res)
    return None

def upload_asset(release_id, file_path):
    if not os.path.isfile(file_path):
        print(f"[!] File not found: {file_path}")
        return False
    filename = os.path.basename(file_path)
    file_size = os.path.getsize(file_path)
    print(f"[*] Uploading {filename} ({file_size / (1024*1024):.2f} MB) to Release ID {release_id}...")

    # Check if asset already exists in release and remove it first (clobber)
    rel_data = gh_api(f"releases/{release_id}")
    try:
        rel_obj = json.loads(rel_data)
        for asset in rel_obj.get("assets", []):
            if asset.get("name") == filename:
                asset_id = asset.get("id")
                print(f"[*] Deleting existing asset {filename} (ID: {asset_id})...")
                gh_api(f"releases/assets/{asset_id}", method="DELETE")
                time.sleep(1)
    except Exception as e:
        print("[!] Note checking existing assets:", e)

    upload_url = f"https://uploads.github.com/repos/{REPO}/releases/{release_id}/assets?name={filename}"
    content_type = "application/x-xz" if filename.endswith(".xz") else "text/plain"
    token = get_token()

    # Use streaming file upload with curl -T (stream from disk without loading full file into RAM)
    cmd = [
        "curl", "-sSL", "-X", "POST",
        "--connect-timeout", "60",
        "--max-time", "7200",
        "--retry", "3",
        "-H", "User-Agent: ASL-Release-Tool",
        "-H", f"Content-Type: {content_type}",
        "-T", file_path,
        upload_url
    ]
    if token:
        cmd.insert(4, f"Authorization: token {token}")
        cmd.insert(4, "-H")

    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    out, err = proc.communicate()
    try:
        resp = json.loads(out.decode("utf-8", errors="ignore"))
        if resp.get("state") == "uploaded" or "id" in resp:
            print(f"[✓] Successfully uploaded {filename} (Asset ID: {resp.get('id')})")
            return True
        else:
            print("[!] Upload returned error:", resp)
            return False
    except Exception as e:
        print("[!] Error parsing upload response:", e, "\nStdout:", out.decode("utf-8", errors="ignore")[:500], "\nStderr:", err.decode("utf-8", errors="ignore")[:500])
        return False

def delete_release_by_tag(tag):
    rel = get_release_by_tag(tag)
    if not rel:
        print(f"[!] Release {tag} not found.")
        return False
    rel_id = rel.get("id")
    print(f"[*] Deleting release {tag} (ID: {rel_id})...")
    res = gh_api(f"releases/{rel_id}", method="DELETE")
    print(f"[✓] Deleted release {tag}")
    return True

def delete_asset_by_id(asset_id):
    print(f"[*] Deleting asset ID {asset_id}...")
    res = gh_api(f"releases/assets/{asset_id}", method="DELETE")
    print(f"[✓] Deleted asset {asset_id}")
    return True

if __name__ == "__main__":
    if len(sys.argv) > 1:
        action = sys.argv[1]
        if action == "list":
            list_releases()
        elif action == "delete-release" and len(sys.argv) > 2:
            tag = sys.argv[2]
            delete_release_by_tag(tag)
        elif action == "delete-asset" and len(sys.argv) > 2:
            asset_id = sys.argv[2]
            delete_asset_by_id(asset_id)
        elif action == "upload" and len(sys.argv) > 3:
            tag = sys.argv[2]
            fpath = sys.argv[3]
            rel = get_release_by_tag(tag)
            if not rel:
                print(f"[*] Release {tag} not found. Creating it...")
                rel = create_release(tag, f"ASL Modded Subsystem Release {tag}", "ASL Prebuilt Modded Debian Rootfs with Turnip Vulkan, Box64, Wine64, and XFCE GTK3 Desktop.")
            if rel:
                upload_asset(rel["id"], fpath)
        elif action == "create" and len(sys.argv) > 2:
            tag = sys.argv[2]
            name = sys.argv[3] if len(sys.argv) > 3 else f"ASL Release {tag}"
            body = sys.argv[4] if len(sys.argv) > 4 else "ASL Release"
            create_release(tag, name, body)
    else:
        list_releases()
