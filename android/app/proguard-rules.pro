# ═══════════════════════════════════════════════════════════════════════
# DRS Video — release R8 rules
#
# Reconstructed (P5 + field fix). Mandate: SAFETY OVER SIZE. Every plugin
# family that crosses a reflection / native / serialization boundary is
# kept whole; only pure-Dart code paths are allowed to shrink.
#
# Field report (XOS 15 / Infinix): "Bad state: enqueue returned null".
# Root cause chain: the app removes the eager WorkManagerInitializer from
# androidx.startup (the v1.0.4 startup-crash fix) and relies fully on
# on-demand init via DrsApplication : Configuration.Provider; R8 breaking
# any class in that chain makes flutter_downloader's un-guarded native
# enqueue() throw, and the plugin's Dart layer swallows the exception and
# returns null. The keeps below pin the whole chain.
# ═══════════════════════════════════════════════════════════════════════

# ── THE FIELD-FAILURE FIX: flutter_downloader + WorkManager chain ─────
-keep class vn.hunghd.flutterdownloader.** { *; }
-keep class androidx.work.** { *; }
-keep interface androidx.work.Configuration$Provider { *; }
-keep class com.drs.drs_video.DrsApplication { *; }

# ── App code: manifest classes, CrashGuard, native bridge ─────────────
-keep class com.drs.drs_video.** { *; }

# ── Flutter engine + generated plugin registrant ──────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# ── audio_service (reflective MediaBrowserService + MediaButton) ──────
-keep class com.ryanheise.** { *; }

# ── flutter_local_notifications (Gson-serialized notification details,
#    scheduled alarms, boot receiver restored by the system) ───────────
-keep class com.dexterous.** { *; }
-keep class com.google.gson.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keepclassmembers,allowobfuscation class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# ── flutter_secure_storage (EncryptedSharedPreferences / Tink) ────────
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class com.google.crypto.tink.** { *; }

# ── flutter_inappwebview (js bridge, reflective WebMessage handlers) ──
-keep class com.pichillilorenzo.flutter_inappwebview.** { *; }

# ── VPN: openvpn_flutter + embedded ics-openvpn core (J ni/aidl) ──────
-keep class id.laskarmedia.openvpn_flutter.** { *; }
-keep class de.blinkt.openvpn.** { *; }

# ── jni runtime (media_kit native bindings via JNI) ───────────────────
-keep class com.github.dart_lang.jni.** { *; }

# ── sqflite (provider-backed DB, lifecycle callbacks by name) ─────────
-keep class com.tekartik.sqflite.** { *; }

# ── Generic safety net ─────────────────────────────────────────────────
-keepattributes Signature, InnerClasses, EnclosingMethod, *Annotation*, Exceptions
-dontwarn android.support.**
-dontwarn org.slf4j.**
# ics-openvpn (com.github.nizwar:openvpn_library) bundles Apache Tika whose
# optional javax.xml.stream (StAX) path never exists on Android — compile-time
# reference only, dead code at runtime (R8 missing_rules.txt, 2026-09-29).
-dontwarn javax.xml.stream.XMLStreamException
