"""Wider client matrix for the two age-gated videos.

Looking for any client/version that still returns streamingData without a
session (the old `contentCheckOk` age-gate bypass), and for clients whose
pinned version is dead platform-wide.
"""
import json
import re
import urllib.request

VIDEOS = ["DuQGokwsWF8", "F3T70bRdfVA"]
UA_PC = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
         "(KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36")

CLIENTS = [
    ("WEB", "1", "1.20261027.10.00", {"platform": "DESKTOP"}),
    ("MWEB", "2", "2.20261027.01.00", {"platform": "MOBILE",
                                       "clientFormFactor": "SMALL_FORM_FACTOR"}),
    ("ANDROID", "3", "20.10.38",
     {"androidSdkVersion": 34, "osName": "Android", "osVersion": "14",
      "platform": "MOBILE", "deviceMake": "Google", "deviceModel": "Pixel 8"}),
    ("IOS", "5", "21.02.3",
     {"deviceMake": "Apple", "deviceModel": "iPhone16,2", "osName": "iOS",
      "osVersion": "18.3.1", "platform": "MOBILE"}),
    ("TVHTML5", "7", "7.20250101.00.00", {"platform": "TV"}),
    ("ANDROID_VR", "28", "1.65.10",
     {"androidSdkVersion": 32, "osName": "Android", "osVersion": "12",
      "platform": "MOBILE", "deviceMake": "Oculus", "deviceModel": "Quest 3"}),
    ("ANDROID_TESTSUITE", "30", "1.9",
     {"androidSdkVersion": 28, "osName": "Android", "osVersion": "9",
      "platform": "MOBILE"}),
    ("ANDROID_MUSIC", "21", "8.32.50",
     {"androidSdkVersion": 34, "osName": "Android", "osVersion": "14",
      "platform": "MOBILE", "deviceMake": "Google", "deviceModel": "Pixel 8"}),
    ("IOS_MUSIC", "26", "8.32.1",
     {"deviceMake": "Apple", "deviceModel": "iPhone15,3", "osName": "iOS",
      "osVersion": "18.0", "platform": "MOBILE"}),
]

ctx_ssl = __import__("ssl").create_default_context()


def post(host, api_key, headers, body):
    req = urllib.request.Request(
        f"{host}/youtubei/v1/player?prettyPrint=false&key={api_key}",
        data=json.dumps(body).encode(), headers=headers)
    with urllib.request.urlopen(req, timeout=20, context=ctx_ssl) as r:
        return json.loads(r.read().decode("utf-8", "replace"))


html = urllib.request.urlopen(
    urllib.request.Request("https://music.youtube.com/", headers={"User-Agent": UA_PC}),
    timeout=20, context=ctx_ssl).read().decode("utf-8", "replace")
api_key = re.search(r'"INNERTUBE_API_KEY":"([^"]+)"', html).group(1)

for video in VIDEOS:
    print(f"=== {video} ===")
    for name, cid, ver, extra in CLIENTS:
        client = {"clientName": name, "clientVersion": ver, "hl": "en", "gl": "US"}
        client.update(extra)
        body = {"context": {"client": client}, "videoId": video,
                "racyCheckOk": True, "contentCheckOk": True,
                "playbackContext": {"contentPlaybackContext":
                                    {"html5Preference": "HTML5_PREF_WANTS"}}}
        host = "https://www.youtube.com"
        headers = {"Content-Type": "application/json", "User-Agent": UA_PC,
                   "X-Goog-Api-Key": api_key, "x-youtube-client-name": cid,
                   "x-youtube-client-version": ver, "Origin": host,
                   "Referer": host + "/", "X-Origin": host}
        try:
            data = post(host, api_key, headers, body)
        except urllib.error.HTTPError as e:
            print(f"  {name:<20}{ver:<18} HTTP {e.code}")
            continue
        except Exception as e:  # noqa: BLE001
            print(f"  {name:<20}{ver:<18} error {e}")
            continue
        p = data.get("playabilityStatus") or {}
        sd = data.get("streamingData") or {}
        n = len(sd.get("adaptiveFormats") or []) + len(sd.get("formats") or [])
        print(f"  {name:<20}{ver:<18} {p.get('status','?'):<16} formats={n:<3}"
              f" {(p.get('reason') or '')[:70]}")
    print()
