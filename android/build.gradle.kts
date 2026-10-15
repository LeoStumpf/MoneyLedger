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
// Some plugins (e.g. file_picker 8.x: compileSdk 34) compile against an older
// SDK than their dependencies require (flutter_plugin_android_lifecycle needs
// 36), which fails :checkReleaseAarMetadata. Raise Android library plugins to
// at least compileSdk 36.
subprojects {
    val raiseCompileSdk = {
        extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)?.let { ext ->
            if ((ext.compileSdk ?: 0) < 36) ext.compileSdk = 36
        }
    }
    if (state.executed) raiseCompileSdk() else afterEvaluate { raiseCompileSdk() }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
