# Flutter core classes - DO NOT REMOVE
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }

# Keep MainActivity and Application
-keep class com.kkape.mynas.** { *; }

# TensorFlow Lite GPU support
-dontwarn org.tensorflow.lite.gpu.GpuDelegateFactory$Options
-keep class org.tensorflow.lite.** { *; }
-keep class org.tensorflow.lite.gpu.** { *; }

# Keep TFLite native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Suppress warnings for optional dependencies
-dontwarn com.google.android.play.core.**
-dontwarn com.google.android.gms.**
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
-dontwarn kotlin.Metadata
