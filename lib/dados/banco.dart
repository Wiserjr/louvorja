import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Acesso aos dois bancos do app, deliberadamente separados.
///
/// - **catálogo** (`louvorja_pt.db`): álbuns, músicas, letras e Bíblia, extraídos
///   do LouvorJA desktop e atualizáveis pela API oficial.
/// - **usuário** (`usuario.db`): favoritos, última posição ouvida e o índice de
///   mídia. Sobrevive à troca do catálogo.
///
/// Manter os dois apartados é o que permite atualizar o acervo sem que o usuário
/// perca nada do que é dele.
class Banco {
  Banco._();

  static const _assetCatalogo = 'assets/louvorja_pt.db.gz';

  /// Incremente para forçar a reinstalação do catálogo na próxima abertura.
  ///
  /// v2: esquema 26.9 do LouvorJA — categorias, subtítulos, durações, 10
  /// versões bíblicas e caminhos de mídia no formato da API.
  /// v3: coletâneas on-line (5 canais, 16 playlists, 1.150 vídeos) com as
  /// miniaturas embutidas como BLOB.
  static const versaoCatalogo = 3;

  // Memoriza o **Future**, e nao o Database ja resolvido.
  //
  // Com `_catalogo ??= await _abrirCatalogo()` o await suspende antes da
  // atribuicao: dois chamadores simultaneos veem null e ambos executam a
  // abertura inteira, competindo pela copia do asset e pela limpeza dos
  // arquivos antigos. Guardar o Future torna a segunda chamada uma espera pela
  // primeira.
  static Future<Database>? _catalogo;
  static Future<Database>? _usuario;

  static Future<Database> get catalogo => _catalogo ??= _abrirCatalogo();

  static Future<Database> get usuario => _usuario ??= _abrirUsuario();

  static Future<Database> _abrirCatalogo() async {
    final dir = await getApplicationSupportDirectory();
    final destino = p.join(dir.path, 'louvorja_pt_v$versaoCatalogo.db');
    final arquivo = File(destino);

    if (!await arquivo.exists()) {
      // O asset viaja comprimido (14,4 MB em vez de 39,4 MB). Inflar aqui custa
      // menos de um segundo, uma única vez, e economiza 25 MB no APK.
      final comprimido = await rootBundle.load(_assetCatalogo);
      final bytes = gzip.decode(
        comprimido.buffer.asUint8List(
          comprimido.offsetInBytes,
          comprimido.lengthInBytes,
        ),
      );
      await arquivo.create(recursive: true);
      await arquivo.writeAsBytes(bytes, flush: true);
      await _limparCatalogosAntigos(dir, destino);
    }

    // Gravável, e não somente leitura: a sincronização com a API atualiza o
    // catálogo no lugar. O asset continua sendo apenas a semente.
    return openDatabase(destino);
  }

  /// Remove versões anteriores do catálogo para não acumular dezenas de MB a
  /// cada atualização.
  ///
  /// A remoção é tolerante: arquivos auxiliares do SQLite (`-journal`, `-wal`)
  /// desaparecem junto com o banco principal, então uma entrada listada pode já
  /// não existir quando chega a vez dela.
  static Future<void> _limparCatalogosAntigos(
    Directory dir,
    String atual,
  ) async {
    await for (final e in dir.list()) {
      if (e is File &&
          p.basename(e.path).startsWith('louvorja_pt_v') &&
          e.path != atual) {
        try {
          await e.delete();
        } on FileSystemException {
          // ja removido
        }
      }
    }
  }

  static Future<Database> _abrirUsuario() async {
    final dir = await getApplicationSupportDirectory();
    return openDatabase(
      p.join(dir.path, 'usuario.db'),
      version: 1,
      onCreate: (db, _) async {
        // Índice de mídia: caminho relativo do catálogo -> URI SAF no aparelho.
        // Percorrer a árvore SAF a cada reprodução seria lento; a varredura
        // acontece uma vez, quando o usuário escolhe a pasta.
        await db.execute('''
          CREATE TABLE midia (
            caminho TEXT PRIMARY KEY,
            uri     TEXT NOT NULL,
            bytes   INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE favoritos (
            id_musica INTEGER PRIMARY KEY,
            criado_em INTEGER NOT NULL
          )
        ''');
      },
    );
  }

  static Future<void> fechar() async {
    await (await _catalogo)?.close();
    await (await _usuario)?.close();
    _catalogo = null;
    _usuario = null;
  }
}
