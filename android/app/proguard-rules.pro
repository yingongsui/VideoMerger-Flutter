# Keep FFmpegKit native JNI classes and callbacks intact under R8 minification
-keep class com.arthenica.ffmpegkit.** { *; }
-keep class com.arthenica.smartexception.** { *; }
