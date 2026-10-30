"""Does a WEB / WEB_REMIX player response hand back URLs that need the `n`
throttling parameter transformed?

If `n` is present, a Dart-side (no JS engine) resolve cannot produce a
playable URL and the rescue has to run in the native extractor.
"""
import json
import re
import urllib.parse
import urllib.request
import ssl

VIDEO = "dQw4w9WgXcQ"  # public, age-unrestricted control
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36")
ctx = ssl.create_default_context()

html = urllib.request.urlopen(urllib.request.Request(
    "https://music.youtube.com/", headers={"User-Agent": UA}),
    timeout=20, context=ctx).read().decode()
key = re.search(r'"INNERTUBE_API_KEY":"([^"]+)"', html).group(1)
ver = re.search(r'"INNERTUBE_CLIENT_VERSION":"([^"]+)"', html).group(1)

for name, cid, host in (("WEB", "1", "https://www.youtube.com"),
                        ("WEB_REMIX", "67", "https://music.youtube.com"),
                        ("ANDROID_VR", "28", "https://www.youtube.com")):
    client = {"clientName": name, "clientVersion": ver, "hl": "en", "gl": "US"}
    if name == "ANDROID_VR":
        client.update({"androidSdkVersion": 32, "osName": "Android",
                       "osVersion": "12", "platform": "MOBILE",
                       "deviceMake": "Oculus", "deviceModel": "Quest 2"})
    else:
        client["platform"] = "DESKTOP"
    body = {"context": {"client": client}, "videoId": VIDEO,
            "racyCheckOk": True, "contentCheckOk": True}
    req = urllib.request.Request(
        f"{host}/youtubei/v1/player?prettyPrint=false&key={key}",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "User-Agent": UA,
                 "X-Goog-Api-Key": key, "x-youtube-client-name": cid,
                 "x-youtube-client-version": ver, "Origin": host,
                 "Referer": host + "/", "X-Origin": host})
    data = json.loads(urllib.request.urlopen(req, timeout=20, context=ctx).read())
    sd = data.get("streamingData") or {}
    fmts = (sd.get("adaptiveFormats") or []) + (sd.get("formats") or [])
    audio = [f for f in fmts if str(f.get("mimeType", "")).startswith("audio/")]
    print(f"{name}: status={(data.get('playabilityStatus') or {}).get('status')} "
          f"audio={len(audio)}")
    for f in audio[:2]:
        url = f.get("url")
        if not url:
            print(f"   itag {f.get('itag')}: no direct url (cipher only)")
            continue
        q = urllib.parse.parse_qs(urllib.parse.urlparse(url).query)
        print(f"   itag {f.get('itag')}: n={'YES' if 'n' in q else 'no'} "
              f"pot={'yes' if 'pot' in q else 'no'} params={sorted(q)[:8]}")
