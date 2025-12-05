import java.io.File
import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
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
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
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
        multiDexEnabled = true

    }

    // Create signing config only if key.properties exists
    signingConfigs {
        create("release") {
            // Prefer values from key.properties if available, otherwise fall back to an absolute path.
            val storeFileProp = prop("storeFile")
            val storeFilePath = storeFileProp ?: "C:/Users/gajen/Downloads/zydus_alias.keystore"

            val sf = file(storeFilePath)
            if (!sf.exists()) {
                throw GradleException("Keystore file not found at: $sf. Update storeFile in key.properties or move keystore.")
            }

            // Kotlin DSL style assignments:
            storeFile = sf
            storePassword = prop("storePassword") ?: "welcome"
            keyAlias = prop("keyAlias") ?: "zydus_alias"
            keyPassword = prop("keyPassword") ?: "welcome"
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
