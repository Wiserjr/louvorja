import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';

import 'banco.dart';
import 'download.dart';

/// Mantém o catálogo em dia com a API oficial.
///
/// A API expõe o acervo em três níveis:
///
///     json_db/config          versão publicada (`version_number`)
///     json_db/pt_categories   índice: categorias -> álbuns
///     json_db/album_{id}      faixas do álbum
///     json_db/music_{id}      caminhos de mídia e a letra completa
///
/// **A sincronização nunca apaga.** O índice da API traz apenas as cinco
/// categorias de coletânea; os dois hinários (1.214 hinos), a Doxologia e as
/// Infantis existem só no catálogo extraído do desktop. Um "espelhar o remoto"
/// destruiria justamente a parte maior do acervo.
class Sincronizacao {
  Sincronizacao._();
  static final Sincronizacao instancia = Sincronizacao._();

  final _http = HttpClient()..connectionTimeout = const Duration(seconds: 20);

  Future<Map<String, dynamic>> _json(String chave) async {
    final base = await Download.instancia.urlBase;
    final url = Uri.parse('$base/json_db/$chave');
    final resp = await (await _http.getUrl(url)).close();
    final texto = await resp.transform(utf8.decoder).join();
    if (resp.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${resp.statusCode}', uri: url);
    }
    final decodificado = jsonDecode(texto);
    return decodificado is Map<String, dynamic>
        ? decodificado
        : {'_lista': decodificado};
  }

  Future<List<dynamic>> _jsonLista(String chave) async =>
      (await _json(chave))['_lista'] as List<dynamic>;

  /// Remove a barra inicial: a API devolve `/musics/pt/...`, o catálogo guarda
  /// `musics/pt/...`.
  static String? _caminho(Object? v) {
    if (v is! String || v.isEmpty) return null;
    return v.startsWith('/') ? v.substring(1) : v;
  }

  static int _ms(Object? v) {
    if (v is! String) return 0;
    final p = v.split(':');
    if (p.length != 3) return 0;
    final h = int.tryParse(p[0]) ?? 0;
    final m = int.tryParse(p[1]) ?? 0;
    final s = double.tryParse(p[2])?.toInt() ?? 0;
    return (h * 3600 + m * 60 + s) * 1000;
  }

  // ---------------------------------------------------------------- versões

  Future<int> versaoRemota() async {
    final c = await _json('config');
    return (c['version_number'] as num?)?.toInt() ?? 0;
  }

  Future<int> versaoLocal() async {
    final db = await Banco.catalogo;
    final r = await db.query(
      'meta',
      columns: ['valor'],
      where: 'chave = ?',
      whereArgs: ['versao_acervo'],
    );
    return r.isEmpty ? 0 : int.tryParse(r.first['valor'] as String? ?? '') ?? 0;
  }

  Future<Diagnostico> verificar() async {
    try {
      final local = await versaoLocal();
      final remota = await versaoRemota();
      return Diagnostico(local: local, remota: remota);
    } on SocketException catch (e) {
      return Diagnostico(
        local: await versaoLocal(),
        remota: null,
        erro: 'Servidor inacessível: ${e.osError?.message ?? e.message}',
      );
    } catch (e) {
      return Diagnostico(local: await versaoLocal(), remota: null, erro: '$e');
    }
  }

  // ------------------------------------------------------------ atualização

