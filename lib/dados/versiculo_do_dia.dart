import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Calendário do versículo do dia.
///
/// O arquivo em `assets/versiculo_do_dia.json` guarda apenas **coordenadas** —
/// livro, capítulo e versículo de cada um dos 366 dias — nunca o texto. Quem
/// escolheu essas passagens foi a YouVersion; o texto sai do banco offline, na
/// tradução que o usuário estiver usando.
///
/// É essa separação que faz o recurso caber aqui: sem rede no aparelho, sem
/// chave de API dentro do APK, e valendo para todas as traduções em vez de uma
/// só. O calendário é buscado uma vez no PC por `ferramentas/votd.py`.
class ReferenciaDoDia {
  const ReferenciaDoDia({
    required this.dia,
    required this.livro,
    required this.capitulo,
    required this.versiculo,
    required this.ate,
  });

  /// Dia do ano, de 1 a 366.
  final int dia;

  /// `biblia_livro.numero`, de 1 (Gênesis) a 66 (Apocalipse).
  final int livro;

  final int capitulo;

  /// Primeiro versículo da passagem.
  final int versiculo;

  /// Último versículo. Igual a [versiculo] quando a passagem é de um só.
  final int ate;

  bool get temIntervalo => ate > versiculo;

  factory ReferenciaDoDia.doMapa(Map<String, Object?> m) => ReferenciaDoDia(
    dia: m['dia']! as int,
    livro: m['livro']! as int,
    capitulo: m['capitulo']! as int,
    versiculo: m['versiculo']! as int,
    ate: m['ate']! as int,
  );
}

class VersiculoDoDia {
  const VersiculoDoDia._();

  static const _asset = 'assets/versiculo_do_dia.json';

  static Map<int, ReferenciaDoDia>? _calendario;

  /// Dia do ano de [d], de 1 a 366.
  ///
  /// Normaliza para data pura de propósito: `difference` sobre um `DateTime`
  /// com hora erraria por um dia nas viradas de horário de verão.
  static int diaDoAno(DateTime d) =>
      DateTime(d.year, d.month, d.day).difference(DateTime(d.year, 1, 1)).inDays +
      1;

  static Future<Map<int, ReferenciaDoDia>> _carregar() async {
    final pronto = _calendario;
    if (pronto != null) return pronto;

    var mapa = <int, ReferenciaDoDia>{};
    try {
      final bruto = jsonDecode(await rootBundle.loadString(_asset));
      final dias = (bruto as Map<String, Object?>)['dias'] as List<Object?>;
      mapa = {
        for (final d in dias.cast<Map<String, Object?>>())
          d['dia']! as int: ReferenciaDoDia.doMapa(d),
      };
    } catch (e) {
      // Silencioso de propósito: sem o asset, o cartão simplesmente não
      // aparece — não é motivo para derrubar a aba Bíblia.
      debugPrint('versiculo do dia indisponivel: $e');
    }

    _calendario = mapa;
    return mapa;
  }

  static Future<ReferenciaDoDia?> de(DateTime data) async =>
      (await _carregar())[diaDoAno(data)];

  static Future<ReferenciaDoDia?> hoje() => de(DateTime.now());
}
