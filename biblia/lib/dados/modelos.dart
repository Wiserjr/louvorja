/// Coordenadas e registros do app. Versículos são guardados como
/// `capitulo * 1000 + versiculo` nas tabelas de estudo (ver
/// ferramentas/referencias_pt.py): `ini <= chave <= fim` acha tudo o que
/// trata de um versículo numa consulta só.
library;

int chave(int capitulo, int versiculo) => capitulo * 1000 + versiculo;

class Versao {
  const Versao(this.id, this.sigla, this.nome);
  final int id;
  final String sigla;
  final String nome;
}

class Livro {
  const Livro(
    this.numero,
    this.nome,
    this.abreviacao,
    this.testamento,
    this.capitulos,
  );
  final int numero;
  final String nome;
  final String abreviacao;

  /// 1 = Antigo, 2 = Novo.
  final int testamento;
  final int capitulos;
}

class Versiculo {
  const Versiculo(this.numero, this.texto);
  final int numero;

  /// Pode trazer `<J>…</J>` (palavras de Jesus) e `<i>…</i>` (palavras
  /// acrescentadas pelos tradutores), conforme a tradução.
  final String texto;
}

/// Um livro de Ellen G. White ou de um pioneiro.
class Obra {
  const Obra({
    required this.id,
    required this.arquivo,
    required this.sigla,
    required this.titulo,
    required this.autor,
    required this.grupo,
    required this.prioridade,
    required this.url,
    required this.bytes,
    required this.sha256,
    required this.paginas,
  });

  final int id;
  final String arquivo;
  final String sigla;
  final String titulo;
  final String autor;

  /// `egw` ou `pioneiros`.
  final String grupo;
  final int prioridade;
  final String url;
  final int bytes;
  final String sha256;
  final int paginas;

  bool get deEllenWhite => grupo == 'egw';

  factory Obra.deMapa(Map<String, Object?> m) => Obra(
    id: m['id'] as int,
    arquivo: m['arquivo'] as String,
    sigla: m['sigla'] as String,
    titulo: m['titulo'] as String,
    autor: m['autor'] as String,
    grupo: m['grupo'] as String,
    prioridade: m['prioridade'] as int,
    url: m['url'] as String,
    bytes: m['bytes'] as int,
    sha256: m['sha256'] as String,
    paginas: m['paginas'] as int,
  );
}

/// Como um trecho se liga ao versículo.
enum TipoLigacao {
  /// O parágrafo cita o versículo.
  citacao,

  /// "Este capítulo é baseado em ..." — o capítulo inteiro narra a passagem.
  capitulo,

  /// Comentário versículo a versículo (Daniel e Apocalipse, Urias Smith).
  comentario,
}

/// Um parágrafo (ou seção) de uma obra, localizado no PDF. O texto não vem
/// do banco: é lido do PDF no aparelho (ver `trechos.dart`).
class Trecho {
  const Trecho({
    required this.id,
    required this.obra,
    required this.pagina,
    required this.paginaOriginal,
    required this.segmentos,
    required this.ancora,
    required this.capitulo,
    required this.tipo,
    required this.livro,
    required this.ini,
    required this.fim,
  });

  final int id;
  final Obra obra;

  /// Índice da página no PDF, a partir de 0.
  final int pagina;

  /// Número da página na edição impressa ("[72]" no PDF), quando há.
  final int? paginaOriginal;

  /// `(página, início, fim)` em unidades UTF-16 do texto cru de cada página.
  final List<(int, int, int)> segmentos;

  /// O texto da citação no parágrafo ("Mateus 4:2-4"), para reencontrá-lo se
  /// o PDF tiver mudado.
  final String? ancora;

  /// "Capítulo 12 — A tentação", quando a obra tem capítulos.
  final String? capitulo;
  final TipoLigacao tipo;

  /// A passagem bíblica a que o trecho está ligado.
  final int livro;
  final int ini;
  final int fim;

  /// "DTN, p. 72" — a forma usual de citar Ellen G. White.
  String get referencia {
    final pag = paginaOriginal ?? (pagina + 1);
    return '${obra.sigla}, p. $pag';
  }

  static List<(int, int, int)> lerSegmentos(String texto) => [
    for (final s in texto.split(';'))
      if (s.isNotEmpty)
        () {
          final partes = s.split(':').map(int.parse).toList();
          return (partes[0], partes[1], partes[2]);
        }(),
  ];
}

/// Referência cruzada do OpenBible.info.
class RefCruzada {
  const RefCruzada({
    required this.livro,
    required this.ini,
    required this.fim,
    required this.votos,
    required this.tipo,
  });

  final int livro;
  final int ini;
  final int fim;
  final int votos;

  /// 0 temática, 1 alusão, 2 citação, 3 passagem paralela.
  final int tipo;

  bool get citacao => tipo == 2;
  bool get alusao => tipo == 1;
  bool get paralelo => tipo == 3;
}

class Introducao {
  const Introducao(this.campos);

  /// autor, data, local, destinatarios, tema, versiculo_chave, esboco,
  /// mensagem, cristo, egw.
  final Map<String, String?> campos;

  String? operator [](String campo) => campos[campo];
}

class Nota {
  const Nota(this.livro, this.ini, this.fim, this.texto);
  final int livro;
  final int ini;
  final int fim;
  final String texto;
}

/// Uma posição de leitura.
class Posicao {
  const Posicao(this.livro, this.capitulo, [this.versiculo]);
  final int livro;
  final int capitulo;
  final int? versiculo;

  @override
  bool operator ==(Object other) =>
      other is Posicao &&
      other.livro == livro &&
      other.capitulo == capitulo &&
      other.versiculo == versiculo;

  @override
  int get hashCode => Object.hash(livro, capitulo, versiculo);
}
