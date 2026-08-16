import 'package:flutter/foundation.dart';

import 'download.dart';
import 'midia.dart';
import 'modelos.dart';

/// Estado corrente da fila, observável pela interface.
class EstadoFila {
  const EstadoFila({
    this.total = 0,
    this.concluidas = 0,
    this.falhas = 0,
    this.atual,
    this.progressoAtual,
    this.bytesBaixados = 0,
    this.rodando = false,
  });

  final int total;
  final int concluidas;
  final int falhas;
  final String? atual;
  final double? progressoAtual;
  final int bytesBaixados;
  final bool rodando;

  double get progressoGeral => total == 0 ? 0 : concluidas / total;
  int get restantes => total - concluidas;

  EstadoFila copiar({
    int? total,
    int? concluidas,
    int? falhas,
    String? atual,
    double? progressoAtual,
    int? bytesBaixados,
    bool? rodando,
  }) => EstadoFila(
    total: total ?? this.total,
    concluidas: concluidas ?? this.concluidas,
    falhas: falhas ?? this.falhas,
    atual: atual ?? this.atual,
    progressoAtual: progressoAtual,
    bytesBaixados: bytesBaixados ?? this.bytesBaixados,
    rodando: rodando ?? this.rodando,
  );
}

/// Baixa muitas faixas em sequência.
///
/// Vive fora das telas de propósito: sair da tela de downloads não deve
/// interromper uma fila de centenas de arquivos. A interface apenas observa
/// [estado].
///
/// O download é **sequencial**. Em paralelo, doze barras andariam devagar ao
/// mesmo tempo e o conjunto pareceria travado, além de sobrecarregar o servidor
/// de quem hospeda o acervo.
class FilaDownload {
  FilaDownload._();
  static final FilaDownload instancia = FilaDownload._();

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

    var concluidas = 0;
    var falhas = 0;
    var bytes = 0;

    for (final m in musicas) {
      if (_cancelamento?.cancelado ?? true) break;
      estado.value = estado.value.copiar(atual: m.nome, progressoAtual: null);
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
        concluidas++;
        bytes += m.audioBytes ?? 0;
      } catch (_) {
        falhas++;
        concluidas++;
      }
      estado.value = estado.value.copiar(
        concluidas: concluidas,
        falhas: falhas,
        bytesBaixados: bytes,
      );
    }

    _rodando = false;
    estado.value = estado.value.copiar(rodando: false, atual: null);
  }

  void cancelar() {
    _cancelamento?.cancelar();
    _rodando = false;
    estado.value = estado.value.copiar(rodando: false, atual: null);
  }
}
