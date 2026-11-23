import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ── App version (Google Play) ──────────────────────────────────────────
// Before each new upload to Google Play:
//   • appVersionCode: +1 every time (Play refuses a code it has already seen)
//   • appVersionName: the version people see in the store (e.g. 1.0.1)
// These override the version in pubspec.yaml for Android.
val appVersionCode = 10
val appVersionName = "10.0.0"

// Release signing with the upload key: android/key.properties (git-ignored)
// points at android/upload-keystore.jks. Without it (another machine, CI)
// release builds fall back to the debug key — fine for `flutter run
// --release`, but Google Play refuses such a bundle.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}

android {
    namespace = "com.alldocs.app"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
        // Required by flutter_local_notifications.
        isCoreLibraryDesugaringEnabled = true
    }
    // For Kotlin projects
    kotlinOptions {
        jvmTarget = "1.8"
    }

    defaultConfig {
        applicationId = "com.alldocs.app"
        minSdk = flutter.minSdkVersion
        // Google Play requires API 36 for new apps and updates (since 31/08/2026).
        targetSdk = 36
        versionCode = appVersionCode
        versionName = appVersionName
        // OAuth redirect scheme for Dropbox sign-in (flutter_appauth).
        // Must match CloudConfig.redirectUri on the Dart side.
        manifestPlaceholders["appAuthRedirectScheme"] = "com.alldocs.app"
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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
    // Required by flutter_local_notifications (isCoreLibraryDesugaringEnabled above).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // OCR (alldocs/ocr channel in MainActivity). iOS uses Apple Vision.
    implementation("com.google.mlkit:text-recognition:16.0.1")
}
