import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// App paralelo: `flutter build apk -P paralelo=true` gera um segundo app, com
// outro identificador e outro nome, que se instala AO LADO do Louvor JA em vez
// de substituí-lo. Cada um fica com seus próprios ajustes e downloads. Sem a
// opção, o build é exatamente o de sempre.
val paralelo = project.findProperty("paralelo")?.toString() == "true"

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
        applicationId =
            if (paralelo) "br.com.wisejr.louvorja.hinarios" else "br.com.wisejr.louvorja"
        manifestPlaceholders["rotulo"] = if (paralelo) "Hinários" else "louvorja"
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
