allprojects {
    repositories {
        google()
        mavenCentral()
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
