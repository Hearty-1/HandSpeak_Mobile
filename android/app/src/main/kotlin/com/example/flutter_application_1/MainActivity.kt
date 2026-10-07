package com.example.flutter_application_1

import android.graphics.Bitmap
import android.graphics.Matrix
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.components.containers.NormalizedLandmark
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarkerResult
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import java.util.concurrent.Executors

/**
 * "fsl_holistic_channel": reproduces the 68-keypoint frame layout of the civic
 * training scripts (extract_lupang_hinirang.py, MediaPipe Holistic):
 *
 *   0-13  pose landmarks 11..24 (shoulders, elbows, wrists, pinky/index/thumb, hips)
 *   14-34 signer's LEFT hand (21)
 *   35-55 signer's RIGHT hand (21)
 *   56-67 face points [1, 33, 61, 199, 263, 291, 0, 17, 10, 152, 234, 454]
 *
 * Coordinates are normalised to the UPRIGHT, un-mirrored frame (x, y in 0..1,
 * z as reported by MediaPipe). Missing parts are zeros, exactly like training.
 */
class MainActivity : FlutterActivity() {
    private val CHANNEL = "fsl_holistic_channel"
    private var handLandmarker: HandLandmarker? = null
    private var poseLandmarker: PoseLandmarker? = null

