import java.util.Properties
import java.io.FileInputStream

// Release signing key (kept private, not in git): android/key.properties
//   storePassword=...
//   keyPassword=...
//   keyAlias=handspeak
//   storeFile=C:\Users\<you>\handspeak-release.jks
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) load(FileInputStream(f))
}

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.flutter_application_1"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

   compileOptions {
        isCoreLibraryDesugaringEnabled = true // Add this exact line
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

    androidResources {
    noCompress.add("task")
    }

    defaultConfig {
        // Permanent app ID (never change it: installed copies could not update).
        applicationId = "com.techspartan.handspeak"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystoreProperties.isNotEmpty()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // The release key when android/key.properties exists; otherwise the
            // debug key (test builds only, never share those).
            signingConfig = if (keystoreProperties.isNotEmpty()) signingConfigs.getByName("release")
                            else signingConfigs.getByName("debug")
            // Test builds: no R8 shrinking. With the MediaPipe / TFLite / ONNX
            // libraries, R8 needs more memory than this PC has (the build ran
            // 89 min and the Gradle daemon was killed). Turn back on, with
            // proguard-rules.pro, for a store release on a bigger machine.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Added desugaring dependency
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    implementation("androidx.concurrent:concurrent-futures:1.1.0")
    implementation("org.tensorflow:tensorflow-lite-select-tf-ops:+")
    // 0.10.29 (already the version Gradle resolves): has HolisticLandmarker,
    // the training clips' landmark pipeline (MainActivity.kt).
    implementation("com.google.mediapipe:tasks-vision:0.10.29")
}