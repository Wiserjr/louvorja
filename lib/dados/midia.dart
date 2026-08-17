import 'package:saf_util/saf_util.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'banco.dart';
import 'download.dart';
import 'repositorio.dart';

/// Resolve os caminhos relativos do catálogo para URIs de arquivo no aparelho.
///
/// O catálogo guarda `musicas/1992 - Brilha Jesus/Brilha Jesus.mp3`. No Android
/// moderno isso não é um caminho de arquivo acessível: o usuário escolhe a pasta
/// pelo seletor do sistema (SAF) e o app recebe URIs `content://`.
///
/// Percorrer a árvore SAF a cada reprodução seria lento, então o resultado de
/// cada resolução fica gravado na tabela `midia` do banco do usuário.
///
/// **Cada arquivo entra no índice com duas chaves:** o caminho completo relativo
/// à pasta escolhida e o par `pasta/arquivo`. A segunda existe porque o
/// reconhecimento não pode depender de qual nível o usuário apontou no seletor —
/// escolher a pasta que contém `musics/pt/...` ou a própria `pt` mudaria todas as
/// chaves. O sufixo casa nos dois casos, e também quando a mídia foi copiada com
/// o layout antigo (`musicas/Álbum/Faixa.mp3`).
class Midia {
  Midia._();
  static final Midia instancia = Midia._();

  static const _chaveRaiz = 'pasta_midia_uri';
  final _saf = SafUtil();
  String? _raiz;

  Future<String?> get raiz async {
    if (_raiz != null) return _raiz;
    final prefs = await SharedPreferences.getInstance();
    return _raiz = prefs.getString(_chaveRaiz);
  }

  Future<bool> get configurada async {
    final r = await raiz;
    if (r == null) return false;
    // A permissão persistida pode ter sido revogada (app reinstalado, cartão
    // removido). Verificar evita erros silenciosos na primeira reprodução.
    return _saf.hasPersistedPermission(r, checkRead: true);
  }

  /// Abre o seletor do sistema para o usuário apontar a pasta LouvorJA.
  Future<bool> escolherPasta() async {
    final doc = await _saf.pickDirectory(
      writePermission: false,
      persistablePermission: true,
    );
    if (doc == null) return false;

    _raiz = doc.uri;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chaveRaiz, doc.uri);

    // Trocar de pasta invalida o índice anterior.
    final db = await Banco.usuario;
    await db.delete('midia');
    return true;
  }

  /// URI tocável de [caminhoRelativo], ou `null` se o arquivo não existir em
  /// nenhuma das duas fontes.
  ///
  /// A ordem importa: a pasta que o usuário copiou à mão vem primeiro, porque
  /// foi uma escolha explícita dele e normalmente vive no cartão de memória. O
  /// que foi baixado pelo servidor entra como complemento.
  ///
  /// O retorno pode ser um `content://` (pasta via SAF) ou um `file://`
  /// (download). O ExoPlayer lê os dois, então quem chama não precisa saber a
  /// diferença.
  /// Par `pasta/arquivo` de um caminho — a chave que sobrevive a mudanças de
  /// prefixo. `musics/pt/1995 - X/Y.mp3` vira `1995 - X/Y.mp3`.
  static String sufixoDe(String caminho) {
    final p = caminho.split('/');
    return p.length < 2 ? caminho : '${p[p.length - 2]}/${p.last}';
  }

  Future<String?> uriDe(String caminhoRelativo) async {
    final db = await Banco.usuario;
    final sufixo = sufixoDe(caminhoRelativo);

    final cache = await db.query(
      'midia',
      columns: ['uri'],
      where: 'chave = ? OR chave = ?',
      whereArgs: [caminhoRelativo, sufixo],
      limit: 1,
    );
    if (cache.isNotEmpty) return cache.first['uri'] as String;

    // 1. pasta escolhida pelo usuário
    final r = await raiz;
    if (r != null) {
      final doc = await _saf.child(r, caminhoRelativo.split('/'));
      if (doc != null) {
        await _gravar(db, caminhoRelativo, doc.uri, doc.length);
        return doc.uri;
      }
    }

    // 2. arquivo baixado pelo servidor
    final baixado = await Download.instancia.arquivoDe(caminhoRelativo);
    if (await baixado.exists()) {
      final uri = baixado.uri.toString();
      await _gravar(db, caminhoRelativo, uri, await baixado.length());
      return uri;
    }

    return null;
  }

  /// Grava as duas chaves apontando para o mesmo arquivo.
  Future<void> _gravar(
    Database db,
    String caminho,
    String uri,
    int bytes,
  ) async {
    for (final chave in {caminho, sufixoDe(caminho)}) {
      await db.insert('midia', {
        'chave': chave,
        'uri': uri,
        'bytes': bytes,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  /// Esquece a entrada de [caminhoRelativo] no índice.
  ///
  /// Só é necessário ao **remover** um arquivo: ausências não são cacheadas,
  /// então um arquivo recém-baixado já é encontrado na consulta seguinte.
  Future<void> invalidar(String caminhoRelativo) async {
    final db = await Banco.usuario;
    await db.delete(
      'midia',
      where: 'chave = ? OR chave = ?',
      whereArgs: [caminhoRelativo, sufixoDe(caminhoRelativo)],
    );
  }

  Future<bool> existe(String caminhoRelativo) async =>
      await uriDe(caminhoRelativo) != null;

  /// Quantas faixas do catálogo o índice já resolve.
  ///
  /// Responde à pergunta que o usuário faz ao ver metade do acervo tocando:
  /// "a pasta que eu copiei está certa?". Comparar em memória é o caminho —
  /// catálogo e índice vivem em bancos separados, então não há join possível, e
  /// 1.889 comparações de string custam milissegundos.
  Future<({int encontradas, int total})> cobertura() async {
    final caminhos = await const Repositorio().caminhosDeAudio();
    final db = await Banco.usuario;
    final chaves = {
      for (final r in await db.query('midia', columns: ['chave']))
        r['chave'] as String,
    };
    var achadas = 0;
    for (final c in caminhos) {
      if (chaves.contains(c) || chaves.contains(sufixoDe(c))) achadas++;
    }
    return (encontradas: achadas, total: caminhos.length);
  }

  /// Varre a pasta escolhida e preenche o índice de uma vez.
  ///
  /// Roda em segundo plano depois que o usuário escolhe a pasta; enquanto não
  /// termina, [uriDe] continua resolvendo sob demanda. [aoProgredir] recebe o
  /// total de arquivos indexados até o momento.
  Future<int> indexar({void Function(int)? aoProgredir}) async {
    final r = await raiz;
    if (r == null) return 0;

    final db = await Banco.usuario;
    var total = 0;

    Future<void> percorrer(String uri, String prefixo) async {
      for (final item in await _saf.list(uri)) {
        final caminho = prefixo.isEmpty ? item.name : '$prefixo/${item.name}';
        if (item.isDir) {
          await percorrer(item.uri, caminho);
        } else {
          await _gravar(db, caminho, item.uri, item.length);
          if (++total % 50 == 0) aoProgredir?.call(total);
        }
      }
    }

    await percorrer(r, '');
    aoProgredir?.call(total);
    return total;
  }
}
