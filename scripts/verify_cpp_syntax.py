import glob
import os
import subprocess
import sys

def main():
    ndk_clang = r"D:\Courses\work\Android\Sdk\ndk\27.1.12297006\toolchains\llvm\prebuilt\windows-x86_64\bin\clang++.exe"
    if not os.path.exists(ndk_clang):
        # fallback search
        found = glob.glob(r"D:\Courses\work\Android\Sdk\ndk\**\bin\clang++.exe", recursive=True)
        if found:
            ndk_clang = found[0]
        else:
            print("NDK clang++ not found on machine, skipping host syntax check")
            return 0

    cpp_files = glob.glob(r"android/app/src/main/cpp/*.cpp")
    include_dir = os.path.abspath(r"android/app/src/main/cpp")

    for f in cpp_files:
        cmd = [
            ndk_clang,
            "--target=aarch64-linux-android28",
            "-fsyntax-only",
            "-std=c++20",
            f"-I{include_dir}",
            f,
        ]
        res = subprocess.run(cmd, capture_output=True, text=True)
        if res.returncode != 0:
            print(f"Error compiling {f}:\n{res.stderr}")
            sys.exit(1)
        print(f"  OK: {os.path.basename(f)}")

    print("\nALL C++ FILES SYNTAX VERIFIED CLEAN (0 errors)!")
    return 0

if __name__ == "__main__":
    sys.exit(main())
