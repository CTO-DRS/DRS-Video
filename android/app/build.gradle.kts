plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.drs.drs_video"
    compileSdk = flutter.compileSdkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.drs.drs_video"
        // Android 7.0 (API 24) explicit: guaranteed compatibility floor.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // v1.2.1: arm64-v8a only. The sandbox disk cannot fit a 3-ABI
        // release build; modern devices are arm64 and this still upgrades
        // in place over previous releases (same signing key). Bump back to
        // the full list when building on a roomier machine.
        // v1.14.2 (patch restored): when Flutter drives the build with
        // --split-per-abi, the split config owns the ABI filters and an
        // unconditional ndk.abiFilters here makes AGP fail with
        // "Conflicting configuration" — apply it to universal builds only.
        if (project.findProperty("split-per-abi") == null) {
            ndk {
                abiFilters += listOf("arm64-v8a")
            }
        }
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    dependencies {
        coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
        // On-demand WorkManager configuration (DrsApplication) — work-runtime
        // is otherwise only a plugin-internal dependency and not visible
        // to the app module at compile time.
        implementation("androidx.work:work-runtime:2.9.0")
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            // P5 (reconstructed after env reset, with the field-failure
            // keeps from worklog Task 9): R8 code + resource shrinking.
            // Rule set is deliberately generous — safety over size.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            isMinifyEnabled = true
            // keep.xml protects the resources resolved by name from Dart
            // (notification icon, network security config, file paths).
            isShrinkResources = true
        }
    }

    packaging {
        // Extract native libraries to disk instead of loading them
        // directly from the APK. Maximizes device compatibility (some
        // OEMs / 16 KB-page devices fail to map uncompressed entries);
        // costs extra disk space only.
        jniLibs {
            useLegacyPackaging = true
            // v1.2.1 ships arm64-v8a only. Plugin AARs bundle other ABIs;
            // without this the APK would advertise (partial) v7a/x86_64
            // support and crash on those devices at load time.
            excludes += listOf("lib/armeabi-v7a/**", "lib/x86_64/**", "lib/x86/**")
        }
    }

    lint {
        // Lint is a static-analysis convenience, not part of the release
        // artifact; disabled to fit the constrained build environment.
        checkReleaseBuilds = false
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
