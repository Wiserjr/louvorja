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
// desinstalar, o que apaga as músicas baixadas. Sem key.properties o release
// sai com a chave de debug da máquina que compilou: funciona enquanto se
// publicar sempre do mesmo PC, e quebra para todo mundo no dia em que o PC
// mudar. Ver "Chave de assinatura" no README.
val chave = Properties().apply {
    val arquivo = rootProject.file("key.properties")
    if (arquivo.exists()) arquivo.inputStream().use { load(it) }
}

android {
    namespace = "br.com.wisejr.louvorja"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "br.com.wisejr.louvorja"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Dois apps do mesmo código, que se instalam lado a lado (identificadores
    // diferentes, cada um com seus ajustes e downloads):
    //
    //   louvorja  o app completo: 75 álbuns, Bíblia, coletâneas on-line.
    //   hinario   só os dois hinários, para quem tem pouco espaço. Leva um
    //             catálogo de ~1 MB em vez de 27 MB (ver pubspec.yaml e
    //             ferramentas/build_hinario.py).
    //
    // flutter build apk --flavor louvorja   /   --flavor hinario
    flavorDimensions += "app"
    productFlavors {
        create("louvorja") {
            dimension = "app"
            applicationId = "br.com.wisejr.louvorja"
            manifestPlaceholders["rotulo"] = "louvorja"
        }
        create("hinario") {
            dimension = "app"
            applicationId = "br.com.wisejr.louvorja.hinarios"
            manifestPlaceholders["rotulo"] = "Hinários"
        }
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
