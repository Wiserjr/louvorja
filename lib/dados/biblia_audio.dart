import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// Uma Bíblia em áudio publicada pela Bible Brain.
class BibliaAudio {
  const BibliaAudio({
    required this.filesetId,
    required this.bibliaId,
    required this.nome,
    this.tipo,
    this.tamanho,
  });

  /// Identificador do conjunto de arquivos — é ele que o endpoint de capítulo
  /// recebe, não o id da Bíblia.
  final String filesetId;
  final String bibliaId;
  final String nome;

  /// `audio` (leitura simples) ou `audio_drama` (dramatizada, com trilha).
  final String? tipo;

  /// `C` = completa, `NT` = Novo Testamento, `OT` = Antigo Testamento.
  final String? tamanho;

  bool get dramatizada => (tipo ?? '').contains('drama');

  String get descricao => [
    if (dramatizada) 'dramatizada' else 'narrada',
    if (tamanho == 'NT') 'Novo Testamento',
    if (tamanho == 'OT') 'Antigo Testamento',
    if (tamanho == 'C') 'Bíblia completa',
  ].join(' · ');

  Map<String, String> get paraJson => {
    'fileset': filesetId,
    'biblia': bibliaId,
    'nome': nome,
    'tipo': ?tipo,
    'tamanho': ?tamanho,
  };

  factory BibliaAudio.doJson(Map<String, dynamic> m) => BibliaAudio(
    filesetId: m['fileset'] as String,
    bibliaId: m['biblia'] as String,
    nome: m['nome'] as String,
    tipo: m['tipo'] as String?,
    tamanho: m['tamanho'] as String?,
  );
}

class ResultadoBibleBrain {
  const ResultadoBibleBrain({
    required this.ok,
    required this.mensagem,
    this.versoes = const [],
  });

  final bool ok;
  final String mensagem;
  final List<BibliaAudio> versoes;
}

/// Cliente da Bible Brain (Faith Comes By Hearing), a fonte **licenciada** de
/// Bíblia em áudio.
///
/// Existe porque as gravações de apps como o YouVersion são obras licenciadas
/// de editoras e seus termos vedam extração e redistribuição. A Bible Brain
/// publica áudio em mais de dois mil idiomas com API gratuita para uso não
/// comercial — mas exige uma **chave por desenvolvedor**, que o usuário obtém em
/// 4.dbt.io/api_key/request e informa aqui. Sem chave, nada disto funciona, e é
/// assim mesmo: é o que separa uso legítimo de cópia.
///
/// Contrato (do OpenAPI oficial em `4.dbt.io/open-api-4.json`):
///
///     GET /bibles?language_code=por&media=audio&v=4&key=…
///     GET /bibles/filesets/{fileset_id}/{book}/{chapter}?v=4&key=…
///
/// O segundo devolve `data[].path` com a URL do arquivo de áudio.
class BibleBrain {
  BibleBrain._();
  static final BibleBrain instancia = BibleBrain._();

  static const base = 'https://4.dbt.io/api';
  static const paginaDaChave = 'https://4.dbt.io/api_key/request';

  static const _chaveApi = 'bible_brain_chave';
  static const _chaveVersao = 'bible_brain_versao';

