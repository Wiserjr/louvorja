import 'package:saf_util/saf_util.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'banco.dart';
import 'download.dart';

/// Resolve os caminhos relativos do catálogo para URIs de arquivo no aparelho.
///
/// O catálogo guarda `musicas/1992 - Brilha Jesus/Brilha Jesus.mp3`. No Android
/// moderno isso não é um caminho de arquivo acessível: o usuário escolhe a pasta
/// pelo seletor do sistema (SAF) e o app recebe URIs `content://`.
///
/// Percorrer a árvore SAF a cada reprodução seria lento, então o resultado de
/// cada resolução fica gravado na tabela `midia` do banco do usuário.
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
  Future<String?> uriDe(String caminhoRelativo) async {
    final db = await Banco.usuario;
    final cache = await db.query(
      'midia',
      columns: ['uri'],
      where: 'caminho = ?',
      whereArgs: [caminhoRelativo],
      limit: 1,
    );
    if (cache.isNotEmpty) return cache.first['uri'] as String;

    // 1. pasta escolhida pelo usuário
    final r = await raiz;
    if (r != null) {
      final doc = await _saf.child(r, caminhoRelativo.split('/'));
      if (doc != null) {
        await db.insert('midia', {
          'caminho': caminhoRelativo,
          'uri': doc.uri,
          'bytes': doc.length,
        });
        return doc.uri;
      }
    }

    // 2. arquivo baixado pelo servidor
    final baixado = await Download.instancia.arquivoDe(caminhoRelativo);
    if (await baixado.exists()) {
      final uri = baixado.uri.toString();
      await db.insert('midia', {
        'caminho': caminhoRelativo,
        'uri': uri,
        'bytes': await baixado.length(),
      });
      return uri;
    }

    return null;
  }

  /// Esquece a entrada de [caminhoRelativo] no índice.
  ///
  /// Só é necessário ao **remover** um arquivo: ausências não são cacheadas,
  /// então um arquivo recém-baixado já é encontrado na consulta seguinte.
  Future<void> invalidar(String caminhoRelativo) async {
    final db = await Banco.usuario;
    await db.delete(
      'midia',
      where: 'caminho = ?',
      whereArgs: [caminhoRelativo],
    );
  }

  Future<bool> existe(String caminhoRelativo) async =>
      await uriDe(caminhoRelativo) != null;

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
          await db.insert('midia', {
            'caminho': caminho,
            'uri': item.uri,
            'bytes': item.length,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
          if (++total % 50 == 0) aoProgredir?.call(total);
        }
      }
    }

    await percorrer(r, '');
    aoProgredir?.call(total);
    return total;
  }
}
