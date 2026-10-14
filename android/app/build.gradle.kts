import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

val requestedReleaseBuild = gradle.startParameter.taskNames.any {
    it.contains("Release", ignoreCase = true)
}
if (requestedReleaseBuild && !hasReleaseKeystore) {
    throw GradleException(
        "Release builds require android/key.properties and android/app/upload-keystore.jks. " +
            "See docs/google-play-release.md."
    )
}

android {
    namespace = "com.carcare.carcare"
    compileSdk = 36
    // ปลั๊กอินหลายตัว (sqflite, notifications, permission_handler ฯลฯ) ขอ NDK 27
    // ต้องตั้งเป็นเวอร์ชันสูงสุดที่มีใครขอ เพราะ NDK เข้ากันได้ย้อนหลัง
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // flutter_local_notifications ต้องใช้ API ของ java.time บน Android รุ่นเก่า
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.carcare.carcare"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasReleaseKeystore) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")

            // ML Kit อ้างถึงคลาสของชุดอักษรที่เราไม่ได้ใส่มา ต้องบอก R8 ให้ข้าม
            // ไม่งั้น build release ไม่ผ่าน (ดูเหตุผลใน proguard-rules.pro)
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
