plugins {
    id("com.android.application")
    id("com.chaquo.python")
}

android {
    namespace = "org.sotc.android"
    compileSdk = 36

    defaultConfig {
        applicationId = "org.sotc.android"
        minSdk = 28
        targetSdk = 28
        versionCode = 1
        versionName = "0.1.0"
        ndk { abiFilters += "arm64-v8a" }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets.getByName("main").jniLibs.srcDir("../../out/android-arm64/jni")
    sourceSets.getByName("main").java.srcDir("../../out/android-arm64/deps/SDL3-3.2.10/android-project/app/src/main/java")
}

chaquopy {
    defaultConfig { version = "3.12" }
    sourceSets {
        getByName("main") { srcDir("../../scripts") }
    }
}

val buildSotcAndroidRuntime by tasks.registering(Exec::class) {
    workingDir = rootProject.projectDir.parentFile
    commandLine("bash", "tools/android/build_android.sh")
}

tasks.named("preBuild").configure {
    dependsOn(buildSotcAndroidRuntime)
}
