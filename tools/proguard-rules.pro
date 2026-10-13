# Flutter 通用规则
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# 加密 / 持久层
-keep class com.it_nomads.fluttersqflite.** { *; }
-dontwarn com.it_nomads.fluttersqflite.**
-keep class com.baseflow.** { *; }
-keep class com.it_nomads.** { *; }

# secure storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class androidx.security.crypto.** { *; }
-keep class com.google.crypto.tink.** { *; }

# 网络 / 图片
-keep class io.flutter.plugins.imagepicker.** { *; }

# FFI / native vault:符号被显式 visibility("default") 导出,无需 -keep
# 但 -keepclassmembers 防止 native 方法被混淆
-keepclasseswithmembernames class * {
    native <methods>;
}

# Tink (Android Keystore 加密)
-keep class com.google.crypto.tink.** { *; }
-dontwarn com.google.crypto.tink.**

# 移除 log
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
    public static int i(...);
    public static int w(...);
}

# 极限压缩
-optimizationpasses 5
-allowaccessmodification
-overloadaggressively
-repackageclasses ''

# 保留行号(崩溃栈解析用,但类名/方法名已混淆)
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile