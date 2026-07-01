plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.openhearth.peckish"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.openhearth.peckish"
        // flutter_gemma / MediaPipe GenAI requires 24 (the Reckon floor).
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    packaging {
        jniLibs {
            // flutter_gemma 0.13.2 bundles MediaPipe/LiteRT-LM native
            // families Peckish never calls — the guess box does TEXT
            // INFERENCE only (verified in Reckon against the plugin's
            // Kotlin source: the text path loads libllm_inference_engine_jni
            // + liblitertlm_jni; everything below is reachable only from
            // classes no code path here touches). Reversible: delete this
            // block to re-bundle everything.
            excludes += "lib/**/libmediapipe_tasks_vision_image_generator_jni.so"
            excludes += "lib/**/libimagegenerator_gpu.so"
            excludes += "lib/**/libmediapipe_tasks_vision_jni.so"
            excludes += "lib/**/libgemma_embedding_model_jni.so"
            excludes += "lib/**/libgecko_embedding_model_jni.so"
            excludes += "lib/**/libtext_chunker_jni.so"
            excludes += "lib/**/libsqlite_vector_store_jni.so"
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
