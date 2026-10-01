import 'dart:io';

import 'package:flutter/material.dart';

import '../dados/atualizacao.dart';

/// O fluxo da atualização do app na tela: aviso, permissão, download e entrega
/// ao instalador. Segue o do Louvor JA (e o do app de recadastramento) passo a
/// passo; no Windows, o "instalador" é o script que troca os arquivos quando o
/// app fecha (ver `Atualizacao._instalarWindows`).
class FluxoAtualizacao {
  FluxoAtualizacao._();

  static bool _emAndamento = false;

  /// Consulta e, havendo versão nova, oferece a atualização.
  ///
  /// [manual] é o botão de Ajustes: aí "já está atualizado" e as falhas de
  /// consulta merecem aviso. Na checagem da abertura, não — ninguém quer um
  /// aviso de "sem conexão" toda vez que abre o app fora do Wi-Fi.
  static Future<void> verificar(
    BuildContext context, {
    bool manual = false,
  }) async {
    if (_emAndamento) return;
    _emAndamento = true;
    final aviso = ScaffoldMessenger.maybeOf(context);
    void dizer(String texto) =>
        aviso?.showSnackBar(SnackBar(content: Text(texto)));

    try {
      final InfoAtualizacao? info;
      try {
        info = await Atualizacao.instancia.consultar();
      } on FalhaAtualizacao catch (e) {
        if (manual) dizer(e.motivo);
        return;
      } catch (_) {
        if (manual) {
          dizer(
            'Não foi possível consultar a versão. '
            'Confira a conexão e tente novamente.',
          );
        }
        return;
      }
      if (!context.mounted) return;
      if (info == null) {
        if (manual) dizer('O aplicativo está atualizado.');
        return;
      }

      final versao = info.versionName;
      final aceitou = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Atualização disponível'),
          content: Text(
            Platform.isWindows
                ? 'Versão $versao. O aplicativo baixa a atualização, fecha e '
                      'abre de novo já atualizado. Os livros baixados, as '
                      'marcações e as anotações continuam onde estão.'
                : 'Versão $versao. O aplicativo baixa sozinho e pede a '
                      'sua confirmação para instalar. A atualização entra por '
                      'cima da versão atual, sem desinstalar — os livros '
                      'baixados, as marcações e as anotações continuam onde '
                      'estão.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Agora não'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Atualizar'),
            ),
          ],
        ),
      );
      if (aceitou != true || !context.mounted) return;
      await _baixarEInstalar(context, info, dizer);
    } finally {
      _emAndamento = false;
    }
  }

  static Future<void> _baixarEInstalar(
    BuildContext context,
    InfoAtualizacao info,
    void Function(String) dizer,
  ) async {
    // A permissão de instalar é por aplicativo, e quem instalou este foi o
    // navegador: na primeira autoatualização de todo aparelho ela falta. A
    // volta da tela de ajustes continua o fluxo sozinha — sem isso a pessoa
    // liberava, voltava, e o botão "Atualizar" já não existia em lugar nenhum.
    if (await Atualizacao.instancia.precisaLiberarFonte()) {
      if (!context.mounted) return;
      final abrir = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Liberar a instalação'),
          content: const Text(
            'O Android pede a sua permissão para este aplicativo instalar '
            'atualizações. Vamos abrir a tela onde isso se liga; ao voltar, o '
            'download começa sozinho.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Agora não'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Abrir'),
            ),
          ],
        ),
      );
      if (abrir != true) return;
      if (!await Atualizacao.instancia.liberarFonte()) {
        dizer(
          'A permissão não foi concedida. Sem ela o aplicativo não consegue '
          'se atualizar sozinho.',
        );
        return;
      }
    }
    if (!context.mounted) return;

    final resultado = await showDialog<Object?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DialogoDownload(info),
    );
    if (resultado is FalhaAtualizacao) dizer(resultado.motivo);
    // true: entregue ao instalador, que mostra a própria confirmação.
  }
}

/// Barra de progresso do download. Fecha sozinho ao terminar, devolvendo
/// `true`, a falha, ou `null` se a pessoa cancelou.
class _DialogoDownload extends StatefulWidget {
  const _DialogoDownload(this.info);

  final InfoAtualizacao info;

  @override
  State<_DialogoDownload> createState() => _DialogoDownloadState();
}

class _DialogoDownloadState extends State<_DialogoDownload> {
  final _cancelamento = CancelToken();

  /// De 0 a 1; `null` enquanto o tamanho é desconhecido.
  double? _progresso;
  bool _instalando = false;

  @override
  void initState() {
    super.initState();
    _executar();
  }

  Future<void> _executar() async {
    Object? resultado;
    try {
      await Atualizacao.instancia.baixar(
        widget.info,
        cancelamento: _cancelamento,
        aoProgredir: (recebidos, total) {
          if (!mounted || total <= 0) return;
          setState(() => _progresso = recebidos / total);
        },
      );
      if (mounted) setState(() => _instalando = true);
      await Atualizacao.instancia.instalar(widget.info);
      resultado = true;
    } on DownloadCancelado {
      resultado = null;
    } on FalhaAtualizacao catch (e) {
      resultado = e;
    } catch (_) {
      resultado = const FalhaAtualizacao(
        'Não foi possível atualizar agora. Tente de novo mais tarde.',
      );
    }
    if (mounted) Navigator.of(context).pop(resultado);
  }

  @override
  Widget build(BuildContext context) {
    final pct = _progresso;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text('Baixando a versão ${widget.info.versionName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _instalando
                  ? (Platform.isWindows
                        ? 'Instalando: o aplicativo vai fechar e abrir de novo…'
                        : 'Abrindo o instalador…')
                  : (Platform.isWindows
                        ? 'Ao terminar, o aplicativo reinicia sozinho.'
                        : 'Ao terminar, o Android vai pedir a sua confirmação.'),
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _instalando ? null : pct),
            if (pct != null && !_instalando) ...[
              const SizedBox(height: 6),
              Text('${(pct * 100).round()}%'),
            ],
          ],
        ),
        actions: [
          if (!_instalando)
            TextButton(
              onPressed: _cancelamento.cancelar,
              child: const Text('Cancelar'),
            ),
        ],
      ),
    );
  }
}
