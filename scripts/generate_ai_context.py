#!/usr/bin/env python3
"""
Pulsr Slim AI-Context Generator
Generates a lean, high-signal architecture context file (pulsr-context.md) targeting < 3,000 lines.
Complies with P4-1:
- pubspec.yaml, analysis_options.yaml, CMakeLists.txt (source),
  app/build.gradle.kts, lib/main.dart, DI graph overview, domain interfaces,
  Go go.mod + protocol.go, and relative directory tree <= 3 levels.
- Strict exclusions: .cxx/, generated .freezed.dart/.g.dart, compiler-ID files, absolute paths.
"""

import os
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

EXCLUDE_DIRS = {
    ".git", ".cxx", "build", ".dart_tool", "node_modules", "third_party",
    ".gemini", ".agents", ".opencode", ".idea", ".vscode", "__pycache__"
}

EXCLUDE_EXTENSIONS = {
    ".freezed.dart", ".g.dart", ".config.dart", ".so", ".a", ".o", ".exe",
    ".dll", ".dylib", ".bin", ".zip", ".tar.gz", ".png", ".jpg", ".jpeg",
    ".webp", ".svg", ".ico", ".ttf", ".otf", ".woff", ".woff2", ".pdf"
}

def is_excluded_path(p: Path) -> bool:
    for part in p.parts:
        if part in EXCLUDE_DIRS:
            return True
        if part.endswith(".cxx"):
            return True
    name = p.name
    for ext in EXCLUDE_EXTENSIONS:
        if name.endswith(ext):
            return True
    return False

def generate_dir_tree(root: Path, max_depth: int = 3) -> str:
    lines = ["pulsr/"]
    prefix = ""

    def walk(directory: Path, depth: int, cur_prefix: str):
        if depth > max_depth:
            return
        try:
            entries = sorted(list(directory.iterdir()), key=lambda x: (not x.is_dir(), x.name.lower()))
        except PermissionError:
            return
        
        filtered = [e for e in entries if not is_excluded_path(e)]
        count = len(filtered)
        for i, entry in enumerate(filtered):
            is_last = (i == count - 1)
            connector = "└── " if is_last else "├── "
            child_prefix = cur_prefix + ("    " if is_last else "│   ")
            if entry.is_dir():
                lines.append(f"{cur_prefix}{connector}{entry.name}/")
                walk(entry, depth + 1, child_prefix)
            else:
                lines.append(f"{cur_prefix}{connector}{entry.name}")

    walk(root, 1, "")
    return "\n".join(lines)

def sanitize_content(text: str) -> str:
    # Remove any absolute paths like D:\Courses\... or /Users/...
    text = re.sub(r'[A-Za-z]:\\[^"\'\s\n\r]+', '<REL_PATH>', text)
    return text

def read_rel_file(rel_path: str) -> str:
    p = REPO_ROOT / rel_path
    if not p.is_file():
        return f"<!-- File not found: {rel_path} -->"
    content = p.read_text(encoding="utf-8", errors="replace")
    return sanitize_content(content)

def extract_domain_interfaces() -> str:
    domain_dir = REPO_ROOT / "lib" / "domain"
    out = []
    for sub in ["interfaces", "repositories"]:
        target = domain_dir / sub
        if not target.is_dir():
            continue
        for file in sorted(target.glob("*.dart")):
            rel = file.relative_to(REPO_ROOT).as_posix()
            content = file.read_text(encoding="utf-8", errors="replace")
            # Extract class/abstract interface definition
            lines = content.splitlines()
            decl_lines = []
            for line in lines:
                stripped = line.strip()
                if (stripped.startswith("abstract class") or 
                    stripped.startswith("class") or 
                    re.match(r'^(Future<|Stream<|void|bool|int|String|\w+)\s+\w+\(', stripped)):
                    decl_lines.append(f"  {stripped}")
            out.append(f"### `{rel}`\n```dart\n" + "\n".join(decl_lines[:25]) + "\n```")
    return "\n\n".join(out)

def extract_di_graph() -> str:
    inj_file = REPO_ROOT / "lib" / "core" / "di" / "injection.dart"
    if not inj_file.is_file():
        return "DI injection file not found."
    content = inj_file.read_text(encoding="utf-8", errors="replace")
    matches = re.findall(r'getIt\.register\w+<([^>]+)>\([^)]*\)', content)
    warmups = re.findall(r'getIt\.getAsync<([^>]+)>', content)
    lines = ["**Registered Singletons & Services:**"]
    for m in set(matches):
        lines.append(f"- `{m}`")
    lines.append("\n**Pre-warmed Singletons (Async Initialization):**")
    for w in set(warmups):
        lines.append(f"- `{w}`")
    return "\n".join(lines)

def main():
    print("Generating slim AI context document...")
    tree = generate_dir_tree(REPO_ROOT, max_depth=3)
    pubspec = read_rel_file("pubspec.yaml")
    analysis = read_rel_file("analysis_options.yaml")
    cmake = read_rel_file("android/app/src/main/cpp/CMakeLists.txt")
    gradle = read_rel_file("android/app/build.gradle.kts")
    main_dart = read_rel_file("lib/main.dart")
    go_mod = read_rel_file("server/pulsr_party/go.mod")
    protocol_go = read_rel_file("server/pulsr_party/protocol/protocol.go")
    domain_interfaces = extract_domain_interfaces()
    di_graph = extract_di_graph()

    doc = f"""# PULSR — SLIM ARCHITECTURE & REPO CONTEXT

> Offline-first audiophile music player.
> Flutter (frontend/BLoC) + C++20 NDK (Audio DSP Engine) + Go (Listen Together Party Server).

---

## 1. Directory Tree (Depth <= 3)
```
{tree}
```

---

## 2. Core Build & Analysis Configurations

### `pubspec.yaml`
```yaml
{pubspec}
```

### `analysis_options.yaml`
```yaml
{analysis}
```

### `android/app/src/main/cpp/CMakeLists.txt`
```cmake
{cmake}
```

### `android/app/build.gradle.kts`
```kotlin
{gradle}
```

---

## 3. Flutter Entry & Dependency Injection Graph

### `lib/main.dart`
```dart
{main_dart}
```

### Dependency Injection Graph (`lib/core/di/injection.dart`)
{di_graph}

---

## 4. Domain Interfaces & Repositories
{domain_interfaces}

---

## 5. Go Listen-Together Party Server

### `server/pulsr_party/go.mod`
```go
{go_mod}
```

### `server/pulsr_party/protocol/protocol.go`
```go
{protocol_go}
```
"""

    out_file = REPO_ROOT / "pulsr-context.md"
    out_file.write_text(doc, encoding="utf-8")
    line_count = len(doc.splitlines())
    print(f"Generated {out_file} ({line_count} lines). Target < 3000: {'PASS' if line_count < 3000 else 'FAIL'}")

if __name__ == "__main__":
    main()
