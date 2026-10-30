"""Guest probe: which InnerTube client (if any) serves an age-gated (+18) track.

Mirrors what Pulsr's native/Dart chains send today (no cookies, no poToken),
so the playabilityStatus printed here is exactly the verdict the app sees
when the session is not attached.
"""
import json
import re
import ssl
import urllib.request

VIDEOS = ["DuQGokwsWF8", "F3T70bRdfVA"]
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36")

CLIENTS = [
    # (context client, name id, version, host, extra client fields)
    ("WEB_REMIX", "67", None, "https://music.youtube.com", {"platform": "DESKTOP"}),
    ("WEB", "1", None, "https://www.youtube.com", {"platform": "DESKTOP"}),
    ("MWEB", "2", None, "https://m.youtube.com", {"platform": "MOBILE"}),
    ("ANDROID_VR", "28", "1.62.27", "https://www.youtube.com",
     {"androidSdkVersion": 32, "osName": "Android", "osVersion": "12",
      "platform": "MOBILE", "deviceMake": "Oculus", "deviceModel": "Quest 2"}),
    ("TVHTML5_SIMPLY_EMBEDDED_PLAYER", "85", "2.0", "https://www.youtube.com",
     {"platform": "TV"}),
    ("WEB_EMBEDDED_PLAYER", "56", "1.20250101.00.00", "https://www.youtube.com",
     {"platform": "DESKTOP"}),
    ("IOS", "5", "20.10.4", "https://www.youtube.com",
     {"deviceMake": "Apple", "deviceModel": "iPhone15,3", "osName": "iOS",
      "osVersion": "18.0", "platform": "MOBILE"}),
]

ctx = ssl.create_default_context()


def get(url, data=None, headers=None):
    req = urllib.request.Request(url, data=data, headers=headers or {})
    with urllib.request.urlopen(req, timeout=20, context=ctx) as r:
        return r.read().decode("utf-8", "replace")


def scrape():
    html = get("https://music.youtube.com/", headers={"User-Agent": UA})
    key = re.search(r'"INNERTUBE_API_KEY":"([^"]+)"', html)
    ver = re.search(r'"INNERTUBE_CLIENT_VERSION":"([^"]+)"', html)
    visitor = re.search(r'"VISITOR_DATA":"([^"]+)"', html)
    return (key.group(1) if key else None,
            ver.group(1) if ver else None,
            visitor.group(1) if visitor else None)


api_key, web_ver, visitor = scrape()
print(f"api_key={'ok' if api_key else 'MISSING'} web_version={web_ver} visitor={'ok' if visitor else 'none'}\n")

for video in VIDEOS:
    print(f"=== {video} ===")
    for name, name_id, version, host, extra in CLIENTS:
        client = {"clientName": name, "clientVersion": version or web_ver,
                  "hl": "en", "gl": "US"}
        client.update(extra)
        if visitor:
            client["visitorData"] = visitor
        body = {
            "context": {"client": client},
            "videoId": video,
            "racyCheckOk": True,
            "contentCheckOk": True,
            "playbackContext": {"contentPlaybackContext":
                                {"html5Preference": "HTML5_PREF_WANTS"}},
        }
        if name in ("TVHTML5_SIMPLY_EMBEDDED_PLAYER", "WEB_EMBEDDED_PLAYER"):
            body["thirdParty"] = {"embedUrl": f"https://www.youtube.com/watch?v={video}"}
            body["context"]["thirdParty"] = body["thirdParty"]
        headers = {
            "Content-Type": "application/json",
            "User-Agent": UA,
            "X-Goog-Api-Key": api_key or "",
            "x-youtube-client-name": name_id,
            "x-youtube-client-version": client["clientVersion"],
            "Origin": host,
            "Referer": host + "/",
            "X-Origin": host,
        }
        url = f"{host}/youtubei/v1/player?prettyPrint=false&key={api_key}"
        try:
            raw = get(url, json.dumps(body).encode(), headers)
            data = json.loads(raw)
        except Exception as e:  # noqa: BLE001
            print(f"  {name:<32} transport error: {e}")
            continue
        p = data.get("playabilityStatus", {}) or {}
        status = p.get("status", "?")
        reason = (p.get("reason") or "").replace("\n", " ")[:90]
        fmts = 0
        sd = data.get("streamingData") or {}
        for arr in ("adaptiveFormats", "formats"):
            fmts += len(sd.get(arr) or [])
        print(f"  {name:<32} {status:<16} formats={fmts:<3} {reason}")
    print()
