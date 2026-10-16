#!/usr/bin/env python3
"""
Bridge Parity Enforcement Script

Deterministically verifies that all MethodChannel methods invoked from Dart's
`AudioEffectsChannel` have matching handlers in Kotlin's `AudioEffectsPlugin`,
and that callbacks from native (e.g. `onRouteChanged`, `onSystemVolumeChanged`)
are handled in Dart.
"""

import sys
import re
from pathlib import Path

def get_dart_invoked_methods(dart_file: Path) -> set[str]:
    content = dart_file.read_text(encoding="utf-8")
    methods = set()
    
    # 1. Direct _channel.invokeMethod('methodName', ...)
    for match in re.finditer(r"_channel\s*\.\s*invokeMethod(?:<[^>]+>)?\s*\(\s*['\"]([^'\"]+)['\"]", content):
        name = match.group(1)
        if name not in {"method", "enabled", "gains"}:
            methods.add(name)
            
    # 2. _invokeNativeSetter('methodName', ...)
    for match in re.finditer(r"_invokeNativeSetter\s*\(\s*['\"]([^'\"]+)['\"]", content):
        methods.add(match.group(1))

    return methods

def get_dart_callbacks_handled(dart_file: Path) -> set[str]:
    content = dart_file.read_text(encoding="utf-8")
    callbacks = set()
    for match in re.finditer(r"call\.method\s*==\s*['\"]([^'\"]+)['\"]", content):
        callbacks.add(match.group(1))
    return callbacks

def get_kotlin_handled_methods(kotlin_file: Path) -> set[str]:
    content = kotlin_file.read_text(encoding="utf-8")
    methods = set()

    # Look for calls inside onMethodCall / handleCoreAndHalCall / handleNativeDspCall / handleAdvancedAndDiagnosticCall
    # Matches patterns like "methodName" -> or "method1", "method2" ->
    # Find all string literals followed by -> or comma before ->
    in_switch = False
    for line in content.splitlines():
        trimmed = line.strip()
        # Find cases like "setAudioSessionId", "setVirtualizerEnabled" -> {
        # or "setAudioSessionId" -> {
        # or when (call.method)
        if "when (call.method)" in trimmed or "when(call.method)" in trimmed:
            in_switch = True
            continue
        
        # Match quoted method names that appear before '->' or ','
        # e.g., "setVolumeBoost" ->
        # "methodA", "methodB" ->
        if "->" in trimmed:
            prefix = trimmed.split("->")[0]
            for m in re.finditer(r'"([a-zA-Z0-9_]+)"', prefix):
                methods.add(m.group(1))
        elif trimmed.startswith('"') and trimmed.endswith('",'):
            for m in re.finditer(r'"([a-zA-Z0-9_]+)"', trimmed):
                methods.add(m.group(1))
        elif 'call.method == "' in trimmed:
            for m in re.finditer(r'call\.method\s*==\s*"([a-zA-Z0-9_]+)"', trimmed):
                methods.add(m.group(1))

    return methods

def get_kotlin_callbacks_invoked(kotlin_file: Path) -> set[str]:
    content = kotlin_file.read_text(encoding="utf-8")
    callbacks = set()
    for match in re.finditer(r"invokeMethod\s*\(\s*\"([a-zA-Z0-9_]+)\"", content):
        callbacks.add(match.group(1))
    return callbacks

def check_parity() -> bool:
    root = Path(__file__).resolve().parent.parent
    dart_channel = root / "lib" / "data" / "audio" / "audio_effects_channel.dart"
    kotlin_plugin = root / "android" / "app" / "src" / "main" / "kotlin" / "com" / "pulsr" / "music" / "AudioEffectsPlugin.kt"

    if not dart_channel.exists():
        print(f"ERROR: Dart channel file not found: {dart_channel}", file=sys.stderr)
        return False
    if not kotlin_plugin.exists():
        print(f"ERROR: Kotlin plugin file not found: {kotlin_plugin}", file=sys.stderr)
        return False

    dart_methods = get_dart_invoked_methods(dart_channel)
    kotlin_methods = get_kotlin_handled_methods(kotlin_plugin)

    dart_callbacks = get_dart_callbacks_handled(dart_channel)
    kotlin_callbacks = get_kotlin_callbacks_invoked(kotlin_plugin)

    print(f"Scanned Dart methods: {len(dart_methods)}")
    print(f"Scanned Kotlin handlers: {len(kotlin_methods)}")
    print(f"Scanned Native callbacks: {len(kotlin_callbacks)}")
    print(f"Scanned Dart callback handlers: {len(dart_callbacks)}")

    # Missing in Kotlin
    missing_in_kotlin = sorted(list(dart_methods - kotlin_methods))
    # Missing callbacks in Dart
    missing_callbacks_in_dart = sorted(list(kotlin_callbacks - dart_callbacks))

    has_error = False

    if missing_in_kotlin:
        print("\n[!] Bridge Parity Failure: Dart invokes methods that have NO handler in Kotlin:", file=sys.stderr)
        for m in missing_in_kotlin:
            print(f"  - {m}", file=sys.stderr)
        has_error = True

    if missing_callbacks_in_dart:
        print("\n[!] Bridge Parity Failure: Kotlin emits callbacks that have NO handler in Dart:", file=sys.stderr)
        for c in missing_callbacks_in_dart:
            print(f"  - {c}", file=sys.stderr)
        has_error = True

    if not has_error:
        print("\n[OK] Bridge parity verified: all Dart calls have Kotlin handlers, all native callbacks are handled.")
        return True
    return False

if __name__ == "__main__":
    if not check_parity():
        sys.exit(1)
    sys.exit(0)
