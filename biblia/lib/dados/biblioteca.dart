import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'modelos.dart';

/// Os PDFs de Ellen G. White e dos pioneiros no aparelho.
///
/// O app não traz esses livros: a licença dos e-books é de uso pessoal e não
/// permite redistribuir. Cada PDF é baixado direto do Centro de Pesquisas Ellen
/// G. White, como a pessoa faria pelo navegador, e fica guardado só aqui.
///
/// O índice que liga versículos a parágrafos foi feito sobre um arquivo exato
/// (tamanho e SHA-256 em `obra`). Depois do download o arquivo é conferido; se
/// o Centro White tiver publicado outra edição, o PDF continua utilizável, mas
/// os trechos passam a ser localizados pela busca da citação na página (ver
/// `trechos.dart`) em vez da posição exata.
class Biblioteca extends ChangeNotifier {
  Biblioteca._();
  static final Biblioteca instancia = Biblioteca._();

  /// Hosts de onde se aceita baixar (e para onde se aceita redirecionar).
  static const hosts = {'cdn.centrowhite.org.br', 'centrowhite.org.br'};

  Directory? _dir;
  final _estado = <int, EstadoObra>{};
  final _progresso = <int, double?>{};
  final _fila = <Obra>[];
  bool _baixando = false;
  bool _cancelarTudo = false;