    // MediaPipe inference is far too slow for the UI thread. Pose and hands
    // run on separate threads in parallel so a frame costs max(), not sum().
    // Camera image -> bitmap conversion has its own thread, so it overlaps the
    // inference of the previous frame (Dart keeps up to 2 frames in flight).
    private val worker = Executors.newSingleThreadExecutor()
    private val convertWorker = Executors.newSingleThreadExecutor()
    private val handWorker = Executors.newSingleThreadExecutor()
    // Pose (full model) is the slowest part (~85 ms on a Unisoc T616). When it
    // is slow it runs on every other frame only: the server's clean_sequence
    // interpolates pose gaps up to 0.5 s, while the hands, which carry the
    // handshape changes, are tracked on every frame. The last pose is still
    // used to tell the signer's left hand from the right.
    private var lastPose: List<NormalizedLandmark>? = null
    private var lastPoseMs = 0L
    private var frameCount = 0L
    private val mainHandler = Handler(Looper.getMainLooper())
    private var lastTimestampMs = 0L
    // Reused ARGB buffer for camera-frame conversion (only touched on convertWorker).
    private var pixelBuffer = IntArray(0)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        worker.execute { initMediaPipe() }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method != "processFrame") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val width = call.argument<Int>("width")
            val height = call.argument<Int>("height")
            val rotation = call.argument<Int>("rotation") ?: 0
            // Preferred: the camera's raw Y/U/V planes (no per-pixel work in Dart).
            val yPlane = call.argument<ByteArray>("y")
            val uPlane = call.argument<ByteArray>("u")
            val vPlane = call.argument<ByteArray>("v")
            val yRowStride = call.argument<Int>("yRowStride")
            val uvRowStride = call.argument<Int>("uvRowStride")
            val uvPixelStride = call.argument<Int>("uvPixelStride") ?: 1
            // Legacy: one NV21 buffer built in Dart.
            val yuvBytes = call.argument<ByteArray>("yuvBytes")

            val hasPlanes = yPlane != null && uPlane != null && vPlane != null &&
                yRowStride != null && uvRowStride != null
            if (width == null || height == null || (!hasPlanes && yuvBytes == null)) {
                result.error("INVALID_ARGUMENTS", "Missing image data, width, or height", null)
                return@setMethodCallHandler
            }

            convertWorker.execute {
                try {
                    val t0 = SystemClock.uptimeMillis()
                    val bitmap = if (hasPlanes) {
                        yuv420ToUprightBitmap(yPlane!!, uPlane!!, vPlane!!, width, height,
                            yRowStride!!, uvRowStride!!, uvPixelStride, rotation)
                    } else {
                        yuvToUprightBitmap(yuvBytes!!, width, height, rotation)
                    }
                    val convertMs = SystemClock.uptimeMillis() - t0
                    if (bitmap == null) {
                        mainHandler.post { result.success(null) }
                        return@execute
                    }
                    worker.execute {
                        try {
                            val frame = processHolistic(bitmap) + ("convertMs" to convertMs)
                            mainHandler.post { result.success(frame) }
                        } catch (e: Exception) {
                            mainHandler.post { result.error("PROCESSING_ERROR", e.localizedMessage, null) }
                        }
                    }
                } catch (e: Exception) {
                    mainHandler.post { result.error("PROCESSING_ERROR", e.localizedMessage, null) }
                }
            }
        }
    }

    private fun baseOptions(model: String, delegate: Delegate) =
        BaseOptions.builder().setModelAssetPath(model).setDelegate(delegate).build()

    /** What actually loaded (model / delegate), reported to Dart for diagnostics. */
    private var engineInfo = "not loaded"

    // lupang_common_v4.HOLISTIC_KWARGS: detection / tracking confidence 0.35
    // ("fewer hand drops at ~20 fps / motion blur").
    private val minConfidence = 0.35f

    private fun initMediaPipe() {
        var handInfo = "none"
        // GPU first (on a Unisoc T616 the CPU hand model was slower: 100-270 ms
        // vs 50-150 ms), CPU fallback.
        for (delegate in listOf(Delegate.GPU, Delegate.CPU)) {
            if (handLandmarker != null) break
            try {
                handLandmarker = HandLandmarker.createFromOptions(
                    this,
                    HandLandmarker.HandLandmarkerOptions.builder()
                        .setBaseOptions(baseOptions("hand_landmarker.task", delegate))
                        .setNumHands(2)
                        .setMinHandDetectionConfidence(minConfidence)
                        .setMinHandPresenceConfidence(minConfidence)
                        .setMinTrackingConfidence(minConfidence)
                        .setRunningMode(RunningMode.VIDEO)
                        .build()
                )
                handInfo = "hands/$delegate"
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
        // Training ran Holistic with model_complexity=1 = the FULL pose model.
        // It is also several times faster than heavy, which held capture at
        // ~3 fps (the v4 kinematic gates need a proper trajectory). Heavy is
        // kept as a fallback only.
        var poseInfo = "none"
        loop@ for (model in listOf("pose_landmarker_full.task", "pose_landmarker_heavy.task")) {
            for (delegate in listOf(Delegate.GPU, Delegate.CPU)) {
                try {
                    poseLandmarker = PoseLandmarker.createFromOptions(
                        this,
                        PoseLandmarker.PoseLandmarkerOptions.builder()
                            .setBaseOptions(baseOptions(model, delegate))
                            .setNumPoses(1)
                            .setMinPoseDetectionConfidence(minConfidence)
                            .setMinPosePresenceConfidence(minConfidence)
                            .setMinTrackingConfidence(minConfidence)
                            .setRunningMode(RunningMode.VIDEO)
                            .build()
                    )
                    poseInfo = "${model.removeSuffix(".task")}/$delegate"
                    break@loop
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
        }
        engineInfo = "$poseInfo, $handInfo"
        android.util.Log.i("FslHolistic", "MediaPipe engines: $engineInfo")
    }

    /**
     * NV21 -> ARGB Bitmap directly (no JPEG round-trip), rotated by the sensor
     * orientation so it is upright.
     */
    /**
     * YUV_420_888 planes (with row / pixel strides, as delivered by the camera)
     * -> ARGB Bitmap, rotated upright. One pass, no intermediate NV21 copy.
     */
    private fun yuv420ToUprightBitmap(
        yP: ByteArray, uP: ByteArray, vP: ByteArray, width: Int, height: Int,
        yRowStride: Int, uvRowStride: Int, uvPixelStride: Int, rotation: Int
    ): Bitmap? {
        return try {
            // Rotation is applied while writing each pixel (no second full-frame
            // Bitmap + Matrix copy), and the pixel buffer is reused between
            // frames (convertWorker is single-threaded; createBitmap copies it).
            // This removed ~1.4 MB of garbage and one 720x480 copy per frame.
            val rot = ((rotation % 360) + 360) % 360
            val outW = if (rot == 90 || rot == 270) height else width
            val outH = if (rot == 90 || rot == 270) width else height
            val n = width * height
            if (pixelBuffer.size != n) pixelBuffer = IntArray(n)
            val argb = pixelBuffer
            for (j in 0 until height) {
                val yRow = j * yRowStride
                val uvRow = (j shr 1) * uvRowStride
                // Destination index of (i = 0, j) and its step per +1 in i.
                var dst: Int
                val step: Int
                when (rot) {
                    90 -> { dst = (outW - 1 - j); step = outW }              // (x=h-1-j, y=i)
                    180 -> { dst = (outH - 1 - j) * outW + (outW - 1); step = -1 } // (x=w-1-i, y=h-1-j)
                    270 -> { dst = (outH - 1) * outW + j; step = -outW }     // (x=j, y=w-1-i)
                    else -> { dst = j * outW; step = 1 }
                }
                for (i in 0 until width) {
                    val uvIndex = uvRow + (i shr 1) * uvPixelStride
                    val y = (yP[yRow + i].toInt() and 0xFF) - 16
                    val u = (uP[uvIndex].toInt() and 0xFF) - 128
                    val v = (vP[uvIndex].toInt() and 0xFF) - 128
                    val y1192 = if (y < 0) 0 else 1192 * y
                    var r = y1192 + 1634 * v
                    var g = y1192 - 833 * v - 400 * u
                    var b = y1192 + 2066 * u
                    r = if (r < 0) 0 else if (r > 262143) 262143 else r
                    g = if (g < 0) 0 else if (g > 262143) 262143 else g
                    b = if (b < 0) 0 else if (b > 262143) 262143 else b
                    argb[dst] = -0x1000000 or
                        ((r shl 6) and 0xFF0000) or ((g shr 2) and 0xFF00) or ((b shr 10) and 0xFF)
                    dst += step
                }
            }
            Bitmap.createBitmap(argb, outW, outH, Bitmap.Config.ARGB_8888)
        } catch (e: Exception) {
            null
        }
    }

    private fun yuvToUprightBitmap(nv21: ByteArray, width: Int, height: Int, rotation: Int): Bitmap? {
        return try {
            val argb = IntArray(width * height)
            val frameSize = width * height
            for (j in 0 until height) {
                val uvRow = frameSize + (j shr 1) * width
                for (i in 0 until width) {
                    val y = (nv21[j * width + i].toInt() and 0xFF) - 16
                    val uvIndex = uvRow + (i and 1.inv())
                    val v = (nv21[uvIndex].toInt() and 0xFF) - 128
                    val u = (nv21[uvIndex + 1].toInt() and 0xFF) - 128
                    val y1192 = if (y < 0) 0 else 1192 * y
                    var r = y1192 + 1634 * v
                    var g = y1192 - 833 * v - 400 * u
                    var b = y1192 + 2066 * u
                    r = r.coerceIn(0, 262143); g = g.coerceIn(0, 262143); b = b.coerceIn(0, 262143)
                    argb[j * width + i] = -0x1000000 or
                        ((r shl 6) and 0xFF0000) or ((g shr 2) and 0xFF00) or ((b shr 10) and 0xFF)
                }
            }
            val raw = Bitmap.createBitmap(argb, width, height, Bitmap.Config.ARGB_8888)
            if (rotation % 360 == 0) return raw
            val m = Matrix().apply { postRotate(rotation.toFloat()) }
            val rotated = Bitmap.createBitmap(raw, 0, 0, raw.width, raw.height, m, true)
            if (rotated != raw) raw.recycle()
            rotated
        } catch (e: Exception) {
            null
        }
    }

    private fun processHolistic(bitmap: Bitmap): Map<String, Any?> {
        // VIDEO mode requires strictly increasing timestamps.
        var ts = SystemClock.uptimeMillis()
        if (ts <= lastTimestampMs) ts = lastTimestampMs + 1
        lastTimestampMs = ts

        val imageWidth = bitmap.width
        val imageHeight = bitmap.height
        val mpImage = BitmapImageBuilder(bitmap).build()
        var handMs = 0L
        val handFuture = handWorker.submit<HandLandmarkerResult?> {
            val h0 = SystemClock.uptimeMillis()
            val r = handLandmarker?.detectForVideo(mpImage, ts)
            handMs = SystemClock.uptimeMillis() - h0
            r
        }
        frameCount++
        val runPose = lastPose == null || lastPoseMs < 45 || frameCount % 2 == 0L
        var freshPose: List<NormalizedLandmark>? = null
        if (runPose) {
            val p0 = SystemClock.uptimeMillis()
            freshPose = poseLandmarker?.detectForVideo(mpImage, ts)?.landmarks()?.firstOrNull()
            lastPoseMs = SystemClock.uptimeMillis() - p0
            lastPose = freshPose
        }
        // Skipped frames reuse the last pose (shoulders / nose barely move
        // between two frames; the hand features use the hands' own wrists).
        // Every frame therefore carries a pose: the API client rejects captures
        // with pose on fewer than half of the frames (minPoseCoverage).
        val pose: List<NormalizedLandmark>? = if (runPose) freshPose else lastPose
        val handResult = handFuture.get()
        if (frameCount % 15 == 0L) {
            android.util.Log.d("FslPerf", "$engineInfo ${imageWidth}x$imageHeight pose=${if (runPose) lastPoseMs else -1}ms hands=${handMs}ms total=${SystemClock.uptimeMillis() - ts}ms")
        }
        mpImage.close()
        bitmap.recycle()

        val out = DoubleArray(68 * 3)
        fun put(slot: Int, x: Double, y: Double, z: Double) {
            out[slot * 3] = x; out[slot * 3 + 1] = y; out[slot * 3 + 2] = z
        }

        val hasPose = pose != null && pose.size >= 25
        if (hasPose) {
            for (i in 11..24) {
                val p = pose!![i]
                put(i - 11, p.x().toDouble(), p.y().toDouble(), p.z().toDouble())
            }
            putFace(pose!!, ::put)
        }

        // Holistic decides left/right from the pose wrists (15 = left, 16 = right).
        var hasLeft = false
        var hasRight = false
        val hands = handResult?.landmarks().orEmpty().filter { it.size == 21 }
        val assigned = arrayOfNulls<List<NormalizedLandmark>>(2) // 0 = left, 1 = right
        if (hands.isNotEmpty()) {
            if (hasPose) {
                val lw = pose!![15]
                val rw = pose[16]
                fun d(a: NormalizedLandmark, b: NormalizedLandmark): Double {
                    val dx = (a.x() - b.x()).toDouble()
                    val dy = (a.y() - b.y()).toDouble()
                    return dx * dx + dy * dy
                }
                if (hands.size == 1) {
                    val w = hands[0][0]
                    assigned[if (d(w, lw) <= d(w, rw)) 0 else 1] = hands[0]
                } else {
                    val a = hands[0]; val b = hands[1]
                    val straight = d(a[0], lw) + d(b[0], rw)
                    val swapped = d(b[0], lw) + d(a[0], rw)
                    if (straight <= swapped) { assigned[0] = a; assigned[1] = b }
                    else { assigned[0] = b; assigned[1] = a }
                }
            } else {
                // No pose: MediaPipe handedness assumes a mirrored (selfie) image,
                // and ours is un-mirrored, so its "Left" is the signer's right.
                val handedness = handResult?.handedness().orEmpty()
                hands.forEachIndexed { i, h ->
                    val label = handedness.getOrNull(i)?.firstOrNull()?.categoryName() ?: ""
                    val slot = if (label.equals("Left", ignoreCase = true)) 1 else 0
                    if (assigned[slot] == null) assigned[slot] = h
                }
            }
        }
        assigned.forEachIndexed { slot, h ->
            if (h == null) return@forEachIndexed
            if (slot == 0) hasLeft = true else hasRight = true
            val base = if (slot == 0) 14 else 35
            h.forEachIndexed { i, p -> put(base + i, p.x().toDouble(), p.y().toDouble(), p.z().toDouble()) }
        }

        // Raw landmarks for the v4 server pipeline (/v1/predict_raw):
        // all 33 pose points as [x, y, visibility] (the server's nose /
        // occlusion repair needs visibility) and each hand as 21 x [x, y, z],
        // left = the signer's own left (assigned from the pose wrists above).
        // All normalised to the upright, UN-mirrored frame.
        val pose33: List<List<Double>>? = if (pose != null && pose.size >= 33) {
            pose.take(33).map { p ->
                listOf(p.x().toDouble(), p.y().toDouble(), p.visibility().orElse(0f).toDouble())
            }
        } else null
        fun hand21(h: List<NormalizedLandmark>?): List<List<Double>>? =
            h?.map { p -> listOf(p.x().toDouble(), p.y().toDouble(), p.z().toDouble()) }

        return mapOf(
            "landmarks" to out.toList(),
            "hasPose" to hasPose,
            "hasLeft" to hasLeft,
            "hasRight" to hasRight,
            "pose33" to pose33,
            "leftHand" to hand21(assigned[0]),
            "rightHand" to hand21(assigned[1]),
            // Upright frame size (the server scales x by width / height).
            "imageWidth" to imageWidth,
            "imageHeight" to imageHeight,
            "engine" to engineInfo,
            "processMs" to (SystemClock.uptimeMillis() - ts),
        )
    }

    /**
     * No face-mesh model is bundled, so the 12 face points are approximated from
     * the pose's face landmarks (0 nose, 2/5 eyes, 3/6 outer eye corners,
     * 7/8 ears, 9/10 mouth corners). Face-mesh z is relative to the head centre,
     * so z is re-based on the ears' depth.
     */
    private fun putFace(pose: List<NormalizedLandmark>, put: (Int, Double, Double, Double) -> Unit) {
        fun v(i: Int) = doubleArrayOf(pose[i].x().toDouble(), pose[i].y().toDouble(), pose[i].z().toDouble())
        val headZ = (pose[7].z() + pose[8].z()) / 2.0
        val eyeMid = DoubleArray(3) { (v(2)[it] + v(5)[it]) / 2.0 }
        val mouthMid = DoubleArray(3) { (v(9)[it] + v(10)[it]) / 2.0 }
        val down = DoubleArray(3) { mouthMid[it] - eyeMid[it] } // eye line -> mouth line
        fun along(t: Double) = DoubleArray(3) { eyeMid[it] + down[it] * t }

        // Order = FACE_INDICES [1, 33, 61, 199, 263, 291, 0, 17, 10, 152, 234, 454]
        val pts = listOf(
            v(0),         // 1   nose tip
            v(6),         // 33  right eye, outer corner
            v(10),        // 61  right mouth corner
            along(1.65),  // 199 chin (below lower lip)
            v(3),         // 263 left eye, outer corner
            v(9),         // 291 left mouth corner
            along(0.9),   // 0   upper lip centre
            along(1.1),   // 17  lower lip centre
            along(-1.25), // 10  forehead
            along(1.9),   // 152 chin bottom
            v(8),         // 234 right face edge (ear)
            v(7),         // 454 left face edge (ear)
        )
        pts.forEachIndexed { i, p -> put(56 + i, p[0], p[1], p[2] - headZ) }
    }

    override fun onDestroy() {
        worker.execute {
            handLandmarker?.close()
            poseLandmarker?.close()
        }
        convertWorker.shutdown()
        worker.shutdown()
        handWorker.shutdown()
        super.onDestroy()
    }
}
