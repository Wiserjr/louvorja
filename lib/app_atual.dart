import 'package:flutter/services.dart' show appFlavor;

/// Qual dos dois apps este build é (ver `productFlavors` no
/// `android/app/build.gradle.kts`).
///
/// `appFlavor` é constante de compilação: o ramo do outro app sai do binário no
/// tree-shaking, e o Hinários não carrega o código da Bíblia nem das
/// coletâneas on-line. Sem `--flavor` (nos testes, por exemplo) vale o Louvor JA.
const bool soHinarios = appFlavor == 'hinario';
