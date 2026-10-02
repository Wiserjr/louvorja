import 'package:sqflite/sqflite.dart';

import 'banco.dart';
import 'estudo.dart';
import 'modelos.dart';
import 'temas.dart';

/// Os quatro evangelhos, na ordem das colunas do guia.
const evangelhos = [40, 41, 42, 43];

class EventoSinotico {
  const EventoSinotico({
    required this.id,
    required this.periodo,
    required this.titulo,
    required this.passagens,
    required this.leituras,
  });

  final int id;
  final String periodo;
  final String titulo;

  /// Passagens por evangelho (40 Mateus ... 43 João). Um evangelho pode ter
  /// mais de um trecho ("Mateus 26:1-5, 14-16").
  final Map<int, List<Passagem>> passagens;

  /// Capítulos de Ellen G. White que narram o episódio.
  final List<LeituraEgw> leituras;

  int get quantosEvangelhos => passagens.length;
}

/// Guia sinótico (harmonia dos evangelhos): ferramentas/sinotico.json.
class Sinotico {
  Sinotico._();
  static final Sinotico instancia = Sinotico._();

  Database get _db => Banco.instancia.estudo;

  List<EventoSinotico>? _eventos;

  /// Todos os episódios, em ordem cronológica (são poucos: cabem na memória).
  Future<List<EventoSinotico>> eventos() async {
    if (_eventos != null) return _eventos!;
    final obras = await Estudo.instancia.obras();
    final passagens = <int, Map<int, List<Passagem>>>{};
    for (final r in await _db.rawQuery(
      'SELECT evento, livro, ini, fim FROM sinotico_ref '
      'ORDER BY evento, livro, ordem',
    )) {
      passagens
          .putIfAbsent(r['evento'] as int, () => {})
          .putIfAbsent(r['livro'] as int, () => [])
          .add(Passagem(r['livro'] as int, r['ini'] as int, r['fim'] as int));
    }
    final leituras = <int, List<LeituraEgw>>{};
    for (final r in await _db.rawQuery(
      'SELECT l.evento, l.obra, l.pagina, c.titulo FROM sinotico_leitura l '
      'JOIN capitulo c ON c.id = l.capitulo ORDER BY l.evento, l.ordem',
    )) {
      final obra = obras[r['obra']];
      if (obra == null) continue;
      leituras
          .putIfAbsent(r['evento'] as int, () => [])
          .add(LeituraEgw(obra, r['titulo'] as String, r['pagina'] as int, 0));
    }
    final rows = await _db.rawQuery(
      'SELECT e.id, e.titulo, s.titulo AS periodo FROM sinotico_evento e '
      'JOIN sinotico_secao s ON s.id = e.secao ORDER BY e.id',
    );
    return _eventos = [
      for (final r in rows)
        EventoSinotico(
          id: r['id'] as int,
          periodo: r['periodo'] as String,
          titulo: r['titulo'] as String,
          passagens: passagens[r['id']] ?? const {},
          leituras: leituras[r['id']] ?? const [],
        ),
    ];
  }

  /// Episódios que contêm o versículo — o painel de estudo mostra "este
  /// episódio nos outros evangelhos".
  Future<List<EventoSinotico>> doVersiculo(
    int livro,
    int capitulo,
    int versiculo,
  ) async {
    if (!evangelhos.contains(livro)) return const [];
    final k = chave(capitulo, versiculo);
    final ids = {
      for (final r in await _db.rawQuery(
        'SELECT evento FROM sinotico_ref WHERE livro=? AND ini<=? AND fim>=?',
        [livro, k, k],
      ))
        r['evento'] as int,
    };
    if (ids.isEmpty) return const [];
    return [
      for (final e in await eventos())
        if (ids.contains(e.id)) e,
    ];
  }
}
