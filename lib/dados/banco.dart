import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../app_atual.dart';
import 'download.dart';

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

  /// O Hinários leva só os dois hinários (ferramentas/build_hinario.py), com o
  /// mesmo esquema: nada abaixo precisa saber qual dos dois abriu.
  static const _assetCatalogo = soHinarios
      ? 'assets/hinario.db.gz'
      : 'assets/louvorja_pt.db.gz';
  static const _prefixoArquivo = soHinarios ? 'hinario_v' : 'louvorja_pt_v';

  /// Incremente para forçar a reinstalação do catálogo na próxima abertura.
  ///
  /// v2: esquema 26.9 do LouvorJA — categorias, subtítulos, durações, 10
  /// versões bíblicas e caminhos de mídia no formato da API.
  /// v3: coletâneas on-line (5 canais, 16 playlists, 1.150 vídeos) com as
  /// miniaturas embutidas como BLOB.
  ///
  /// O Hinários tem a sua própria numeração. v4: nomes de arquivo do acervo 186
  /// (o Hinário de 1996 passou de MP3 para Opus no servidor). A cópia antiga
  /// pedia `.mp3` e levava 404 em cada hino. Só ele sobe: o Louvor JA guarda no
  /// catálogo o que a sincronização trouxe, e recopiar o catálogo o descartaria.
  static const versaoCatalogo = soHinarios ? 4 : 3;

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
    final destino = p.join(dir.path, '$_prefixoArquivo$versaoCatalogo.db');
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
    final db = await openDatabase(destino);
    await _repararCaminhos(db);
    return db;
  }

  /// Troca por caminho relativo as URLs completas que a sincronização gravou
  /// antes de saber lidar com elas (ver `Download.caminhoDaApi`).
  ///
  /// Sem isto, quem já sincronizou continuaria com faixas e capas que o
  /// servidor responde com 404, mesmo depois de atualizar o app. É barato — só
  /// toca linhas que começam com `http` — e idempotente.
  static Future<void> _repararCaminhos(Database db) async {
    const campos = [
      ('musicas', 'audio'),
      ('musicas', 'audio_pb'),
      ('musicas', 'imagem'),
      ('albums', 'capa'),
      ('letras', 'imagem'),
    ];
    for (final (tabela, coluna) in campos) {
      try {
        final linhas = await db.rawQuery(
          "SELECT rowid AS r, $coluna AS v FROM $tabela WHERE $coluna LIKE 'http%'",
        );
        if (linhas.isEmpty) continue;
        final lote = db.batch();
        for (final l in linhas) {
          lote.rawUpdate('UPDATE $tabela SET $coluna = ? WHERE rowid = ?', [
            Download.caminhoDaApi(l['v']),
            l['r'],
          ]);
        }
        await lote.commit(noResult: true);
      } on DatabaseException {
        // tabela ou coluna ausente neste catálogo: nada a reparar
      }
    }
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
          p.basename(e.path).startsWith(_prefixoArquivo) &&
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
      version: 2,
      onCreate: (db, _) async {
        // Índice de mídia: caminho relativo do catálogo -> URI SAF no aparelho.
        // Percorrer a árvore SAF a cada reprodução seria lento; a varredura
        // acontece uma vez, quando o usuário escolhe a pasta.
        await db.execute('''
          CREATE TABLE midia (
            chave TEXT PRIMARY KEY,
            uri   TEXT NOT NULL,
            bytes INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE favoritos (
            id_musica INTEGER PRIMARY KEY,
            criado_em INTEGER NOT NULL
          )
        ''');
      },
      onUpgrade: (db, de, para) async {
        if (de < 2) {
          // O índice de mídia é só cache: recriar é mais simples e mais seguro
          // do que migrar, e a próxima varredura o refaz com as duas chaves.
          await db.execute('DROP TABLE IF EXISTS midia');
          await db.execute('''
            CREATE TABLE midia (
              chave TEXT PRIMARY KEY,
              uri   TEXT NOT NULL,
              bytes INTEGER NOT NULL DEFAULT 0
            )
          ''');
        }
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
