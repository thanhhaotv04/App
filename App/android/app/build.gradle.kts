plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.thanhhao.esp32_navride"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.thanhhao.esp32_monitor"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    dependencies {
        implementation("net.osmand:android-aidl-lib:5.4@aar")
        testImplementation("junit:junit:4.13.2")
        testImplementation("org.json:json:20240303")
        testImplementation("org.mockito:mockito-inline:5.2.0")
        // Mockito's older defaults cannot instrument the JDK 25 used locally.
        testImplementation("net.bytebuddy:byte-buddy:1.18.2")
        testImplementation("net.bytebuddy:byte-buddy-agent:1.18.2")
        testImplementation("org.objenesis:objenesis:3.4")
    }

    buildTypes {
        release {
            proguardFiles("proguard-rules.pro")
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
