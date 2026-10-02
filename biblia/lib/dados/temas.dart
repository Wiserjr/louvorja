import 'package:sqflite/sqflite.dart';

import 'banco.dart';
import 'estudo.dart';
import 'modelos.dart';

class Tema {
  const Tema(this.id, this.categoria, this.titulo, this.resumo);
  final String id;
  final String categoria;
  final String titulo;
  final String? resumo;
}

/// Uma passagem: livro e intervalo `capitulo*1000+versiculo`.
class Passagem {
  const Passagem(this.livro, this.ini, this.fim);
  final int livro;
  final int ini;
  final int fim;

  Posicao get posicao =>
      Posicao(livro, ini ~/ 1000, ini % 1000 == 0 ? null : ini % 1000);
}

/// Capítulo de Ellen G. White que cita vários versículos de um tema.
class LeituraEgw {
  const LeituraEgw(this.obra, this.capitulo, this.pagina, this.versiculos);
  final Obra obra;
  final String capitulo;

  /// Página do PDF (a partir de 0) onde o capítulo começa.
  final int pagina;

  /// Quantos versículos do tema o capítulo cita.
  final int versiculos;
}

class EstudoBiblico {
  const EstudoBiblico(this.id, this.titulo, this.introducao);
  final String id;
  final String titulo;
  final String? introducao;
}

class Pergunta {
  const Pergunta(this.texto, this.passagem);
  final String texto;
  final Passagem passagem;
}

/// Índice temático e estudos bíblicos (ferramentas/temas.json).
class Temas {
  Temas._();
  static final Temas instancia = Temas._();

  Database get _db => Banco.instancia.estudo;

  Future<List<Tema>> temas() async => [
    for (final r in await _db.rawQuery('SELECT * FROM tema ORDER BY ordem'))
      Tema(
        r['id'] as String,
        r['categoria'] as String,
        r['titulo'] as String,
        r['resumo'] as String?,
      ),
  ];

  Future<List<Passagem>> passagens(String tema) async => [
    for (final r in await _db.rawQuery(
      'SELECT livro, ini, fim FROM tema_ref WHERE tema=? ORDER BY ordem',
      [tema],
    ))
      Passagem(r['livro'] as int, r['ini'] as int, r['fim'] as int),
  ];

  Future<List<LeituraEgw>> leituras(String tema) async {
    final obras = await Estudo.instancia.obras();
    final rows = await _db.rawQuery(
      'SELECT e.obra, c.titulo, e.pagina, e.versiculos FROM tema_egw e '
      'JOIN capitulo c ON c.id = e.capitulo WHERE e.tema=? ORDER BY e.ordem',
      [tema],
    );
    return [
      for (final r in rows)
        if (obras[r['obra']] != null)
          LeituraEgw(
            obras[r['obra']]!,
            r['titulo'] as String,
            r['pagina'] as int,
            r['versiculos'] as int,
          ),
    ];
  }

  /// Temas em que o versículo aparece — mostrado no painel de estudo.
  Future<List<Tema>> doVersiculo(int livro, int capitulo, int versiculo) async {
    final k = chave(capitulo, versiculo);
    final rows = await _db.rawQuery(
      'SELECT DISTINCT t.* FROM tema_ref r JOIN tema t ON t.id = r.tema '
      'WHERE r.livro=? AND r.ini<=? AND r.fim>=? ORDER BY t.ordem',
      [livro, k, k],
    );
    return [
      for (final r in rows)
        Tema(
          r['id'] as String,
          r['categoria'] as String,
          r['titulo'] as String,
          r['resumo'] as String?,
        ),
    ];
  }

  Future<List<EstudoBiblico>> estudos() async => [
    for (final r in await _db.rawQuery('SELECT * FROM estudo ORDER BY ordem'))
      EstudoBiblico(
        r['id'] as String,
        r['titulo'] as String,
        r['introducao'] as String?,
      ),
  ];

  Future<List<Pergunta>> perguntas(String estudo) async => [
    for (final r in await _db.rawQuery(
      'SELECT * FROM estudo_pergunta WHERE estudo=? ORDER BY ordem',
      [estudo],
    ))
      Pergunta(
        r['pergunta'] as String,
        Passagem(r['livro'] as int, r['ini'] as int, r['fim'] as int),
      ),
  ];
}

/// "Capítulo 23 — O santuário celestial..." sem epígrafe colada e sem o
/// prefixo, para listas.
String tituloCurto(String capitulo) {
  var t = capitulo;
  final aspas = t.indexOf('“');
  if (aspas > 20) t = t.substring(0, aspas).trim();
  final asterisco = t.indexOf('*');
  if (asterisco > 20) t = t.substring(0, asterisco).trim();
  return t.replaceFirstMapped(
    RegExp(r'^Cap[íi]tulo\s+(\d+)\s*[—–-]\s*'),
    (m) => 'cap. ${m[1]} — ',
  );
}
