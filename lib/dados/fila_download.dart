import 'dart:io';

import 'package:flutter/foundation.dart';

import 'download.dart';
import 'midia.dart';
import 'modelos.dart';

/// Um arquivo da fila: o áudio cantado de uma música, ou o playback dela.
///
/// A fila trabalha com arquivos, não com músicas, porque a mesma música pode
/// render dois downloads — e cada um pode falhar, ou já existir, por conta
/// própria.
class ItemDownload {
  const ItemDownload(this.musica, {this.playback = false});

  final Musica musica;

  /// Faixa instrumental em vez da cantada.
  final bool playback;

  String get caminho => playback ? musica.audioPlayback! : musica.audio!;

  /// Como o item aparece no painel e na lista de falhas.
  String get nome => playback ? '${musica.nome} (playback)' : musica.nome;

  /// Tamanho estimado.
  ///
  /// O catálogo só traz o tamanho da faixa cantada. O playback é o mesmo
  /// arranjo sem as vozes, de duração parecida, então o tamanho da cantada é a
  /// melhor estimativa disponível — boa para o "cerca de" da confirmação, não
  /// para a conta do que foi gravado, que usa o arquivo de verdade.
  int get bytesEstimados => musica.audioBytes ?? 0;
}

/// Um arquivo que não veio, com o motivo.
class ItemFalhou {
  const ItemFalhou({required this.item, required this.motivo});

  final ItemDownload item;
  final String motivo;
}

/// Estado corrente da fila, observável pela interface.
///
/// Sucesso e falha são contadores **separados**. Somá-los, como a versão
/// anterior fazia, produzia "1635 de 1635" ao lado de "1252 falharam" — a barra
/// dizia concluído e o número dizia o contrário.
class EstadoFila {
  const EstadoFila({
    this.total = 0,
    this.baixadas = 0,
    this.falhas = const [],
    this.atual,
    this.progressoAtual,
    this.bytesBaixados = 0,
    this.rodando = false,
    this.tentativa = 1,
    this.aguardando = false,
    this.desacelerou = false,
  });

  final int total;

  /// Faixas efetivamente gravadas.
  final int baixadas;

  /// Faixas que desistiram depois das retentativas, com o motivo de cada uma.
  final List<ItemFalhou> falhas;

  final String? atual;
  final double? progressoAtual;
  final int bytesBaixados;
  final bool rodando;

  /// Tentativa em curso para a faixa atual (1 = primeira).
  final int tentativa;

  /// Verdadeiro durante a espera entre tentativas, para a interface poder
  /// dizer "aguardando" em vez de parecer travada.
  final bool aguardando;

  /// O servidor pediu calma em algum momento e a fila reduziu o ritmo.
  final bool desacelerou;

  int get processadas => baixadas + falhas.length;
  int get restantes => total - processadas;
  double get progressoGeral => total == 0 ? 0 : processadas / total;
  bool get terminou => total > 0 && !rodando && processadas >= total;

  EstadoFila copiar({
    int? total,
    int? baixadas,
    List<ItemFalhou>? falhas,
    Object? atual = _mantem,
    Object? progressoAtual = _mantem,
    int? bytesBaixados,
    bool? rodando,
    int? tentativa,
    bool? aguardando,
    bool? desacelerou,
  }) => EstadoFila(
    total: total ?? this.total,
    baixadas: baixadas ?? this.baixadas,
    falhas: falhas ?? this.falhas,
    atual: atual == _mantem ? this.atual : atual as String?,
    progressoAtual: progressoAtual == _mantem
        ? this.progressoAtual
        : progressoAtual as double?,
    bytesBaixados: bytesBaixados ?? this.bytesBaixados,
    rodando: rodando ?? this.rodando,
    tentativa: tentativa ?? this.tentativa,
    aguardando: aguardando ?? this.aguardando,
    desacelerou: desacelerou ?? this.desacelerou,
  );

  static const _mantem = Object();
}

/// Baixa muitas faixas em sequência, com retentativa e ritmo.
///
/// Vive fora das telas de propósito: sair da tela não deve interromper uma fila
/// de centenas de arquivos. A interface apenas observa [estado].
///
/// Três decisões moldam o comportamento:
///
/// - **Uma por vez.** Em paralelo, doze barras andariam devagar ao mesmo tempo e
///   o conjunto pareceria travado — além de multiplicar a carga no servidor.
/// - **Retentativa com espera crescente.** Num lote de 1.600 arquivos e 8 GB,
///   falha transitória não é exceção, é rotina. Desistir na primeira transforma
///   cada soluço de rede em perda definitiva.
/// - **Pausa entre arquivos, e recuo quando o servidor reclama.** Uma rajada de
///   milhares de requisições é o tipo de tráfego que proteções de servidor
///   cortam, e o acervo é hospedado por outra pessoa.
class FilaDownload {
  FilaDownload._();
  static final FilaDownload instancia = FilaDownload._();

  /// Esperas entre tentativas da mesma faixa.
  static const _esperas = [
    Duration(seconds: 2),
    Duration(seconds: 6),
    Duration(seconds: 15),
  ];

