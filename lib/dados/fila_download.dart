import 'package:flutter/foundation.dart';

import 'download.dart';
import 'midia.dart';
import 'modelos.dart';

/// Uma faixa que não veio, com o motivo.
class ItemFalhou {
  const ItemFalhou({required this.musica, required this.motivo});

  final Musica musica;
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

  /// Descarta o que já existe e devolve só o que falta baixar.
  Future<List<Musica>> pendentes(List<Musica> musicas) async {
    final falta = <Musica>[];
    for (final m in musicas) {
      if (m.audio == null) continue;
      if (!await Midia.instancia.existe(m.audio!)) falta.add(m);
    }
    return falta;
  }

  static int bytesDe(List<Musica> musicas) =>
      musicas.fold(0, (s, m) => s + (m.audioBytes ?? 0));

  Future<void> iniciar(List<Musica> musicas) async {
    if (_rodando) return;
    _rodando = true;
    _cancelamento = CancelToken();

    estado.value = EstadoFila(total: musicas.length, rodando: true);

    var baixadas = 0;
    var bytes = 0;
    final falhas = <ItemFalhou>[];
    var pausa = _pausaNormal;
    var desacelerou = false;

    for (final m in musicas) {
      if (_cancelamento?.cancelado ?? true) break;

      estado.value = estado.value.copiar(
        atual: m.nome,
        progressoAtual: null,
        tentativa: 1,
        aguardando: false,
      );

      FalhaDownload? ultima;
      for (var tentativa = 1; tentativa <= _esperas.length + 1; tentativa++) {
        if (_cancelamento?.cancelado ?? true) break;
        try {
          await Download.instancia.baixar(
            m.id,
            m.audio!,
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
          bytes += m.audioBytes ?? 0;
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
        falhas.add(ItemFalhou(musica: m, motivo: ultima.motivo));
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

  /// Repete apenas as faixas que falharam.
  Future<void> repetirFalhas() async {
    final quais = estado.value.falhas.map((f) => f.musica).toList();
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
