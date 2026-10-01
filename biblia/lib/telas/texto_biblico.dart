import 'package:flutter/material.dart';

/// Converte o texto de um versículo em spans: `<J>…</J>` (palavras de Jesus,
/// em vermelho se [vermelho]) e `<i>…</i>` (palavras acrescentadas pelos
/// tradutores, em itálico). Marcação desconhecida é descartada.
List<InlineSpan> spansDoTexto(
  String texto, {
  required TextStyle estilo,
  required Color corJesus,
  bool vermelho = true,
}) {
  final spans = <InlineSpan>[];
  var jesus = false;
  var italico = false;
  final marca = RegExp(r'<(/?)([A-Za-z]+)>');
  var pos = 0;
  void emitir(String s) {
    if (s.isEmpty) return;
    var e = estilo;
    if (jesus && vermelho) e = e.copyWith(color: corJesus);
    if (italico) e = e.copyWith(fontStyle: FontStyle.italic);
    spans.add(TextSpan(text: s, style: e));
  }

  for (final m in marca.allMatches(texto)) {
    emitir(texto.substring(pos, m.start));
    final fecha = m.group(1) == '/';
    switch (m.group(2)!.toUpperCase()) {
      case 'J':
        jesus = !fecha;
      case 'I':
        italico = !fecha;
    }
    pos = m.end;
  }
  emitir(texto.substring(pos));
  return spans;
}
