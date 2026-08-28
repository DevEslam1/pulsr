#!/usr/bin/env python3
"""
CI Guard Script: Prod Flavor Isolation Checker
Validates that the merged AndroidManifest for the 'prod' flavor contains NO
YouTube intent filters, domains, or NewPipeExtractor references.
"""
import os
import sys

def check_prod_manifest():
    manifest_paths = [
        "build/app/intermediates/merged_manifest/prodRelease/processProdReleaseMainManifest/AndroidManifest.xml",
        "build/app/intermediates/merged_manifest/prodDebug/processProdDebugMainManifest/AndroidManifest.xml",
        "build/app/intermediates/merged_manifest/prodRelease/AndroidManifest.xml",
        "build/app/intermediates/merged_manifest/prodDebug/AndroidManifest.xml",
    ]
    
    found_manifest = None
    for p in manifest_paths:
        if os.path.exists(p):
            found_manifest = p
            break

    forbidden_terms = [
        "music.youtube.com",
        "www.youtube.com",
        "youtube.com",
        "youtu.be",
        "NewPipeExtractor",
    ]

    if not found_manifest:
        print("[CI GUARD] Notice: No merged prod manifest found yet at default paths (run gradlew processProdReleaseMainManifest first).")
        # Check source manifest directly
        with open("android/app/src/main/AndroidManifest.xml", "r", encoding="utf-8") as f:
            content = f.read()
        for term in forbidden_terms:
            if term in content:
                print(f"[CI GUARD ERROR] Forbidden term '{term}' detected in android/app/src/main/AndroidManifest.xml!")
                return False
        print("[CI GUARD PASSED] android/app/src/main/AndroidManifest.xml is clean of YouTube/NewPipe.")
        return True

    print(f"[CI GUARD] Checking merged manifest: {found_manifest}")
    with open(found_manifest, "r", encoding="utf-8") as f:
        content = f.read()

    violations = []
    for term in forbidden_terms:
        if term in content:
            violations.append(term)

    if violations:
        print(f"[CI GUARD FAILED] Forbidden YouTube/GPL terms leaked into prod manifest: {violations}")
        return False

    print("[CI GUARD PASSED] Prod merged manifest is completely clean of YouTube/NewPipe references.")
    return True

if __name__ == "__main__":
    success = check_prod_manifest()
    sys.exit(0 if success else 1)
