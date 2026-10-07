# Release shrinking (R8) rules for the native ML libraries. They load classes
# by reflection / JNI, so R8 must neither remove nor rename them.

# MediaPipe Tasks (pose / hand landmarkers in MainActivity.kt)
-keep class com.google.mediapipe.** { *; }
-dontwarn com.google.mediapipe.**

# Protobuf (used by MediaPipe)
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**

# AutoValue / annotations referenced by MediaPipe but not needed at runtime
-dontwarn com.google.auto.value.**
-dontwarn javax.annotation.**
-dontwarn javax.lang.model.**
-dontwarn autovalue.shaded.**

# TensorFlow Lite (+ select TF ops, GPU delegate)
-keep class org.tensorflow.** { *; }
-dontwarn org.tensorflow.**

# ONNX Runtime (onnxruntime Flutter plugin)
-keep class ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**

# Google Play Core (referenced by Flutter's deferred components, unused here)
-dontwarn com.google.android.play.core.**
