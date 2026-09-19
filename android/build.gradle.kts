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
// 部分插件（如 amap_map）在自己的 build.gradle 里写死了较低的 compileSdk，
// 而 flutter_plugin_android_lifecycle 要求依赖方至少编译到 36，
// 会在 checkReleaseAarMetadata 阶段失败。这里统一抬到与 app 一致。
//
// 下面的 evaluationDependsOn(":app") 会让子项目提前完成评估，
// 所以不能用 afterEvaluate（会报 project is already evaluated），
// 改成在 Android library 插件应用时立即修改扩展。
subprojects {
    plugins.withId("com.android.library") {
        val libraryExtension =
            extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)
        if (libraryExtension != null && (libraryExtension.compileSdk ?: 0) < 36) {
            libraryExtension.compileSdk = 36
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
