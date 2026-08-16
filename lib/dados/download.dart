import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Baixa mídia da API oficial do LouvorJA, como segunda fonte além da pasta
/// copiada à mão.
///
/// A API tem dois endpoints úteis aqui:
///
///     GET {base}/json_db/config        -> versão do acervo (115 bytes)
///     GET {base}/file/{caminho}        -> o MP3
///
/// Desde a versão 26.9 do programa, o caminho gravado no catálogo é o mesmo que
/// o servidor usa (`musics/pt/Álbum/Faixa.mp3`), então dá para montar a URL
/// direto, sem perguntar nada à API. Quando isso falha — um caminho que ficou
/// para trás numa renomeação — o id da música serve de plano B, porque os ids
/// se mantiveram estáveis desde 2024.
///
/// Os arquivos são gravados com o mesmo caminho relativo do catálogo, a mesma
/// convenção da pasta copiada à mão, para que a resolução de mídia não precise
/// saber de onde o arquivo veio.
class Download {
  Download._();
  static final Download instancia = Download._();

  static const chaveUrlBase = 'url_base_download';
  static const urlBasePadrao = 'https://api.louvorja.com.br';

  /// Host do antigo servidor de arquivos, desativado depois de 2024.
  static const _hostObsoleto = 'arquivos.louvorja.com.br';

  final _http = HttpClient()..connectionTimeout = const Duration(seconds: 20);

  /// URL base efetiva.
  ///
  /// Um endereço salvo apontando para o servidor desativado é descartado em
  /// favor do padrão atual. Sem isso, quem já usou uma versão anterior do app
  /// ficaria preso a um host que nem resolve em DNS, e o único sintoma seria o
  /// download falhar sempre.
  Future<String> get urlBase async {
    final prefs = await SharedPreferences.getInstance();
    final salva = prefs.getString(chaveUrlBase);
    if (salva == null || salva.contains(_hostObsoleto)) return urlBasePadrao;
    return salva;
  }

  Future<void> definirUrlBase(String url) async {
    final prefs = await SharedPreferences.getInstance();
    var v = url.trim();
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    await prefs.setString(chaveUrlBase, v);
  }

