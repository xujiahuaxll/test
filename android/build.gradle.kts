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

// 部分插件（如 amap_map）在自己的 build.gradle 里写死了较低的 compileSdk，
// 而 flutter_plugin_android_lifecycle 要求依赖方至少编译到 36，
// 会在 checkReleaseAarMetadata 阶段失败。这里统一抬到与 app 一致。
subprojects {
    afterEvaluate {
        extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)
            ?.let { libraryExtension ->
                if (libraryExtension.compileSdk?.let { it < 36 } != false) {
                    libraryExtension.compileSdk = 36
                }
            }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
