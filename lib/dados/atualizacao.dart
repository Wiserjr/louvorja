import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'download.dart';

/// Atualização automática do próprio app, no mesmo padrão do app de
/// recadastramento: ao abrir, o app consulta um manifesto publicado junto com a
/// release, e havendo versão nova, baixa o APK e o entrega ao instalador do
/// sistema — que sempre pede a confirmação da pessoa. Ninguém precisa mais
/// mandar APK por WhatsApp a cada versão.
///
/// O canal é a última release do GitHub, onde o `publicar.ps1` já põe os APKs:
///
///     https://github.com/Wiserjr/louvorja/releases/latest/download/atualizacao-{pacote}.json
///
/// Um manifesto por app, com o identificador no nome, porque o mesmo código
/// gera dois apps (Louvor JA e Hinários, ver `-P paralelo=true`) que convivem
/// no aparelho e não podem receber um o APK do outro.
///
///     {
///       "applicationId": "br.com.wisejr.louvorja",
///       "versionCode": 11,
///       "versionName": "1.0.10",
///       "apks": { "arm64-v8a": "https://github.com/.../louvorja-arm64-v8a.apk", ... }
///     }
///
/// Tudo o que vem do manifesto é validado com o rigor do recadastramento: ele é
/// a porta por onde um APK entra no aparelho, e quem controlar esse arquivo não
/// deve conseguir apontar para outro servidor, outro app, nem pôr texto
/// arbitrário no diálogo.
class Atualizacao {
  Atualizacao._();
  static final Atualizacao instancia = Atualizacao._();

  static const repositorio = 'Wiserjr/louvorja';
  static const _canal = MethodChannel('br.com.wisejr.louvorja/atualizacao');

  /// O manifesto é pequeno; um teto baixo barra resposta estranha cedo.
  static const _tetoManifesto = 16 * 1024;

  /// O APK tem ~50 MB. O teto existe para servidor comprometido (ou proxy
  /// hostil) não encher o aparelho.
  static const _tetoApk = 200 * 1024 * 1024;

  final _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..idleTimeout = const Duration(seconds: 30)
    ..userAgent = Download.identificacao;

  /// Consulta o manifesto e devolve a atualização, ou `null` se o app já está
  /// na versão publicada.
  ///
  /// Lança [FalhaAtualizacao] quando não dá para saber — sem rede, manifesto
  /// ausente ou inválido. Quem chama decide se isso merece aviso: na checagem
  /// silenciosa da abertura, não merece.
  Future<InfoAtualizacao?> consultar() async {
    final pacote = (await PackageInfo.fromPlatform()).packageName;
    final instalada = await _canal.invokeMethod<int>('versaoInstalada') ?? 0;
    final abis = (await _canal.invokeListMethod<String>('abis')) ?? const [];

    final url = Uri.parse(
      'https://github.com/$repositorio/releases/latest/download/'
      'atualizacao-$pacote.json',
    );
    final corpo = await _get(url, teto: _tetoManifesto);
    final Object? json;
    try {
      // O PowerShell 5, que gera o manifesto no publicar.ps1, grava UTF-8 com
      // BOM se não for impedido; aceitá-lo aqui custa uma linha.
      final texto = utf8.decode(corpo);
      json = jsonDecode(
        texto.startsWith('\uFEFF') ? texto.substring(1) : texto,
      );
    } on FormatException {
      throw const FalhaAtualizacao('O manifesto da atualização é inválido.');
    }
    if (json is! Map<String, dynamic>) {
      throw const FalhaAtualizacao('O manifesto da atualização é inválido.');
    }
    return interpretarManifesto(
      json,
      pacote: pacote,
      versaoInstalada: instalada,
      abis: abis,
    );
  }

