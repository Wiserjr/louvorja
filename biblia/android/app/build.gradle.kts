import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Chave de assinatura fixa, lida de android/key.properties (fora do git).
//
// A atualização automática só entra por cima se o APK novo for assinado com a
// MESMA chave do instalado — senão o Android recusa, e a única saída é
// desinstalar, o que apaga os livros baixados e as marcações. Sem
// key.properties o release sai com a chave de debug da máquina que compilou:
// funciona enquanto se publicar sempre do mesmo PC. Ver "Chave de assinatura"
// no README.
val chave = Properties().apply {
    val arquivo = rootProject.file("key.properties")
    if (arquivo.exists()) arquivo.inputStream().use { load(it) }
}

android {
    namespace = "br.com.wisejr.bibliaestudo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "br.com.wisejr.bibliaestudo"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Com --split-per-abi o Flutter soma 1000 × arquitetura ao número do
        // pubspec; o manifesto de atualização publica a base (ver
        // lib/dados/atualizacao.dart, versaoBase).
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (chave.getProperty("storeFile") != null) {
            create("release") {
                storeFile = file(chave.getProperty("storeFile"))
                storePassword = chave.getProperty("storePassword")
                keyAlias = chave.getProperty("keyAlias")
                keyPassword = chave.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
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
