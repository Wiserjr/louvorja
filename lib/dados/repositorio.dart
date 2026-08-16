import 'modelos.dart';
import 'banco.dart';

/// Consultas ao catálogo. Nenhuma escrita — o catálogo é imutável.
class Repositorio {
  const Repositorio();

  Future<List<Album>> albuns() async {
    final db = await Banco.catalogo;
    final r = await db.rawQuery('''
      SELECT a.id, a.nome, a.cor, a.capa, a.ordem, ac.subtitulo,
             COUNT(am.id_musica) AS total_musicas
        FROM albums a
        LEFT JOIN album_musicas am ON am.id_album = a.id
        LEFT JOIN album_categoria ac ON ac.id_album = a.id
       GROUP BY a.id, a.nome, a.cor, a.capa, a.ordem, ac.subtitulo
       ORDER BY a.nome COLLATE NOCASE
    ''');
    return r.map(Album.doMapa).toList();
  }

  /// Categorias que têm ao menos um álbum, na ordem do programa original.
  Future<List<Categoria>> categorias() async {
    final db = await Banco.catalogo;
    final r = await db.rawQuery('''
      SELECT c.id, c.nome, c.slug, c.tipo, c.ordem
        FROM categorias c
       WHERE EXISTS (SELECT 1 FROM album_categoria ac WHERE ac.id_categoria = c.id)
       ORDER BY c.ordem, c.nome COLLATE NOCASE
    ''');
    return r.map(Categoria.doMapa).toList();
  }

  /// Álbuns de uma categoria.
  ///
  /// A ordenação segue `album_categoria.ordem`, que nos CDs oficiais coloca os
  /// mais recentes primeiro — a mesma ordem da grade do programa original.
  Future<List<Album>> albunsDaCategoria(int idCategoria) async {
    final db = await Banco.catalogo;
    final r = await db.rawQuery(
      '''
      SELECT a.id, a.nome, a.cor, a.capa, ac.ordem, ac.subtitulo,
             COUNT(am.id_musica) AS total_musicas
        FROM album_categoria ac
        JOIN albums a ON a.id = ac.id_album
        LEFT JOIN album_musicas am ON am.id_album = a.id
       WHERE ac.id_categoria = ?
       GROUP BY a.id, a.nome, a.cor, a.capa, ac.ordem, ac.subtitulo
       ORDER BY ac.ordem DESC, a.nome COLLATE NOCASE
    ''',
      [idCategoria],
    );
    return r.map(Album.doMapa).toList();
  }

  /// Busca um hino pelo número dentro de um hinário.
  ///
  /// Nos hinários a faixa **é** o número do hino, então a busca por número sai
  /// de graça — é o mesmo campo que ordena o álbum.
  Future<List<Musica>> hinosPorNumero(int idAlbum, int numero) async {
    final db = await Banco.catalogo;
    final r = await db.rawQuery(
      '''
      SELECT m.id, m.nome, m.audio, m.audio_pb, m.imagem,
             m.audio_bytes, m.tem_letra, m.duracao_ms, am.faixa
        FROM musicas m
        JOIN album_musicas am ON am.id_musica = m.id
       WHERE am.id_album = ? AND am.faixa = ?
    ''',
      [idAlbum, numero],
    );
    return r.map(Musica.doMapa).toList();
  }

  /// Versão do acervo que este catálogo representa (a mesma numeração que a
  /// API publica em `json_db/config`).
  Future<int> versaoAcervo() async {
    final db = await Banco.catalogo;
    final r = await db.query(
      'meta',
      columns: ['valor'],
      where: 'chave = ?',
      whereArgs: ['versao_acervo'],
    );
    return r.isEmpty ? 0 : int.tryParse(r.first['valor'] as String? ?? '') ?? 0;
  }

  Future<List<Musica>> musicasDoAlbum(int idAlbum) async {
    final db = await Banco.catalogo;
    final r = await db.rawQuery(
      '''
      SELECT m.id, m.nome, m.audio, m.audio_pb, m.imagem,
             m.audio_bytes, m.tem_letra, m.duracao_ms, am.faixa
        FROM musicas m
        JOIN album_musicas am ON am.id_musica = m.id
       WHERE am.id_album = ?
       ORDER BY am.faixa
    ''',
      [idAlbum],
    );
    return r.map(Musica.doMapa).toList();
  }

  /// Busca por título em todo o acervo.
  ///
  /// Traz o álbum junto porque na busca global a faixa aparece solta — "Santo,
  /// Santo, Santo!" sem dizer que é do Hinário não ajuda ninguém.
  ///
  /// Um termo numérico também casa com o número da faixa, que nos hinários é o
  /// número do hino. `LIKE` sem insensibilidade a acento basta: são 1.889
  /// títulos e a varredura é instantânea.
  Future<List<Musica>> buscarMusicas(String termo) async {
    final t = termo.trim();
    if (t.isEmpty) return const [];
    final numero = int.tryParse(t);
    final db = await Banco.catalogo;
    final r = await db.rawQuery(
      '''
      SELECT m.id, m.nome, m.audio, m.audio_pb, m.imagem, m.audio_bytes,
             m.tem_letra, m.duracao_ms, am.faixa,
             a.id AS id_album, a.nome AS album_nome
        FROM musicas m
        LEFT JOIN album_musicas am ON am.id_musica = m.id
        LEFT JOIN albums a ON a.id = am.id_album
       WHERE m.nome LIKE ? COLLATE NOCASE
          OR (? IS NOT NULL AND am.faixa = ?)
       ORDER BY m.nome COLLATE NOCASE
       LIMIT 150
    ''',
      ['%$t%', numero, numero],
    );
    return r.map(Musica.doMapa).toList();
  }

