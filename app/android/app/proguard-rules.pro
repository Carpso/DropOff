# Flutter ProGuard rules
# Play Advisory (release 84) + R8 full mode: narrowed the old catch-alls.
# `io.flutter.**` is the official Flutter rule and stays. The redundant
# `io.flutter.plugin.**` / `io.flutter.plugins.**` were folded into it.
-keep class io.flutter.** { *; }
-dontwarn io.flutter.embedding.**
-dontwarn io.flutter.plugins.embeddedviews.**
-dontwarn io.flutter.plugins.android.**

# Firebase
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# Africa's Talking / okhttp
-dontwarn okhttp3.**
-dontwarn okio.**

# Shared preferences / secure storage
-dontwarn androidx.security.crypto.**

# WebSocket
-dontwarn org.eclipse.jetty.**
-dontwarn javax.annotation.**

# Dropped the old `-keep class zm.dropoff.dropoff.** { *; }` catch-all:
# our models use explicit jsonEncode/jsonDecode (no reflection), so R8 can
# safely shrink unused app classes. If a plugin ever reflects a model, add a
# targeted -keep for that one class here, not the whole package.