  /// Baixa o APK para o cache, onde o lado nativo o procura.
  ///
  /// Grava num `.parcial` e só renomeia no fim: uma queda no meio não deixa um
  /// APK truncado com o nome do bom.
  Future<void> baixar(
    InfoAtualizacao info, {
    void Function(int recebidos, int total)? aoProgredir,
    CancelToken? cancelamento,
  }) async {
    final dir = await getTemporaryDirectory();
    final destino = File(p.join(dir.path, 'atualizacao.apk'));
    final parcial = File('${destino.path}.parcial');
    if (await destino.exists()) await destino.delete();

    final resp = await _abrir(info.apk);
    final total = resp.contentLength;
    if (total > _tetoApk) {
      await resp.drain<void>();
      throw const FalhaAtualizacao(
        'O arquivo da atualização é maior do que o esperado.',
      );
    }

    final saida = parcial.openWrite();
    var recebidos = 0;
    try {
      await for (final pedaco in resp) {
        if (cancelamento?.cancelado ?? false) throw const DownloadCancelado();
        recebidos += pedaco.length;
        if (recebidos > _tetoApk) {
          throw const FalhaAtualizacao(
            'O arquivo da atualização é maior do que o esperado.',
          );
        }
        saida.add(pedaco);
        aoProgredir?.call(recebidos, total);
      }
      await saida.flush();
      await saida.close();
    } catch (e) {
      await saida.close();
      if (await parcial.exists()) await parcial.delete();
      if (e is DownloadCancelado || e is FalhaAtualizacao) rethrow;
      throw const FalhaAtualizacao(
        'O download foi interrompido. Confira a conexão e tente de novo.',
      );
    }
    if (total > 0 && recebidos != total) {
      await parcial.delete();
      throw const FalhaAtualizacao(
        'O download foi interrompido antes de terminar. Tente de novo.',
      );
    }
    await parcial.rename(destino.path);
  }

  /// Confere o APK baixado e o entrega ao instalador do sistema.
  ///
  /// A conferência repete, no arquivo de verdade, o que o manifesto prometeu:
  /// mesmo app e a versão anunciada. Um manifesto honesto apontando para o APK
  /// errado — do outro app, ou de uma versão velha — para aqui, antes do
  /// instalador.
  Future<void> instalar(InfoAtualizacao info) async {
    final pacote = (await PackageInfo.fromPlatform()).packageName;
    final apk = await _canal.invokeMapMethod<String, Object?>('conferirApk');
    if (apk == null) {
      throw const FalhaAtualizacao(
        'O arquivo da atualização chegou corrompido. Tente de novo.',
      );
    }
    final codigo = apk['versionCode'];
    if (apk['pacote'] != pacote ||
        codigo is! int ||
        versaoBase(codigo) != info.versionCode) {
      throw const FalhaAtualizacao(
        'O arquivo baixado não corresponde a esta atualização.',
      );
    }
    await _canal.invokeMethod<bool>('instalar');
  }

  /// Se o Android ainda não deixa este app instalar atualizações.
  Future<bool> precisaLiberarFonte() async =>
      await _canal.invokeMethod<bool>('precisaLiberarFonte') ?? false;

  /// Abre a tela da permissão e diz, na volta, se ela foi concedida.
  Future<bool> liberarFonte() async =>
      await _canal.invokeMethod<bool>('liberarFonte') ?? false;

  /// GET com o corpo inteiro na memória, até [teto] bytes.
  Future<List<int>> _get(Uri url, {required int teto}) async {
    final resp = await _abrir(url).timeout(const Duration(seconds: 15));
    final corpo = <int>[];
    await for (final pedaco in resp.timeout(const Duration(seconds: 15))) {
      corpo.addAll(pedaco);
      if (corpo.length > teto) {
        throw const FalhaAtualizacao('O manifesto da atualização é inválido.');
      }
    }
    return corpo;
  }

  /// Abre a URL seguindo redirecionamentos só para os hosts do GitHub.
  ///
  /// O GitHub responde `releases/latest/download/...` com um 302 para o CDN
  /// dele, então seguir redirecionamento é inevitável. O que não pode é
  /// seguir para qualquer lugar: cada salto é conferido.
  Future<HttpClientResponse> _abrir(Uri url) async {
    var atual = url;
    for (var saltos = 0; saltos < 5; saltos++) {
      if (!hostPermitido(atual)) {
        throw const FalhaAtualizacao(
          'A atualização aponta para um endereço não permitido.',
        );
      }
      final HttpClientResponse resp;
      try {
        final req = await _http.getUrl(atual);
        req.followRedirects = false;
        resp = await req.close();
      } on SocketException {
        throw const FalhaAtualizacao(
          'Sem conexão para consultar a atualização.',
        );
      } on HttpException {
        throw const FalhaAtualizacao(
          'Sem conexão para consultar a atualização.',
        );
      }
      if (resp.isRedirect) {
        final destino = resp.headers.value(HttpHeaders.locationHeader);
        await resp.drain<void>();
        if (destino == null) break;
        atual = atual.resolve(destino);
        continue;
      }
      if (resp.statusCode == HttpStatus.notFound) {
        await resp.drain<void>();
        throw const FalhaAtualizacao('Não há atualização publicada.');
      }
      if (resp.statusCode != HttpStatus.ok) {
        await resp.drain<void>();
        throw FalhaAtualizacao(
          'O servidor da atualização não respondeu (${resp.statusCode}).',
        );
      }
      return resp;
    }
    throw const FalhaAtualizacao('Redirecionamento demais na atualização.');
  }
}

