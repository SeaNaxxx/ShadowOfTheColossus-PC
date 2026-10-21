plugins {
    id("com.android.application")
}

android {
    namespace = "org.sotc.android"
    compileSdk = 37

    defaultConfig {
        applicationId = "org.sotc.android"
        minSdk = 28
        targetSdk = 28
        versionCode = 1
        versionName = "0.1.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