  /// Pasta onde a mídia baixada é gravada. Diretório privado do app: não exige
  /// permissão alguma e é limpo na desinstalação.
  Future<Directory> get pasta async {
    final base =
        await getExternalStorageDirectory() ??
        await getApplicationSupportDirectory();
    final d = Directory(p.join(base.path, 'midia'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<File> arquivoDe(String caminhoRelativo) async => File(
    p.join((await pasta).path, caminhoRelativo.replaceAll('/', p.separator)),
  );

  Future<bool> jaBaixado(String caminhoRelativo) async =>
      (await arquivoDe(caminhoRelativo)).exists();

  Uri _urlDe(String base, String caminho) => Uri.parse(
    '$base/file/${caminho.split('/').map(Uri.encodeComponent).join('/')}',
  );

  Future<String> _corpo(Uri url) async {
    final req = await _http.getUrl(url);
    final resp = await req.close();
    final texto = await resp.transform(utf8.decoder).join();
    if (resp.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${resp.statusCode}', uri: url);
    }
    return texto;
  }

  /// Consulta a versão do acervo publicada pela API.
  ///
  /// Serve de teste de conexão: são 115 bytes, contra os 2,2 MB que uma sonda
  /// em cima de um MP3 custaria — o servidor ignora o cabeçalho `Range` e
  /// devolve o arquivo inteiro.
  Future<ResultadoTeste> testarConexao() async {
    final base = await urlBase;
    final url = Uri.parse('$base/json_db/config');
    try {
      final json = jsonDecode(await _corpo(url)) as Map<String, dynamic>;
      return ResultadoTeste(
        ok: true,
        mensagem:
            'Acervo versão ${json['version_number']}, '
            'atualizado em ${json['latest_updated'] ?? '?'}.',
        url: url.toString(),
      );
    } on SocketException catch (e) {
      return ResultadoTeste(
        ok: false,
        mensagem: 'Servidor inacessível: ${e.osError?.message ?? e.message}',
        url: url.toString(),
      );
    } catch (e) {
      return ResultadoTeste(ok: false, mensagem: '$e', url: url.toString());
    }
  }

  /// Caminho do arquivo no servidor para a música [idMusica].
  ///
  /// [instrumental] pede a faixa de playback, quando existir.
  Future<String?> caminhoNoServidor(
    int idMusica, {
    bool instrumental = false,
  }) async {
    final base = await urlBase;
    final json = jsonDecode(
      await _corpo(Uri.parse('$base/json_db/music_$idMusica')),
    ) as Map<String, dynamic>;
    final campo = instrumental ? 'url_instrumental_music' : 'url_music';
    final v = json[campo];
    return (v is String && v.isNotEmpty) ? v : null;
  }

  /// Baixa o áudio de [idMusica], gravando em [caminhoRelativoLocal].
  ///
  /// Grava primeiro num arquivo `.parcial` e só então renomeia: uma queda de
  /// conexão no meio deixaria um MP3 truncado que o player aceitaria tocar, e o
  /// app o consideraria "já baixado".
  Future<File> baixar(
    int idMusica,
    String caminhoRelativoLocal, {
    bool instrumental = false,
    void Function(int recebidos, int total)? aoProgredir,
    CancelToken? cancelamento,
  }) async {
    final destino = await arquivoDe(caminhoRelativoLocal);
    if (await destino.exists()) return destino;

    final base = await urlBase;
    var url = _urlDe(base, caminhoRelativoLocal);

    await destino.parent.create(recursive: true);
    final parcial = File('${destino.path}.parcial');

    var resp = await (await _http.getUrl(url)).close();

    // Plano B: o caminho do catálogo não bateu com o do servidor. Pergunta pelo
    // id, que é estável, e tenta de novo.
    if (resp.statusCode == HttpStatus.notFound) {
      await resp.drain<void>();
      final doServidor = await caminhoNoServidor(
        idMusica,
        instrumental: instrumental,
      );
      if (doServidor == null) throw const SemArquivoNoServidor();
      url = _urlDe(base, doServidor);
      resp = await (await _http.getUrl(url)).close();
    }

    if (resp.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${resp.statusCode}', uri: url);
    }

    final total = resp.contentLength;
    var recebidos = 0;
    final saida = parcial.openWrite();
    try {
      await for (final pedaco in resp) {
        if (cancelamento?.cancelado ?? false) throw const DownloadCancelado();
        saida.add(pedaco);
        recebidos += pedaco.length;
        aoProgredir?.call(recebidos, total);
      }
      await saida.flush();
    } catch (_) {
      await saida.close();
      if (await parcial.exists()) await parcial.delete();
      rethrow;
    }
    await saida.close();

    await parcial.rename(destino.path);
    return destino;
  }

  /// Baixa um arquivo avulso do acervo — usado para as imagens de fundo dos
  /// slides, que não pertencem a nenhuma faixa em particular.
  ///
  /// Sem isto, quem usa só o download teria a letra sem o fundo: o áudio viria
  /// do servidor e a imagem, não.
  Future<File?> baixarArquivo(String caminhoRelativo) async {
    final destino = await arquivoDe(caminhoRelativo);
    if (await destino.exists()) return destino;

    final base = await urlBase;
    final resp = await (await _http.getUrl(_urlDe(base, caminhoRelativo)))
        .close();
    if (resp.statusCode != HttpStatus.ok) {
      await resp.drain<void>();
      return null;
    }

    await destino.parent.create(recursive: true);
    final parcial = File('${destino.path}.parcial');
    final saida = parcial.openWrite();
    try {
      await resp.pipe(saida);
    } catch (_) {
      await saida.close();
      if (await parcial.exists()) await parcial.delete();
      return null;
    }
    await parcial.rename(destino.path);
    return destino;
  }

  Future<void> remover(String caminhoRelativo) async {
    final f = await arquivoDe(caminhoRelativo);
    if (await f.exists()) await f.delete();
  }

  Future<int> bytesOcupados() async {
    final d = await pasta;
    var total = 0;
    await for (final e in d.list(recursive: true)) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  Future<void> limparTudo() async {
    final d = await pasta;
    if (await d.exists()) await d.delete(recursive: true);
  }
}

class ResultadoTeste {
  const ResultadoTeste({
    required this.ok,
    required this.mensagem,
    required this.url,
  });

  final bool ok;
  final String mensagem;
  final String url;
}

class CancelToken {
  bool cancelado = false;
  void cancelar() => cancelado = true;
}

class DownloadCancelado implements Exception {
  const DownloadCancelado();
  @override
  String toString() => 'Download cancelado';
}

class SemArquivoNoServidor implements Exception {
  const SemArquivoNoServidor();
  @override
  String toString() => 'O servidor não tem áudio para esta música';
}