  final _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20)
    ..userAgent = 'LouvorJA-Android/1.0';

  /// Códigos USFM na ordem canônica, alinhados a `biblia_livro.numero` (1 a 66).
  ///
  /// A Bible Brain identifica livros por esses códigos; o catálogo daqui usa
  /// número e nome em português. Esta lista é a ponte, e a ordem é a mesma das
  /// duas pontas — por isso o índice basta, sem tabela de conversão.
  static const livrosUsfm = [
    'GEN',
    'EXO',
    'LEV',
    'NUM',
    'DEU',
    'JOS',
    'JDG',
    'RUT',
    '1SA',
    '2SA',
    '1KI',
    '2KI',
    '1CH',
    '2CH',
    'EZR',
    'NEH',
    'EST',
    'JOB',
    'PSA',
    'PRO',
    'ECC',
    'SNG',
    'ISA',
    'JER',
    'LAM',
    'EZK',
    'DAN',
    'HOS',
    'JOL',
    'AMO',
    'OBA',
    'JON',
    'MIC',
    'NAM',
    'HAB',
    'ZEP',
    'HAG',
    'ZEC',
    'MAL',
    'MAT',
    'MRK',
    'LUK',
    'JHN',
    'ACT',
    'ROM',
    '1CO',
    '2CO',
    'GAL',
    'EPH',
    'PHP',
    'COL',
    '1TH',
    '2TH',
    '1TI',
    '2TI',
    'TIT',
    'PHM',
    'HEB',
    'JAS',
    '1PE',
    '2PE',
    '1JN',
    '2JN',
    '3JN',
    'JUD',
    'REV',
  ];

  static String? usfmDoLivro(int numero) =>
      (numero >= 1 && numero <= livrosUsfm.length)
      ? livrosUsfm[numero - 1]
      : null;

  // ------------------------------------------------------------- preferências

  Future<String?> get chave async =>
      (await SharedPreferences.getInstance()).getString(_chaveApi);

  Future<void> definirChave(String v) async {
    final prefs = await SharedPreferences.getInstance();
    final limpa = v.trim();
    if (limpa.isEmpty) {
      await prefs.remove(_chaveApi);
    } else {
      await prefs.setString(_chaveApi, limpa);
    }
  }

  Future<BibliaAudio?> get versaoEscolhida async {
    final bruto = (await SharedPreferences.getInstance()).getString(
      _chaveVersao,
    );
    if (bruto == null) return null;
    try {
      return BibliaAudio.doJson(
        (jsonDecode(bruto) as Map).cast<String, dynamic>(),
      );
    } on FormatException {
      return null;
    }
  }

  Future<void> escolherVersao(BibliaAudio? v) async {
    final prefs = await SharedPreferences.getInstance();
    if (v == null) {
      await prefs.remove(_chaveVersao);
    } else {
      await prefs.setString(_chaveVersao, jsonEncode(v.paraJson));
    }
  }

  Future<bool> get configurado async =>
      (await chave) != null && (await versaoEscolhida) != null;

  // ------------------------------------------------------------------ rede

  Future<Map<String, dynamic>> _json(
    String caminho,
    Map<String, String> params,
  ) async {
    final k = await chave;
    if (k == null) throw const SemChave();

    final url = Uri.parse('$base$caminho')
        .replace(queryParameters: {...params, 'v': '4', 'key': k});
    final resp = await (await _http.getUrl(url)).close();
    final corpo = await resp.transform(utf8.decoder).join();

    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw const ChaveRecusada();
    }
    if (resp.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${resp.statusCode}', uri: url);
    }
    final j = jsonDecode(corpo);
    return j is Map<String, dynamic> ? j : {'data': j};
  }

  /// Bíblias em áudio disponíveis em português.
  ///
  /// A resposta aninha os filesets por "bucket", e o formato varia entre um mapa
  /// de listas e uma lista. A leitura aqui aceita as duas formas em vez de
  /// depender de uma — é resposta de terceiro, e quebrar a tela por causa de um
  /// invólucro seria desnecessário.
  Future<ResultadoBibleBrain> listarVersoes() async {
    try {
      final j = await _json('/bibles', {
        'language_code': 'por',
        'media': 'audio',
        'limit': '100',
      });
      final dados = (j['data'] as List?) ?? const [];
      final versoes = <BibliaAudio>[];

      for (final b in dados.cast<Map<String, dynamic>>()) {
        final nome = (b['vname'] ?? b['name'] ?? b['abbr'] ?? '?').toString();
        final id = (b['abbr'] ?? b['id'] ?? '').toString();

        for (final fs in _achatarFilesets(b['filesets'])) {
          final tipo = (fs['type'] ?? '').toString();
          if (!tipo.startsWith('audio')) continue;
          versoes.add(
            BibliaAudio(
              filesetId: (fs['id'] ?? '').toString(),
              bibliaId: id,
              nome: nome,
              tipo: tipo,
              tamanho: (fs['size'] ?? '').toString(),
            ),
          );
        }
      }
      // Completas primeiro, depois narradas antes de dramatizadas.
      versoes.sort((a, b) {
        final pa = a.tamanho == 'C' ? 0 : 1;
        final pb = b.tamanho == 'C' ? 0 : 1;
        if (pa != pb) return pa - pb;
        if (a.dramatizada != b.dramatizada) return a.dramatizada ? 1 : -1;
        return a.nome.compareTo(b.nome);
      });

      return ResultadoBibleBrain(
        ok: true,
        mensagem: versoes.isEmpty
            ? 'A chave funciona, mas nenhuma Bíblia em áudio em português foi '
                  'retornada.'
            : '${versoes.length} versões em áudio encontradas.',
        versoes: versoes,
      );
    } on SemChave {
      return const ResultadoBibleBrain(
        ok: false,
        mensagem: 'Informe a chave da Bible Brain.',
      );
    } on ChaveRecusada {
      return const ResultadoBibleBrain(
        ok: false,
        mensagem: 'Chave recusada pelo servidor. Confira se copiou inteira.',
      );
    } on SocketException catch (e) {
      return ResultadoBibleBrain(
        ok: false,
        mensagem: 'Sem conexão: ${e.osError?.message ?? e.message}',
      );
    } catch (e) {
      return ResultadoBibleBrain(ok: false, mensagem: '$e');
    }
  }

  static List<Map<String, dynamic>> _achatarFilesets(Object? bruto) {
    final saida = <Map<String, dynamic>>[];
    void juntar(Object? v) {
      if (v is List) {
        for (final e in v) {
          if (e is Map) saida.add(e.cast<String, dynamic>());
        }
      } else if (v is Map) {
        for (final e in v.values) {
          juntar(e);
        }
      }
    }

    juntar(bruto);
    return saida;
  }

  /// URL do áudio de um capítulo, ou `null` se a versão não o cobrir.
  ///
  /// Devolve nulo em vez de lançar quando o capítulo não existe no conjunto —
  /// uma versão só do Novo Testamento não tem Gênesis, e isso é situação
  /// normal, não erro.
  Future<({String url, int? duracaoSegundos})?> audioDoCapitulo({
    required int numeroDoLivro,
    required int capitulo,
  }) async {
    final versao = await versaoEscolhida;
    final livro = usfmDoLivro(numeroDoLivro);
    if (versao == null || livro == null) return null;

    try {
      final j = await _json(
        '/bibles/filesets/${versao.filesetId}/$livro/$capitulo',
        const {},
      );
      final dados = (j['data'] as List?)?.cast<Map<String, dynamic>>();
      if (dados == null || dados.isEmpty) return null;

      final primeiro = dados.first;
      final url = (primeiro['path'] ?? '').toString();
      if (url.isEmpty) return null;
      final dur = primeiro['duration'];
      return (url: url, duracaoSegundos: dur is num ? dur.toInt() : null);
    } on ChaveRecusada {
      rethrow;
    } catch (_) {
      return null;
    }
  }
}

class SemChave implements Exception {
  const SemChave();
  @override
  String toString() => 'Chave da Bible Brain não informada';
}

class ChaveRecusada implements Exception {
  const ChaveRecusada();
  @override
  String toString() => 'Chave da Bible Brain recusada';
}
