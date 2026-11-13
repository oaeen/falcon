import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keyProps = Properties().apply {
    rootProject.file("key.properties").takeIf { it.exists() }?.inputStream()?.use { load(it) }
}

val hasWholeReleaseKey =
    listOf("storeFile", "keyAlias").all { !keyProps.getProperty(it).isNullOrBlank() } &&
        listOf("storePassword", "keyPassword").all { !keyProps.getProperty(it).isNullOrEmpty() } &&
        file(keyProps.getProperty("storeFile")).exists()

// Encodes UTC+8 build minute as (year - 2026) * 10^8 + MMDDhhmm when flutter.versionCode <= 1.
fun buildMinuteVersionCode(): Int {
    val t = OffsetDateTime.now(ZoneOffset.ofHours(8))
    return (t.year - 2026) * 100_000_000 +
        t.monthValue * 1_000_000 +
        t.dayOfMonth * 10_000 +
        t.hour * 100 +
        t.minute
}

android {
    namespace = "io.github.falcon.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.github.falcon.app"
        minSdk = 26
        targetSdk = 35
        versionCode = flutter.versionCode.takeIf { it > 1 } ?: buildMinuteVersionCode()
        versionName = flutter.versionName
    }

    packaging {
        // Extract libfalcon_core.so and libbun.so into nativeLibraryDir with executable permissions.
        jniLibs {
            useLegacyPackaging = true
            keepDebugSymbols += listOf("**/libfalcon_core.so", "**/libbun.so")
        }
    }

    signingConfigs {
        if (hasWholeReleaseKey) {
            create("release") {
                storeFile = keyProps.getProperty("storeFile")?.let { file(it) }
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }

    buildTypes {
        debug {
            if (hasWholeReleaseKey) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
        release {
            signingConfig = signingConfigs.getByName(if (hasWholeReleaseKey) "release" else "debug")
        }
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
