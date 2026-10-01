import 'package:sqflite/sqflite.dart';

import 'banco.dart';
import 'modelos.dart';

/// Consultas ao material de estudo (banco `estudo.db`).
class Estudo {
  Estudo._();
  static final Estudo instancia = Estudo._();

  Database get _db => Banco.instancia.estudo;

  Map<int, Obra>? _obras;

  Future<Map<int, Obra>> obras() async => _obras ??= {
    for (final r in await _db.rawQuery('SELECT * FROM obra ORDER BY id'))
      r['id'] as int: Obra.deMapa(r),
  };

  /// Trechos de Ellen G. White e dos pioneiros ligados a um versículo.
  ///
  /// Ordem: primeiro o capítulo que narra a passagem ("Este capítulo é
  /// baseado em..."), depois o comentário versículo a versículo, depois as
  /// citações — das que tratam deste versículo isoladamente para as que o
  /// incluem num intervalo maior, e dentro disso pela prioridade da obra
  /// (série Conflito dos Séculos primeiro).
  Future<List<Trecho>> trechos(int livro, int capitulo, int versiculo) async {
    final k = chave(capitulo, versiculo);
    final todas = await obras();
    final rows = await _db.rawQuery(
      'SELECT t.id, t.obra, t.pagina, t.pagina_original, t.segmentos, '
      '       t.ancora, c.titulo AS capitulo, r.tipo, r.livro, r.ini, r.fim '
      '  FROM ref_obra r '
      '  JOIN trecho t ON t.id = r.trecho '
      '  LEFT JOIN capitulo c ON c.id = t.capitulo '
      ' WHERE r.livro = ? AND r.ini <= ? AND r.fim >= ?',
      [livro, k, k],
    );
    final lista = <Trecho>[];
    final vistos = <int>{};
    for (final r in rows) {
      final id = r['id'] as int;
      if (!vistos.add(id)) continue;
      final obra = todas[r['obra'] as int];
      if (obra == null) continue;
      lista.add(
        Trecho(
          id: id,
          obra: obra,
          pagina: r['pagina'] as int,
          paginaOriginal: r['pagina_original'] as int?,
          segmentos: Trecho.lerSegmentos(r['segmentos'] as String),
          ancora: r['ancora'] as String?,
          capitulo: r['capitulo'] as String?,
          tipo: TipoLigacao.values[r['tipo'] as int],
          livro: r['livro'] as int,
          ini: r['ini'] as int,
          fim: r['fim'] as int,
        ),
      );
    }
    int ordemTipo(TipoLigacao t) => switch (t) {
      TipoLigacao.capitulo => 0,
      TipoLigacao.comentario => 1,
      TipoLigacao.citacao => 2,
    };
    lista.sort((a, b) {
      final t = ordemTipo(a.tipo).compareTo(ordemTipo(b.tipo));
      if (t != 0) return t;
      final la = a.fim - a.ini, lb = b.fim - b.ini;
      // Citação pontual antes de citação de capítulo inteiro.
      final ea = la == 0 ? 0 : (la < 999 ? 1 : 2);
      final eb = lb == 0 ? 0 : (lb < 999 ? 1 : 2);
      if (ea != eb) return ea.compareTo(eb);
      final p = a.obra.prioridade.compareTo(b.obra.prioridade);
      if (p != 0) return p;
      final o = a.obra.id.compareTo(b.obra.id);
      if (o != 0) return o;
      return a.pagina.compareTo(b.pagina);
    });
    return lista;
  }

  /// Quantos trechos de Ellen G. White e dos pioneiros citam cada versículo
  /// do capítulo — o número discreto ao lado do versículo no leitor. Só
  /// conta citação direta e comentário; o capítulo que narra a história toda
  /// apareceria em todos os versículos e não diria nada.
  Future<Map<int, int>> contagem(int livro, int capitulo) async {
    final rows = await _db.rawQuery(
      'SELECT ini, fim FROM ref_obra '
      ' WHERE livro = ? AND tipo != 1 AND ini <= ? AND fim >= ? '
      '   AND fim - ini < 900',
      [livro, chave(capitulo, 999), chave(capitulo, 0)],
    );
    final contagem = <int, int>{};
    for (final r in rows) {
      final ini = r['ini'] as int, fim = r['fim'] as int;
      final de = ini ~/ 1000 < capitulo ? 1 : ini % 1000;
      final ate = fim ~/ 1000 > capitulo ? 200 : fim % 1000;
      for (var v = de; v <= ate; v++) {
        contagem[v] = (contagem[v] ?? 0) + 1;
      }
    }
    return contagem;
  }