  /// Traz do servidor o que houver de novo.
  ///
  /// [aoProgredir] recebe a etapa corrente e o quanto dela já foi feito.
  Future<Resumo> sincronizar({
    void Function(String etapa, int feito, int total)? aoProgredir,
    bool forcar = false,
  }) async {
    final db = await Banco.catalogo;
    final local = await versaoLocal();
    final remota = await versaoRemota();

    if (!forcar && remota <= local) {
      return Resumo(
        versaoAnterior: local,
        versaoNova: remota,
        semMudancas: true,
      );
    }

    final resumo = Resumo(versaoAnterior: local, versaoNova: remota);

    // 1) índice de categorias e álbuns
    aoProgredir?.call('Lendo o índice', 0, 1);
    final categorias = await _jsonLista('pt_categories');

    final idsAlbuns = <int>[];
    await db.transaction((txn) async {
      for (final cat in categorias.cast<Map<String, dynamic>>()) {
        final idCat = (cat['id_category'] as num).toInt();
        await txn.insert('categorias', {
          'id': idCat,
          'nome': cat['name'],
          'slug': cat['slug'],
          // O índice publica só coletâneas; hinários e doxologia são locais.
          'tipo': 'collection',
          'ordem': (cat['order'] as num?)?.toInt() ?? 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        for (final alb
            in (cat['albums'] as List).cast<Map<String, dynamic>>()) {
          final idAlbum = (alb['id_album'] as num).toInt();
          idsAlbuns.add(idAlbum);
          await txn.insert('albums', {
            'id': idAlbum,
            'nome': alb['name'],
            'cor': alb['color'],
            'capa': _caminho(alb['url_image']),
            'ordem': (alb['order'] as num?)?.toInt(),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
          await txn.insert('album_categoria', {
            'id_album': idAlbum,
            'id_categoria': idCat,
            'subtitulo': (alb['subtitle'] as String?)?.trim().isEmpty ?? true
                ? null
                : alb['subtitle'],
            'ordem': (alb['order'] as num?)?.toInt() ?? 0,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
    resumo.categorias = categorias.length;
    resumo.albuns = idsAlbuns.length;

    // 2) faixas de cada álbum
    final novas = <int>[];
    for (var i = 0; i < idsAlbuns.length; i++) {
      aoProgredir?.call('Lendo álbuns', i + 1, idsAlbuns.length);
      final alb = await _json('album_${idsAlbuns[i]}');
      final musicas = (alb['musics'] as List?) ?? const [];

      await db.transaction((txn) async {
        for (final m in musicas.cast<Map<String, dynamic>>()) {
          final idMusica = (m['id_music'] as num).toInt();

          final existente = await txn.query(
            'musicas',
            columns: ['id', 'audio'],
            where: 'id = ?',
            whereArgs: [idMusica],
            limit: 1,
          );

          if (existente.isEmpty) {
            // Faixa nova: o índice do álbum não traz os caminhos de mídia nem a
            // letra, então ela entra incompleta e é completada no passo 3.
            await txn.insert('musicas', {
              'id': idMusica,
              'nome': m['name'],
              'duracao_ms': _ms(m['duration']),
              'tem_letra': 0,
            });
            novas.add(idMusica);
          } else {
            await txn.update(
              'musicas',
              {'nome': m['name'], 'duracao_ms': _ms(m['duration'])},
              where: 'id = ?',
              whereArgs: [idMusica],
            );
            if (existente.first['audio'] == null) novas.add(idMusica);
          }

          await txn.insert('album_musicas', {
            'id_album': idsAlbuns[i],
            'id_musica': idMusica,
            'faixa': (m['track'] as num?)?.toInt() ?? 0,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
    }

    // 3) detalhes e letra das faixas novas
    for (var i = 0; i < novas.length; i++) {
      aoProgredir?.call('Baixando letras', i + 1, novas.length);
      try {
        await detalharMusica(novas[i]);
        resumo.musicasNovas++;
      } catch (_) {
        resumo.falhas++;
      }
    }

    await db.update(
      'meta',
      {'valor': '$remota'},
      where: 'chave = ?',
      whereArgs: ['versao_acervo'],
    );

    return resumo;
  }

  /// Busca caminhos de mídia e letra de uma música e grava no catálogo.
  ///
  /// Usado tanto pela sincronização quanto sob demanda, quando o usuário abre
  /// uma faixa cuja letra ainda não veio.
  Future<void> detalharMusica(int idMusica) async {
    final db = await Banco.catalogo;
    final m = await _json('music_$idMusica');

    await db.transaction((txn) async {
      final letras = (m['lyric'] as List?) ?? const [];
      final temLetra = letras.any(
        (l) =>
            (l['show_slide'] as num?) == 1 &&
            ((l['lyric'] as String?) ?? '').trim().isNotEmpty,
      );

      await txn.update(
        'musicas',
        {
          'nome': m['name'],
          'audio': _caminho(m['url_music']),
          'audio_pb': _caminho(m['url_instrumental_music']),
          'imagem': _caminho(m['url_image']),
          'duracao_ms': _ms(m['duration']),
          'tem_letra': temLetra ? 1 : 0,
        },
        where: 'id = ?',
        whereArgs: [idMusica],
      );

      await txn.delete('letras', where: 'id_musica = ?', whereArgs: [idMusica]);
      for (final l in letras.cast<Map<String, dynamic>>()) {
        final t = _ms(l['time']);
        await txn.insert('letras', {
          'id': (l['id_lyric'] as num).toInt(),
          'id_musica': idMusica,
          'ordem': (l['order'] as num?)?.toInt() ?? 0,
          'texto': l['lyric'] ?? '',
          'texto_aux': l['aux_lyric'],
          'imagem': _caminho(l['url_image']),
          'ms': t,
          'ms_pb': _ms(l['instrumental_time']) == 0
              ? t
              : _ms(l['instrumental_time']),
          'exibe_slide': (l['show_slide'] as num?)?.toInt() ?? 1,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }
}

class Diagnostico {
  Diagnostico({required this.local, required this.remota, this.erro});

  final int local;
  final int? remota;
  final String? erro;

  bool get temAtualizacao => remota != null && remota! > local;
  bool get emDia => remota != null && remota! <= local;
}

class Resumo {
  Resumo({
    required this.versaoAnterior,
    required this.versaoNova,
    this.semMudancas = false,
  });

  final int versaoAnterior;
  final int versaoNova;
  final bool semMudancas;

  int categorias = 0;
  int albuns = 0;
  int musicasNovas = 0;
  int falhas = 0;

  @override
  String toString() => semMudancas
      ? 'Catálogo já está na versão $versaoNova.'
      : 'Versão $versaoAnterior → $versaoNova: $albuns álbuns conferidos, '
            '$musicasNovas músicas novas'
            '${falhas > 0 ? ', $falhas falharam' : ''}.';
}
