import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'download.dart';
import 'midia.dart';

/// Baixa de uma vez todos os fundos dos slides, num zip único.
///
/// Existe porque as imagens são selecionadas junto com os álbuns no empacotador
/// do PC: quem copia parte do acervo fica com parte dos fundos, e as demais
/// músicas passam a buscá-los na API durante a reprodução — dependendo de rede
/// no meio do culto e gerando rajadas que já estouraram o limite do servidor.
/// Quem instalou o APK pelo GitHub nem tem a pasta do PC para copiar.
///
/// São 1.003 imagens. Uma requisição a um zip na release resolve as duas
/// coisas: tira a carga da API e serve quem não tem o programa instalado.
///
/// A extração vai para a mesma pasta do download avulso, então nada mais no app
/// precisa mudar: `Midia.uriDe` já procura ali como segunda fonte, e ausências
/// não são cacheadas — a imagem extraída é encontrada na consulta seguinte.
class PacoteFundos {
  PacoteFundos._();

  static final PacoteFundos instancia = PacoteFundos._();

  /// Tag fixa, de propósito: não acompanha a versão do app.
  ///
  /// Com `releases/latest/...` toda release futura teria de carregar os 158 MB,
  /// senão a URL quebraria assim que uma nova virasse a mais recente. Numa tag
  /// própria o endereço nunca muda e as releases do app seguem leves.
  static const url =
      'https://github.com/Wiserjr/louvorja/releases/download/fundos/fundos.zip';

  /// Prefixo aceito dentro do zip. Ver [nomeSeguro].
  static const _prefixo = 'images/';

  final ValueNotifier<EstadoPacote> estado = ValueNotifier(
    const EstadoPacote(),
  );

  CancelToken? _cancelamento;