  /// Slides exibíveis de uma música, em ordem.
  ///
  /// O filtro `exibe_slide = 1` é essencial: as 7.559 linhas restantes são
  /// marcadores de tela em branco herdados da projeção do desktop, com `ms = 0`.
  /// Incluí-las faria o player saltar para o instante zero no meio da música.
  Future<List<Slide>> slidesDe(int idMusica) async {
    final db = await Banco.catalogo;
    final r = await db.rawQuery(
      '''
      SELECT id, ordem, texto, texto_aux, imagem, ms, ms_pb
        FROM letras
       WHERE id_musica = ? AND exibe_slide = 1
       ORDER BY ordem
    ''',
      [idMusica],
    );
    return r.map(Slide.doMapa).toList();
  }

  /// Faixas com áudio publicado, opcionalmente restritas a um álbum ou a uma
  /// categoria inteira. Base para o download em lote.
  Future<List<Musica>> musicasParaDownload({
    int? idAlbum,
    int? idCategoria,
  }) async {
    final db = await Banco.catalogo;
    final onde = <String>['m.audio IS NOT NULL'];
    final args = <Object?>[];
    if (idAlbum != null) {
      onde.add('am.id_album = ?');
      args.add(idAlbum);
    }
    if (idCategoria != null) {
      onde.add('ac.id_categoria = ?');
      args.add(idCategoria);
    }
    final r = await db.rawQuery('''
      SELECT DISTINCT m.id, m.nome, m.audio, m.audio_pb, m.imagem,
             m.audio_bytes, m.tem_letra, m.duracao_ms, am.faixa
        FROM musicas m
        JOIN album_musicas am ON am.id_musica = m.id
        LEFT JOIN album_categoria ac ON ac.id_album = am.id_album
       WHERE ${onde.join(' AND ')}
       ORDER BY m.nome COLLATE NOCASE
    ''', args);
    return r.map(Musica.doMapa).toList();
  }

  // ---------- Coletâneas on-line ----------

  Future<List<Canal>> canais() async {
    final db = await Banco.catalogo;
    final r = await db.rawQuery('''
      SELECT c.id, c.nome, c.url, c.thumb,
             (SELECT COUNT(*) FROM onl_playlists p WHERE p.id_canal = c.id) AS total
        FROM onl_canais c
       ORDER BY c.nome COLLATE NOCASE
    ''');
    return r.map(Canal.doMapa).toList();
  }

  Future<List<PlaylistOnline>> playlists({int? idCanal}) async {
    final db = await Banco.catalogo;
    final r = await db.rawQuery(
      '''
      SELECT p.id, p.nome, p.thumb, c.nome AS canal_nome,
             (SELECT COUNT(*) FROM onl_videos v WHERE v.id_playlist = p.id) AS total
        FROM onl_playlists p
        JOIN onl_canais c ON c.id = p.id_canal
       ${idCanal == null ? '' : 'WHERE p.id_canal = ?'}
       ORDER BY p.nome COLLATE NOCASE
    ''',
      [?idCanal],
    );
    return r.map(PlaylistOnline.doMapa).toList();
  }

  Future<List<VideoOnline>> videos(int idPlaylist) async {
    final db = await Banco.catalogo;
    final r = await db.rawQuery(
      '''
      SELECT id, video_id, nome, ordem, thumb
        FROM onl_videos
       WHERE id_playlist = ?
       ORDER BY ordem, id
    ''',
      [idPlaylist],
    );
    return r.map(VideoOnline.doMapa).toList();
  }

  // ---------- Bíblia ----------

  Future<List<Map<String, Object?>>> versoesBiblia() async {
    final db = await Banco.catalogo;
    return db.query('biblia_versao', orderBy: 'sigla');
  }

  Future<List<Map<String, Object?>>> livrosBiblia() async {
    final db = await Banco.catalogo;
    return db.query('biblia_livro', orderBy: 'numero');
  }

  Future<int> totalCapitulos(int idLivro, int idVersao) async {
    final db = await Banco.catalogo;
    final r = await db.rawQuery(
      'SELECT MAX(capitulo) c FROM biblia_versiculo WHERE id_livro = ? AND id_versao = ?',
      [idLivro, idVersao],
    );
    return (r.first['c'] as int?) ?? 0;
  }

  Future<List<Versiculo>> capitulo(int idLivro, int cap, int idVersao) async {
    final db = await Banco.catalogo;
    final r = await db.rawQuery(
      '''
      SELECT l.nome AS livro, v.capitulo, v.versiculo, v.texto
        FROM biblia_versiculo v
        JOIN biblia_livro l ON l.id = v.id_livro
       WHERE v.id_livro = ? AND v.capitulo = ? AND v.id_versao = ?
       ORDER BY v.versiculo
    ''',
      [idLivro, cap, idVersao],
    );
    return r.map(Versiculo.doMapa).toList();
  }

  Future<List<Versiculo>> buscarNaBiblia(String termo, int idVersao) async {
    if (termo.trim().length < 3) return const [];
    final db = await Banco.catalogo;
    final r = await db.rawQuery(
      '''
      SELECT l.nome AS livro, v.capitulo, v.versiculo, v.texto
        FROM biblia_versiculo v
        JOIN biblia_livro l ON l.id = v.id_livro
       WHERE v.id_versao = ? AND v.texto LIKE ?
       ORDER BY l.numero, v.capitulo, v.versiculo
       LIMIT 200
    ''',
      [idVersao, '%${termo.trim()}%'],
    );
    return r.map(Versiculo.doMapa).toList();
  }
}
