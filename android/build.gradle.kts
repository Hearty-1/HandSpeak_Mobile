allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Force every plugin module (many of which don't set this themselves) onto
// the same JVM target as the app, so Gradle 9 / Kotlin 2.3 don't pick a
// mismatched default (e.g. tflite_flutter's Java 11 vs Kotlin's JDK-22 default).
// Fixes: "Inconsistent JVM-target compatibility detected for tasks
// 'compileDebugJavaWithJavac' (11) and 'compileDebugKotlin' (22)".
subprojects {
    afterEvaluate {
        extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.apply {
            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }
        tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile::class.java).configureEach {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }
    }
}

// Ensure common AndroidX dependencies are available to plugin modules
subprojects {
    plugins.withId("com.android.library") {
        afterEvaluate {
            try {
                dependencies.add("implementation", "androidx.concurrent:concurrent-futures:1.1.0")
            } catch (_: Exception) {
            }
        }
    }
    plugins.withId("com.android.application") {
        afterEvaluate {
            try {
                dependencies.add("implementation", "androidx.concurrent:concurrent-futures:1.1.0")
            } catch (_: Exception) {
            }
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}