  /// Respiro entre faixas em ritmo normal.
  static const _pausaNormal = Duration(milliseconds: 300);

  /// Respiro depois de o servidor pedir calma.
  static const _pausaLenta = Duration(seconds: 3);

  final estado = ValueNotifier<EstadoFila>(const EstadoFila());

  CancelToken? _cancelamento;
  bool _rodando = false;

  bool get rodando => _rodando;

  /// Os arquivos que existem no acervo para [musicas], nos tipos pedidos.
  ///
  /// Cada música entra com a cantada seguida do playback, e não todas as
  /// cantadas antes de todos os playbacks: interrompido no meio, o lote deixa
  /// hinos completos, prontos para qualquer dos dois usos.
  static List<ItemDownload> itensDe(
    List<Musica> musicas, {
    bool cantado = true,
    bool playback = false,
  }) => [
    for (final m in musicas) ...[
      if (cantado && m.audio != null) ItemDownload(m),
      if (playback && m.audioPlayback != null) ItemDownload(m, playback: true),
    ],
  ];

  /// Descarta o que já existe e devolve só o que falta baixar.
  Future<List<ItemDownload>> pendentes(List<ItemDownload> itens) async {
    final falta = <ItemDownload>[];
    for (final i in itens) {
      if (!await Midia.instancia.existe(i.caminho)) falta.add(i);
    }
    return falta;
  }

  static int bytesDe(List<ItemDownload> itens) =>
      itens.fold(0, (s, i) => s + i.bytesEstimados);

  Future<void> iniciar(List<ItemDownload> itens) async {
    if (_rodando) return;
    _rodando = true;
    _cancelamento = CancelToken();

    estado.value = EstadoFila(total: itens.length, rodando: true);

    var baixadas = 0;
    var bytes = 0;
    final falhas = <ItemFalhou>[];
    var pausa = _pausaNormal;
    var desacelerou = false;

    for (final item in itens) {
      if (_cancelamento?.cancelado ?? true) break;

      estado.value = estado.value.copiar(
        atual: item.nome,
        progressoAtual: null,
        tentativa: 1,
        aguardando: false,
      );

      FalhaDownload? ultima;
      for (var tentativa = 1; tentativa <= _esperas.length + 1; tentativa++) {
        if (_cancelamento?.cancelado ?? true) break;
        try {
          final arquivo = await Download.instancia.baixar(
            item.musica.id,
            item.caminho,
            instrumental: item.playback,
            cancelamento: _cancelamento,
            aoProgredir: (recebidos, total) {
              if (total > 0) {
                estado.value = estado.value.copiar(
                  progressoAtual: recebidos / total,
                );
              }
            },
          );
          baixadas++;
          bytes += await _tamanhoDe(arquivo, item);
          ultima = null;
          break;
        } on DownloadCancelado {
          ultima = null;
          break;
        } on FalhaDownload catch (e) {
          ultima = e;
          if (e.pedeCalma) {
            // O servidor está limitando: desacelera pelo resto do lote, não só
            // nesta faixa.
            pausa = _pausaLenta;
            desacelerou = true;
          }
          if (!e.temporaria || tentativa > _esperas.length) break;
          estado.value = estado.value.copiar(
            tentativa: tentativa + 1,
            aguardando: true,
            progressoAtual: null,
            desacelerou: desacelerou,
          );
          await Future<void>.delayed(_esperas[tentativa - 1]);
          estado.value = estado.value.copiar(aguardando: false);
        } catch (e) {
          ultima = FalhaDownload(motivo: '$e', temporaria: false);
          break;
        }
      }

      if (ultima != null) {
        falhas.add(ItemFalhou(item: item, motivo: ultima.motivo));
      }

      estado.value = estado.value.copiar(
        baixadas: baixadas,
        falhas: List.unmodifiable(falhas),
        bytesBaixados: bytes,
        desacelerou: desacelerou,
      );

      if (!(_cancelamento?.cancelado ?? true)) {
        await Future<void>.delayed(pausa);
      }
    }

    _rodando = false;
    estado.value = estado.value.copiar(
      rodando: false,
      atual: null,
      progressoAtual: null,
      aguardando: false,
    );
  }

  /// Tamanho gravado de fato, com a estimativa do catálogo como reserva.
  ///
  /// O catálogo não traz o tamanho do playback, então somar a estimativa faria
  /// o contador de espaço usado mentir justamente nos lotes com playback.
  static Future<int> _tamanhoDe(File arquivo, ItemDownload item) async {
    try {
      return await arquivo.length();
    } on FileSystemException {
      return item.bytesEstimados;
    }
  }

  /// Repete apenas os arquivos que falharam.
  Future<void> repetirFalhas() async {
    final quais = estado.value.falhas.map((f) => f.item).toList();
    if (quais.isEmpty || _rodando) return;
    await iniciar(quais);
  }

  void limpar() {
    if (_rodando) return;
    estado.value = const EstadoFila();
  }

  void cancelar() {
    _cancelamento?.cancelar();
    _rodando = false;
    estado.value = estado.value.copiar(
      rodando: false,
      atual: null,
      aguardando: false,
    );
  }
}
