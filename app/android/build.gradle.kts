allprojects {
    repositories {
        google()
        mavenCentral()
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

// AGP 8 requires every module to declare a namespace. flutter_bluetooth_serial
// 0.4.0 predates that — inject its manifest package and lift its pinned
// compileSdk 30 (pre-lStar resources) to the app's level AFTER the plugin's
// own build.gradle configures itself (scoped to that one project only).
subprojects {
    if (project.name == "flutter_bluetooth_serial") {
        project.afterEvaluate {
            val ext = project.extensions.findByName("android")
            if (ext is com.android.build.gradle.LibraryExtension) {
                ext.namespace = "io.github.edufolly.flutterbluetoothserial"
                ext.compileSdkVersion(36)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
