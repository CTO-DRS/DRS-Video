#!/usr/bin/env bash
# Re-applies pub-cache patches needed to build DRS Video.
# Run after EVERY `flutter pub get` (pub-cache is outside the repo).
set -euo pipefail
CACHE="${HOME}/.pub-cache/hosted/pub.dev"

# 1) flutter_inappwebview_android: R8 chokes on proguard-android.txt.
INAPP_DIR=$(ls -d "${CACHE}"/flutter_inappwebview_android-* 2>/dev/null | head -1 || true)
if [[ -n "${INAPP_DIR}" ]]; then
  F="${INAPP_DIR}/android/build.gradle"
  if [[ -f "$F" ]] && grep -q "proguard-android.txt" "$F"; then
    sed -i "s/proguard-android\.txt/proguard-android-optimize.txt/g" "$F"
    echo "patched inappwebview R8 ($(basename "$INAPP_DIR"))"
  else
    echo "inappwebview R8 already OK"
  fi
fi

# 2) jni: restrict native build to arm64 (matches app abiFilters; avoids
#    needing x86/armv7 NDK sysroots for this transitive plugin).
JNI_DIR=$(ls -d "${CACHE}"/jni-1.* 2>/dev/null | sort -V | tail -1 || true)
if [[ -n "${JNI_DIR}" ]]; then
  F="${JNI_DIR}/android/build.gradle"
  if [[ -f "$F" ]] && ! grep -q "abiFilters" "$F"; then
    python3 - "$F" << 'PYEOF'
import sys
path = sys.argv[1]
src = open(path).read()
needle = """    defaultConfig {
        minSdk 21
    }
}"""
patch = """    defaultConfig {
        minSdk 21
        // DRS patch: arm64 only — see scripts/patch_pub_cache.sh
        ndk {
            abiFilters "arm64-v8a"
        }
    }
}"""
if needle not in src:
    print("jni defaultConfig block not found — patch manually", file=sys.stderr)
    sys.exit(1)
open(path, "w").write(src.replace(needle, patch))
print("patched jni abiFilters")
PYEOF
  else
    echo "jni abiFilters already OK"
  fi
fi

echo "pub-cache patches done"