/// Uma versão publicada mais nova que a instalada.
class InfoAtualizacao {
  const InfoAtualizacao({
    required this.versionCode,
    required this.versionName,
    required this.apk,
  });

  /// Versão-base, sem o acréscimo por arquitetura (ver [versaoBase]).
  final int versionCode;
  final String versionName;
  final Uri apk;
}

class FalhaAtualizacao implements Exception {
  const FalhaAtualizacao(this.motivo);

  final String motivo;

  @override
  String toString() => motivo;
}

/// A versão-base de um versionCode.
///
/// Com `--split-per-abi` o Flutter soma 1000 × a arquitetura ao número do
/// pubspec: o `+10` vira 1010 no armeabi-v7a, 2010 no arm64-v8a e 4010 no
/// x86_64. Comparar os números crus faria um arm64 na versão 10 (2010) se achar
/// mais novo que um armeabi na 11 (1011). O manifesto publica a base, e a
/// comparação é sempre entre bases — o que vale enquanto ela for menor que
/// 1000.
int versaoBase(int versionCode) => versionCode % 1000;

/// Se [url] está num host do GitHub por onde a release é servida.
bool hostPermitido(Uri url) =>
    url.scheme == 'https' &&
    !url.hasPort &&
    url.userInfo.isEmpty &&
    const {
      'github.com',
      'objects.githubusercontent.com',
      'release-assets.githubusercontent.com',
    }.contains(url.host);

final _caminhoApk = RegExp(
  '^/${RegExp.escape(Atualizacao.repositorio)}/releases/download/'
  r'[A-Za-z0-9._-]+/[A-Za-z0-9._-]+\.apk$',
);

final _formatoVersao = RegExp(r'^[0-9]{1,4}(\.[0-9]{1,4}){0,3}$');

/// Valida o manifesto e devolve a atualização, ou `null` se não há versão nova.
///
/// Lança [FalhaAtualizacao] para qualquer coisa fora do combinado. As mesmas
/// regras do recadastramento, pelos mesmos motivos:
///
/// - **applicationId igual ao do app.** Sem isso, o manifesto de um app
///   ofereceria o APK do outro.
/// - **Link só para uma release deste repositório**, em https, sem porta,
///   usuário, query ou fragmento.
/// - **versionName só com números e pontos.** Ele vai direto para o diálogo;
///   sem formato exigido, quem publica escreveria ali "APAGUE E REINSTALE O
///   APP" — o que aqui apagaria as músicas baixadas.
/// - **APK para a arquitetura do aparelho**, na ordem de preferência que o
///   próprio Android informa.
InfoAtualizacao? interpretarManifesto(
  Map<String, dynamic> json, {
  required String pacote,
  required int versaoInstalada,
  required List<String> abis,
}) {
  if (json['applicationId'] != pacote) {
    throw const FalhaAtualizacao('O manifesto é de outro aplicativo.');
  }
  final codigo = json['versionCode'];
  final nome = json['versionName'];
  final apks = json['apks'];
  if (codigo is! int || codigo <= 0 || codigo >= 1000) {
    throw const FalhaAtualizacao('Versão com formato inválido.');
  }
  if (nome is! String || !_formatoVersao.hasMatch(nome)) {
    throw const FalhaAtualizacao('Versão com formato inválido.');
  }
  if (apks is! Map<String, dynamic>) {
    throw const FalhaAtualizacao('O manifesto da atualização é inválido.');
  }

  if (codigo <= versaoBase(versaoInstalada)) return null;

  for (final abi in abis) {
    final link = apks[abi];
    if (link == null) continue;
    final url = link is String ? Uri.tryParse(link) : null;
    if (url == null ||
        !hostPermitido(url) ||
        url.host != 'github.com' ||
        url.hasQuery ||
        url.hasFragment ||
        !_caminhoApk.hasMatch(url.path)) {
      throw const FalhaAtualizacao('Link de atualização inválido.');
    }
    return InfoAtualizacao(versionCode: codigo, versionName: nome, apk: url);
  }
  throw const FalhaAtualizacao(
    'A atualização não tem versão para este aparelho.',
  );
}