  final _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20)
    ..idleTimeout = const Duration(seconds: 30)
    ..userAgent = Download.identificacao;

  bool get ocupado => estado.value.etapa != Etapa.parado;

  void cancelar() => _cancelamento?.cancelar();

  /// Nome de entrada do zip aceitável, já normalizado para o disco.
  ///
  /// Um zip é dado de fora, e `../` numa entrada escreveria fora da pasta de
  /// destino. Mesmo sendo nosso o arquivo publicado, validar aqui é barato e
  /// evita que uma release trocada vire escrita arbitrária no aparelho.
  @visibleForTesting
  static String? nomeSeguro(String nome) {
    if (!nome.startsWith(_prefixo)) return null;
    if (nome.contains('..') || nome.contains('\\')) return null;
    final resto = nome.substring(_prefixo.length);
    if (resto.isEmpty || resto.contains('/')) return null;
    return nome;
  }

  /// Quantos dos [total] fundos do catálogo já estão no aparelho.
  ///
  /// Conta a pasta de download e a pasta copiada pelo usuário, porque as duas
  /// servem — quem já copiou tudo do PC não precisa baixar nada.
  Future<({int presentes, int total})> conferir(List<String> fundos) async {
    var presentes = 0;
    for (final rel in fundos) {
      if (await Midia.instancia.uriDe(rel) != null) presentes++;
    }
    return (presentes: presentes, total: fundos.length);
  }

  /// Baixa o zip e extrai. Lança [FalhaDownload] em erro de rede ou disco.
  Future<int> baixarEExtrair() async {
    if (ocupado) return 0;
    final cancelamento = CancelToken();
    _cancelamento = cancelamento;
    estado.value = const EstadoPacote(etapa: Etapa.baixando);

    final pasta = await Download.instancia.pasta;
    final zip = File(p.join(pasta.path, 'fundos.zip'));
    final parcial = File('${zip.path}.parcial');

    try {
      await _baixar(Uri.parse(url), parcial, cancelamento);
      if (await zip.exists()) await zip.delete();
      await parcial.rename(zip.path);
      return await _extrair(zip, pasta, cancelamento);
    } on DownloadCancelado {
      estado.value = const EstadoPacote();
      return 0;
    } catch (e) {
      estado.value = EstadoPacote(erro: _mensagem(e));
      rethrow;
    } finally {
      _cancelamento = null;
      if (await parcial.exists()) await parcial.delete();
      // O zip só serve durante a extração; guardá-lo dobraria o espaço ocupado.
      if (await zip.exists()) await zip.delete();
    }
  }

  Future<void> _baixar(Uri url, File destino, CancelToken cancelamento) async {
    late HttpClientResponse resp;
    try {
      final req = await _http.getUrl(url);
      resp = await req.close();
    } on SocketException catch (e) {
      throw FalhaDownload.rede(e.message);
    } on HttpException catch (e) {
      throw FalhaDownload.rede(e.message);
    }
    if (resp.statusCode != HttpStatus.ok) {
      await resp.drain<void>();
      throw FalhaDownload.http(resp.statusCode);
    }

    final total = resp.contentLength;
    var recebidos = 0;
    await destino.parent.create(recursive: true);
    final saida = destino.openWrite();
    try {
      await for (final pedaco in resp) {
        if (cancelamento.cancelado) throw const DownloadCancelado();
        saida.add(pedaco);
        recebidos += pedaco.length;
        estado.value = estado.value.copiar(
          etapa: Etapa.baixando,
          recebidos: recebidos,
          total: total,
        );
      }
    } finally {
      await saida.close();
    }
  }

  Future<int> _extrair(File zip, Directory pasta, CancelToken cancelamento) async {
    final entrada = InputFileStream(zip.path);
    var extraidos = 0;
    try {
      final arquivo = ZipDecoder().decodeStream(entrada);
      final validos = arquivo.files
          .where((f) => f.isFile && nomeSeguro(f.name) != null)
          .toList();

      estado.value = estado.value.copiar(
        etapa: Etapa.extraindo,
        extraidos: 0,
        aExtrair: validos.length,
      );

      for (final f in validos) {
        if (cancelamento.cancelado) throw const DownloadCancelado();
        final destino = File(
          p.join(pasta.path, f.name.replaceAll('/', p.separator)),
        );
        await destino.parent.create(recursive: true);
        final saida = OutputFileStream(destino.path);
        try {
          f.writeContent(saida);
        } finally {
          await saida.close();
        }
        extraidos++;
        estado.value = estado.value.copiar(extraidos: extraidos);
      }
    } on FileSystemException catch (e) {
      throw FalhaDownload.doSistemaDeArquivos(e);
    } finally {
      await entrada.close();
    }

    // Não há índice a invalidar: `Midia` não cacheia ausências, então as
    // imagens recém-extraídas são encontradas na consulta seguinte.
    estado.value = EstadoPacote(concluidos: extraidos);
    return extraidos;
  }

  String _mensagem(Object e) =>
      e is FalhaDownload ? e.motivo : 'Não foi possível baixar os fundos.';
}

enum Etapa { parado, baixando, extraindo }

@immutable
class EstadoPacote {
  const EstadoPacote({
    this.etapa = Etapa.parado,
    this.recebidos = 0,
    this.total = 0,
    this.extraidos = 0,
    this.aExtrair = 0,
    this.concluidos = 0,
    this.erro,
  });

  final Etapa etapa;

  /// Bytes recebidos e tamanho anunciado. [total] vem -1 em resposta chunked.
  final int recebidos;
  final int total;

  final int extraidos;
  final int aExtrair;

  /// Quantas imagens a última execução gravou. Zero enquanto roda.
  final int concluidos;

  final String? erro;

  /// 0 a 1, ou null quando não dá para saber — a UI mostra barra indefinida.
  double? get progresso => switch (etapa) {
    Etapa.baixando => total > 0 ? recebidos / total : null,
    Etapa.extraindo => aExtrair > 0 ? extraidos / aExtrair : null,
    Etapa.parado => null,
  };

  EstadoPacote copiar({
    Etapa? etapa,
    int? recebidos,
    int? total,
    int? extraidos,
    int? aExtrair,
    int? concluidos,
    String? erro,
  }) => EstadoPacote(
    etapa: etapa ?? this.etapa,
    recebidos: recebidos ?? this.recebidos,
    total: total ?? this.total,
    extraidos: extraidos ?? this.extraidos,
    aExtrair: aExtrair ?? this.aExtrair,
    concluidos: concluidos ?? this.concluidos,
    erro: erro ?? this.erro,
  );
}
