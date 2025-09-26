# Add project specific ProGuard rules here.
# You can control the set of applied configuration files using the
# proguardFiles setting in build.gradle.
#
# For more details, see
#   http://developer.android.com/guide/developing/tools/proguard.html

# If your project uses WebView with JS, uncomment the following
# and specify the fully qualified class name to the JavaScript interface
# class:
#-keepclassmembers class fqcn.of.javascript.interface.for.webview {
#   public *;
#}

# Uncomment this to preserve the line number information for
# debugging stack traces.
#-keepattributes SourceFile,LineNumberTable

# If you keep the line number information, uncomment this to
# hide the original source file name.
#-renamesourcefileattribute SourceFile

# Flutter specific rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep PDF and document scanner related classes
-keep class com.pspdfkit.** { *; }
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.** { *; }

# Keep image processing classes
-keep class com.github.barteksc.** { *; }
-keep class android.support.v4.** { *; }

# Keep permission handler
-keep class com.baseflow.permissionhandler.** { *; }

# Keep shared preferences
-keep class android.preference.** { *; }

# Keep HTTP and networking
-keep class okhttp3.** { *; }
-keep class retrofit2.** { *; }

# Keep Google Play Core classes (for App Bundle)
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# Keep Flutter deferred components
-keep class io.flutter.embedding.engine.deferredcomponents.** { *; }
-dontwarn io.flutter.embedding.engine.deferredcomponents.**