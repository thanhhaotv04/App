plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.vietnam_map_01"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.vietnam_map_01"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val releaseStoreFile = providers.gradleProperty("releaseStoreFile")
        .orElse(providers.environmentVariable("ANDROID_KEYSTORE_PATH"))
    val releaseStorePassword = providers.gradleProperty("releaseStorePassword")
        .orElse(providers.environmentVariable("ANDROID_KEYSTORE_PASSWORD"))
    val releaseKeyAlias = providers.gradleProperty("releaseKeyAlias")
        .orElse(providers.environmentVariable("ANDROID_KEY_ALIAS"))
    val releaseKeyPassword = providers.gradleProperty("releaseKeyPassword")
        .orElse(providers.environmentVariable("ANDROID_KEY_PASSWORD"))

    signingConfigs {
        create("release") {
            val storePath = releaseStoreFile.orNull
            val storePassword = releaseStorePassword.orNull
            val keyAlias = releaseKeyAlias.orNull
            val keyPassword = releaseKeyPassword.orNull
            if (!storePath.isNullOrBlank() && !storePassword.isNullOrBlank() &&
                !keyAlias.isNullOrBlank() && !keyPassword.isNullOrBlank()) {
                storeFile = file(storePath)
                this.storePassword = storePassword
                this.keyAlias = keyAlias
                this.keyPassword = keyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }

    gradle.taskGraph.whenReady {
        val releaseRequested = allTasks.any { it.name.contains("Release", ignoreCase = true) }
        val configured = releaseStoreFile.orNull?.isNotBlank() == true &&
            releaseStorePassword.orNull?.isNotBlank() == true &&
            releaseKeyAlias.orNull?.isNotBlank() == true &&
            releaseKeyPassword.orNull?.isNotBlank() == true
        if (releaseRequested && !configured) {
            throw GradleException(
                "Release signing is not configured. Set ANDROID_KEYSTORE_PATH, " +
                    "ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS and ANDROID_KEY_PASSWORD."
            )
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
