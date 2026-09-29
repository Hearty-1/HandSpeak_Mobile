package com.example.flutter_application_1

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarkerResult
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "fsl_holistic_channel"
    private var handLandmarker: HandLandmarker? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Initialize MediaPipe Hand / Holistic Detector
        initMediaPipe()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "processFrame") {
                val yuvBytes = call.argument<ByteArray>("yuvBytes")
                val width = call.argument<Int>("width")
                val height = call.argument<Int>("height")

                if (yuvBytes == null || width == null || height == null) {
                    result.error("INVALID_ARGUMENTS", "Missing yuvBytes, width, or height", null)
                    return@setMethodCallHandler
                }

                try {
                    // 1. Convert YUV Camera Bytes to Bitmap
                    val bitmap = yuvToBitmap(yuvBytes, width, height)
                    if (bitmap == null) {
                        result.success(null)
                        return@setMethodCallHandler
                    }

                    // 2. Process Bitmap through MediaPipe
                    val landmarksList = processFrameWithMediaPipe(bitmap)

                    // 3. Return flattened 204 doubles (68 landmarks * 3) to Flutter
                    result.success(landmarksList)

                } catch (e: Exception) {
                    result.error("PROCESSING_ERROR", e.localizedMessage, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun initMediaPipe() {
        try {
            val baseOptions = BaseOptions.builder()
                .setModelAssetPath("hand_landmarker.task")
                .build()

            val options = HandLandmarker.HandLandmarkerOptions.builder()
                .setBaseOptions(baseOptions)
                .setNumHands(2)
                .setMinHandDetectionConfidence(0.5f)
                .setMinTrackingConfidence(0.5f)
                .setRunningMode(RunningMode.IMAGE)
                .build()

            handLandmarker = HandLandmarker.createFromOptions(this, options)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun yuvToBitmap(yuvBytes: ByteArray, width: Int, height: Int): Bitmap? {
        return try {
            val yuvImage = YuvImage(yuvBytes, ImageFormat.NV21, width, height, null)
            val out = ByteArrayOutputStream()
            yuvImage.compressToJpeg(Rect(0, 0, width, height), 90, out)
            val imageBytes = out.toByteArray()
            BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
        } catch (e: Exception) {
            null
        }
    }

    private fun processFrameWithMediaPipe(bitmap: Bitmap): List<Double> {
        val targetLandmarks = 68
        val outputFloats = ArrayList<Double>()

        val mpImage = BitmapImageBuilder(bitmap).build()
        val result: HandLandmarkerResult? = handLandmarker?.detect(mpImage)

        if (result != null && result.landmarks().isNotEmpty()) {
            for (hand in result.landmarks()) {
                for (landmark in hand) {
                    outputFloats.add(landmark.x().toDouble())
                    outputFloats.add(landmark.y().toDouble())
                    outputFloats.add(landmark.z().toDouble())
                }
            }
        }

        // Ensure total landmarks count strictly equals 68 (204 values) for ONNX input compatibility
        val requiredLength = targetLandmarks * 3
        while (outputFloats.size < requiredLength) {
            outputFloats.add(0.0)
        }

        return outputFloats.take(requiredLength)
    }

    override fun onDestroy() {
        handLandmarker?.close()
        super.onDestroy()
    }
}