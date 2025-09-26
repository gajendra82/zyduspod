import java.io.File
import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile: File = rootProject.file("key.properties")
val keystoreProperties: Properties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        FileInputStream(keystorePropertiesFile).use { fis -> load(fis) }
    }
}
fun prop(key: String): String? = keystoreProperties.getProperty(key)

android {
    namespace = "com.globalspace.zyduspod"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.globalspace.zyduspod"
        minSdk = 30
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Create signing config only if key.properties exists
    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                // use non-null asserted prop(...) because we know keys exist in file
                storeFile = file(prop("storeFile")!!)
                storePassword = prop("storePassword")
                keyAlias = prop("keyAlias")
                keyPassword = prop("keyPassword")
            }
        }
    }

    buildTypes {
        getByName("release") {
            // enable code shrinking (R8) — required when shrinkResources = true
            isMinifyEnabled = true

            // enable resource shrinking
            isShrinkResources = true

            // Use optimized default proguard file + your rules
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )

            signingConfig = signingConfigs.findByName("release")
        }
    }

}

flutter {
    source = "../.."
}