  /// Capítulos de Ellen G. White que narram este capítulo bíblico, para o
  /// topo do leitor ("Leia também: O Desejado de Todas as Nações, cap. 12").
  Future<List<Trecho>> narrativas(int livro, int capitulo) async {
    final todos = await trechos(livro, capitulo, 1);
    final extra = <Trecho>[];
    // A narrativa pode começar no meio do capítulo (Gênesis 4:25-6:2).
    final rows = await _db.rawQuery(
      'SELECT DISTINCT ini FROM ref_obra WHERE livro=? AND tipo=1 '
      'AND ini > ? AND ini <= ?',
      [livro, chave(capitulo, 1), chave(capitulo, 999)],
    );
    for (final r in rows) {
      final ini = r['ini'] as int;
      for (final t in await trechos(livro, capitulo, ini % 1000)) {
        if (t.tipo == TipoLigacao.capitulo) extra.add(t);
      }
    }
    final vistos = <int>{};
    return [
      for (final t in [...todos, ...extra])
        if (t.tipo == TipoLigacao.capitulo && vistos.add(t.id)) t,
    ];
  }

  Future<List<RefCruzada>> referencias(
    int livro,
    int capitulo,
    int versiculo,
  ) async {
    final rows = await _db.rawQuery(
      'SELECT livro2, ini2, fim2, votos, tipo FROM ref_cruzada '
      'WHERE livro=? AND ini=? ORDER BY tipo=0, tipo DESC, votos DESC',
      [livro, chave(capitulo, versiculo)],
    );
    return [
      for (final r in rows)
        RefCruzada(
          livro: r['livro2'] as int,
          ini: r['ini2'] as int,
          fim: r['fim2'] as int,
          votos: r['votos'] as int,
          tipo: r['tipo'] as int,
        ),
    ];
  }

  /// Versículos do capítulo que citam o AT (ou são citados no NT), ou têm
  /// passagem paralela — o leitor marca esses versículos.
  Future<Map<int, int>> citacoesDoCapitulo(int livro, int capitulo) async {
    final rows = await _db.rawQuery(
      'SELECT ini, max(tipo) AS tipo FROM ref_cruzada '
      'WHERE livro=? AND ini BETWEEN ? AND ? AND tipo IN (2, 3) GROUP BY ini',
      [livro, chave(capitulo, 0), chave(capitulo, 999)],
    );
    return {for (final r in rows) (r['ini'] as int) % 1000: r['tipo'] as int};
  }

  Future<Introducao?> introducao(int livro) async {
    final rows = await _db.rawQuery('SELECT * FROM introducao WHERE livro=?', [
      livro,
    ]);
    if (rows.isEmpty) return null;
    return Introducao({
      for (final e in rows.first.entries)
        if (e.key != 'livro') e.key: e.value as String?,
    });
  }

  Future<List<Nota>> notas(int livro, int capitulo, int versiculo) async {
    final k = chave(capitulo, versiculo);
    final rows = await _db.rawQuery(
      'SELECT livro, ini, fim, texto FROM nota '
      'WHERE livro=? AND ini<=? AND fim>=? ORDER BY ini',
      [livro, k, k],
    );
    return [
      for (final r in rows)
        Nota(
          r['livro'] as int,
          r['ini'] as int,
          r['fim'] as int,
          r['texto'] as String,
        ),
    ];
  }

  Future<Set<int>> versiculosComNota(int livro, int capitulo) async {
    final rows = await _db.rawQuery(
      'SELECT ini, fim FROM nota WHERE livro=? AND ini<=? AND fim>=?',
      [livro, chave(capitulo, 999), chave(capitulo, 0)],
    );
    // Marca só o primeiro versículo de cada nota.
    return {
      for (final r in rows)
        (r['ini'] as int) ~/ 1000 < capitulo ? 1 : (r['ini'] as int) % 1000,
    };
  }
}
