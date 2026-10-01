import 'package:sqflite/sqflite.dart';

import 'banco.dart';
import 'modelos.dart';

/// Consultas ao texto bíblico (banco `biblia.db`).
class Biblia {
  Biblia._();
  static final Biblia instancia = Biblia._();

  Database get _db => Banco.instancia.biblia;

  List<Versao>? _versoes;
  List<Livro>? _livros;

  Future<List<Versao>> versoes() async => _versoes ??= [
    for (final r in await _db.rawQuery(
      'SELECT id, sigla, nome FROM versao ORDER BY ordem, sigla',
    ))
      Versao(r['id'] as int, r['sigla'] as String, r['nome'] as String),
  ];

  Future<List<Livro>> livros() async => _livros ??= [
    for (final r in await _db.rawQuery(
      'SELECT numero, nome, abreviacao, testamento, capitulos FROM livro '
      'ORDER BY numero',
    ))
      Livro(
        r['numero'] as int,
        r['nome'] as String,
        r['abreviacao'] as String,
        r['testamento'] as int,
        r['capitulos'] as int,
      ),
  ];

  Future<Livro> livro(int numero) async => (await livros())[numero - 1];

  Future<List<Versiculo>> capitulo(int versao, int livro, int capitulo) async =>
      [
        for (final r in await _db.rawQuery(
          'SELECT versiculo, texto FROM versiculo '
          'WHERE versao=? AND livro=? AND capitulo=? ORDER BY versiculo',
          [versao, livro, capitulo],
        ))
          Versiculo(r['versiculo'] as int, r['texto'] as String),
      ];

  /// Os versículos de um intervalo `ini..fim` (chaves capítulo*1000+versículo)
  /// — para mostrar o texto de uma referência cruzada. Capítulo inteiro
  /// (`fim % 1000 == 999`) é limitado a [limite] versículos.
  Future<List<(int, int, String)>> intervalo(
    int versao,
    int livro,
    int ini,
    int fim, {
    int limite = 12,
  }) async {
    final rows = await _db.rawQuery(
      'SELECT capitulo, versiculo, texto FROM versiculo '
      'WHERE versao=? AND livro=? AND capitulo*1000+versiculo BETWEEN ? AND ? '
      'ORDER BY capitulo, versiculo LIMIT ?',
      [versao, livro, ini, fim, limite],
    );
    return [
      for (final r in rows)
        (r['capitulo'] as int, r['versiculo'] as int, r['texto'] as String),
    ];
  }

  /// O mesmo versículo em todas as traduções, na ordem de exibição.
  Future<List<(Versao, String)>> comparar(
    int livro,
    int capitulo,
    int versiculo,
  ) async {
    final todas = await versoes();
    final porId = {for (final v in todas) v.id: v};
    final rows = await _db.rawQuery(
      'SELECT x.versao, x.texto FROM versiculo x JOIN versao v ON v.id=x.versao '
      'WHERE x.livro=? AND x.capitulo=? AND x.versiculo=? ORDER BY v.ordem',
      [livro, capitulo, versiculo],
    );
    return [
      for (final r in rows)
        if (porId[r['versao']] != null)
          (porId[r['versao']]!, r['texto'] as String),
    ];
  }

  /// Busca palavras numa tradução. Todas as palavras precisam aparecer
  /// (em qualquer ordem); sem diferença de maiúsculas.
  Future<List<(int, int, int, String)>> buscar(
    int versao,
    String consulta, {
    int? testamento,
    int limite = 300,
  }) async {
    final palavras = consulta
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.length > 1)
        .toList();
    if (palavras.isEmpty) return [];
    final filtros = palavras.map((_) => 'texto LIKE ?').join(' AND ');
    final args = <Object>[versao, ...palavras.map((p) => '%$p%')];
    var extra = '';
    if (testamento != null) {
      extra = testamento == 1 ? ' AND livro <= 39' : ' AND livro >= 40';
    }
    final rows = await _db.rawQuery(
      'SELECT livro, capitulo, versiculo, texto FROM versiculo '
      'WHERE versao=? AND $filtros$extra '
      'ORDER BY livro, capitulo, versiculo LIMIT $limite',
      args,
    );
    return [
      for (final r in rows)
        (
          r['livro'] as int,
          r['capitulo'] as int,
          r['versiculo'] as int,
          r['texto'] as String,
        ),
    ];
  }
}

/// Tira as marcações do texto (`<J>`, `<i>`) — para copiar e compartilhar.
String textoPuro(String texto) => texto.replaceAll(RegExp(r'<[^>]+>'), '');