  final _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20)
    ..idleTimeout = const Duration(seconds: 30)
    ..userAgent = 'BibliaDeEstudo (Android/Windows)';

  Future<Directory> pasta() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    final d = Directory(p.join(base.path, 'obras'));
    await d.create(recursive: true);
    return _dir = d;
  }

  Future<File> arquivo(Obra obra) async =>
      File(p.join((await pasta()).path, '${obra.arquivo}.pdf'));

  /// Lê o estado de todas as obras do disco (uma vez, na abertura).
  Future<void> carregar(Iterable<Obra> obras) async {
    for (final o in obras) {
      final f = await arquivo(o);
      if (!await f.exists()) {
        _estado[o.id] = EstadoObra.ausente;
        continue;
      }
      final marca = File('${f.path}.sha256');
      final sha = await marca.exists() ? await marca.readAsString() : null;
      _estado[o.id] = sha == o.sha256
          ? EstadoObra.pronta
          : EstadoObra.outraEdicao;
    }
    notifyListeners();
  }

  EstadoObra estado(Obra obra) => _estado[obra.id] ?? EstadoObra.ausente;

  bool disponivel(Obra obra) {
    final e = estado(obra);
    return e == EstadoObra.pronta || e == EstadoObra.outraEdicao;
  }

  /// `null` = baixando sem tamanho conhecido; ausente = não está baixando.
  double? progresso(Obra obra) => _progresso[obra.id];
  bool baixando(Obra obra) => _progresso.containsKey(obra.id);
  bool naFila(Obra obra) => _fila.any((o) => o.id == obra.id);
  int get tamanhoFila => _fila.length + (_baixando ? 1 : 0);

  /// Põe na fila e baixa uma de cada vez. O Future completa quando ESTA obra
  /// termina (ou falha).
  Future<void> baixar(Obra obra) async {
    if (disponivel(obra) || naFila(obra) || baixando(obra)) return;
    _fila.add(obra);
    _cancelarTudo = false;
    notifyListeners();
    final concluida = Completer<void>();
    _aguardando[obra.id] = concluida;
    unawaited(_processar());
    return concluida.future;
  }

  final _aguardando = <int, Completer<void>>{};

  Future<void> baixarVarias(Iterable<Obra> obras) async {
    for (final o in obras) {
      if (!disponivel(o) && !naFila(o) && !baixando(o)) {
        _fila.add(o);
      }
    }
    _cancelarTudo = false;
    notifyListeners();
    await _processar();
  }

  void cancelar() {
    _cancelarTudo = true;
    for (final o in _fila) {
      _aguardando.remove(o.id)?.completeError(const DownloadCancelado());
    }
    _fila.clear();
    notifyListeners();
  }

  Future<void> _processar() async {
    if (_baixando) return;
    _baixando = true;
    try {
      while (_fila.isNotEmpty && !_cancelarTudo) {
        final obra = _fila.removeAt(0);
        try {
          await _baixarUma(obra);
          _aguardando.remove(obra.id)?.complete();
        } catch (e) {
          _aguardando.remove(obra.id)?.completeError(e);
          if (e is DownloadCancelado) break;
          ultimoErro = e is FalhaDownload
              ? e.motivo
              : 'Não foi possível baixar "${obra.titulo}".';
        }
      }
    } finally {
      _baixando = false;
      notifyListeners();
    }
  }

  /// A última falha de download, para a tela mostrar.
  String? ultimoErro;

  Future<void> _baixarUma(Obra obra) async {
    final destino = await arquivo(obra);
    final parcial = File('${destino.path}.parcial');
    _progresso[obra.id] = 0;
    notifyListeners();
    try {
      final resp = await _abrir(Uri.parse(obra.url));
      final total = resp.contentLength;
      // Teto: algumas vezes o tamanho indexado, contra servidor que devolva
      // outra coisa enorme.
      final teto = obra.bytes * 4 + 20 * 1024 * 1024;
      if (total > teto) {
        await resp.drain<void>();
        throw const FalhaDownload('O arquivo é maior do que o esperado.');
      }
      final tipo = resp.headers.contentType?.mimeType ?? '';
      if (tipo.startsWith('text/')) {
        await resp.drain<void>();
        throw const FalhaDownload(
          'O site devolveu uma página em vez do livro. Tente mais tarde.',
        );
      }
      final saida = parcial.openWrite();
      final soma = _AcumuladorSha();
      var recebidos = 0;
      var ultimoAviso = DateTime.now();
      try {
        await for (final pedaco in resp) {
          if (_cancelarTudo) throw const DownloadCancelado();
          recebidos += pedaco.length;
          if (recebidos > teto) {
            throw const FalhaDownload('O arquivo é maior do que o esperado.');
          }
          saida.add(pedaco);
          soma.add(pedaco);
          final agora = DateTime.now();
          if (agora.difference(ultimoAviso).inMilliseconds > 150) {
            ultimoAviso = agora;
            _progresso[obra.id] = total > 0 ? recebidos / total : null;
            notifyListeners();
          }
        }
        await saida.flush();
      } finally {
        await saida.close();
      }
      if (total > 0 && recebidos != total) {
        throw const FalhaDownload(
          'O download foi interrompido. Confira a conexão e tente de novo.',
        );
      }
      if (!await _pareceePdf(parcial)) {
        throw const FalhaDownload('O arquivo baixado não é um PDF.');
      }
      final sha = soma.fechar();
      if (await destino.exists()) await destino.delete();
      await parcial.rename(destino.path);
      await File('${destino.path}.sha256').writeAsString(sha);
      _estado[obra.id] = sha == obra.sha256
          ? EstadoObra.pronta
          : EstadoObra.outraEdicao;
    } on SocketException {
      throw const FalhaDownload(
        'Sem conexão para baixar o livro. Confira a internet.',
      );
    } on HttpException {
      throw const FalhaDownload(
        'A conexão caiu durante o download. Tente de novo.',
      );
    } finally {
      _progresso.remove(obra.id);
      if (await parcial.exists()) {
        try {
          await parcial.delete();
        } catch (_) {}
      }
      notifyListeners();
    }
  }

  Future<bool> _pareceePdf(File f) async {
    final raf = await f.open();
    try {
      final cabeca = await raf.read(5);
      return String.fromCharCodes(cabeca) == '%PDF-';
    } finally {
      await raf.close();
    }
  }

  Future<HttpClientResponse> _abrir(Uri url) async {
    var atual = url;
    for (var saltos = 0; saltos < 5; saltos++) {
      if (!urlPermitida(atual)) {
        throw const FalhaDownload('Endereço de download não permitido.');
      }
      final req = await _http.getUrl(atual);
      req.followRedirects = false;
      final resp = await req.close();
      if (resp.isRedirect) {
        final destino = resp.headers.value(HttpHeaders.locationHeader);
        await resp.drain<void>();
        if (destino == null) break;
        atual = atual.resolve(destino);
        continue;
      }
      if (resp.statusCode == HttpStatus.notFound) {
        await resp.drain<void>();
        throw const FalhaDownload(
          'O livro não está mais neste endereço do Centro White. '
          'Procure uma atualização do app.',
        );
      }
      if (resp.statusCode != HttpStatus.ok) {
        await resp.drain<void>();
        throw FalhaDownload(
          'O site do Centro White não respondeu (${resp.statusCode}).',
        );
      }
      return resp;
    }
    throw const FalhaDownload('Redirecionamento demais.');
  }

  Future<void> apagar(Obra obra) async {
    final f = await arquivo(obra);
    for (final x in [f, File('${f.path}.sha256')]) {
      if (await x.exists()) await x.delete();
    }
    _estado[obra.id] = EstadoObra.ausente;
    notifyListeners();
  }

  /// Espaço ocupado pelos PDFs baixados.
  Future<int> espacoUsado() async {
    var total = 0;
    await for (final e in (await pasta()).list()) {
      if (e is File && e.path.endsWith('.pdf')) total += await e.length();
    }
    return total;
  }
}

/// Só https, sem porta nem usuário, nos hosts do Centro White.
bool urlPermitida(Uri url) =>
    url.scheme == 'https' &&
    !url.hasPort &&
    url.userInfo.isEmpty &&
    Biblioteca.hosts.contains(url.host);

enum EstadoObra { ausente, pronta, outraEdicao }

class FalhaDownload implements Exception {
  const FalhaDownload(this.motivo);
  final String motivo;
  @override
  String toString() => motivo;
}

class DownloadCancelado implements Exception {
  const DownloadCancelado();
}

/// SHA-256 calculado durante o download, sem reler o arquivo.
class _AcumuladorSha {
  _AcumuladorSha() {
    _entrada = sha256.startChunkedConversion(_saida);
  }

  final _saida = _Coletor();
  late final ByteConversionSink _entrada;

  void add(List<int> dados) => _entrada.add(dados);

  String fechar() {
    _entrada.close();
    return _saida.valor.toString();
  }
}

class _Coletor implements Sink<Digest> {
  late Digest valor;
  @override
  void add(Digest data) => valor = data;
  @override
  void close() {}
}

String tamanhoLegivel(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024).round()} KB';
}
