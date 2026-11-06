# Flutter ProGuard rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
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

# Keep model classes used by JSON serialization
-keep class zm.dropoff.dropoff.** { *; }
