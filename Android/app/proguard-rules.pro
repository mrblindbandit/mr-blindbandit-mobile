# R8 rules for the Blindbandit release build.
-keepattributes Signature,InnerClasses,EnclosingMethod,*Annotation*,SourceFile,LineNumberTable,Exceptions
-renamesourcefileattribute SourceFile

# App components referenced from the manifest are kept by AAPT; keep the FCM service explicitly.
-keep class net.mrblindbandit.app.BlindbanditFirebaseMessagingService { *; }

# Clerk SDK (uses Retrofit, OkHttp and kotlinx.serialization internally).
-keep class com.clerk.** { *; }
-dontwarn com.clerk.**

# kotlinx.serialization
-keepclassmembers class kotlinx.serialization.json.** { *** Companion; }
-keepclasseswithmembers class **$$serializer { *; }
-keepclassmembers @kotlinx.serialization.Serializable class ** {
    static **$* *;
    *** Companion;
    kotlinx.serialization.KSerializer serializer(...);
}
-if @kotlinx.serialization.Serializable class **
-keep class <1>$Companion { kotlinx.serialization.KSerializer serializer(...); }

# Retrofit / OkHttp / Okio
-keep,allowobfuscation,allowshrinking interface retrofit2.Call
-keep,allowobfuscation,allowshrinking class retrofit2.Response
-keep,allowobfuscation,allowshrinking class kotlin.coroutines.Continuation
-keepclassmembers,allowshrinking,allowobfuscation interface * { @retrofit2.http.* <methods>; }
-dontwarn retrofit2.**
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**

# LiveKit and WebRTC use JNI.
-keep class org.webrtc.** { *; }
-keep class io.livekit.android.** { *; }
-keep class livekit.** { *; }
-dontwarn org.webrtc.**
-dontwarn io.livekit.**

# Agora RTC uses JNI. Release minify was stripping join callbacks on Play builds.
-keep class io.agora.** { *; }
-keep class net.mrblindbandit.app.connect.AgoraCallSession { *; }
-keep class net.mrblindbandit.app.connect.AgoraCallSession$* { *; }
-dontwarn io.agora.**

# Firebase Messaging ships its own consumer rules; silence optional deps.
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Protobuf used by LiveKit.
-keep class * extends com.google.protobuf.GeneratedMessageLite { *; }
-dontwarn com.google.protobuf.**
