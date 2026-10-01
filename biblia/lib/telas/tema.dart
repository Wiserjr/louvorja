import 'package:flutter/material.dart';

/// Azul-noite com papel claro: sóbrio para leitura longa, e o vermelho das
/// palavras de Jesus continua distinguível nos dois temas.
const _semente = Color(0xFF2F4A73);

ThemeData temaClaro() {
  final cores = ColorScheme.fromSeed(
    seedColor: _semente,
    surface: const Color(0xFFFBF8F2),
  );
  return _base(cores);
}

ThemeData temaEscuro() {
  final cores = ColorScheme.fromSeed(
    seedColor: _semente,
    brightness: Brightness.dark,
  );
  return _base(cores);
}

ThemeData _base(ColorScheme cores) => ThemeData(
  colorScheme: cores,
  useMaterial3: true,
  appBarTheme: AppBarTheme(
    backgroundColor: cores.surface,
    surfaceTintColor: Colors.transparent,
    scrolledUnderElevation: 1,
  ),
  cardTheme: CardThemeData(
    elevation: 0,
    color: cores.surfaceContainerLow,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: cores.outlineVariant.withValues(alpha: 0.6)),
    ),
    margin: const EdgeInsets.symmetric(vertical: 4),
  ),
);

/// Cor das palavras de Jesus.
Color corJesus(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFFFF8A80)
    : const Color(0xFFB71C1C);

/// Cor de destaque do material de Ellen G. White.
Color corEgw(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFFFFCC80)
    : const Color(0xFF8D5A00);
