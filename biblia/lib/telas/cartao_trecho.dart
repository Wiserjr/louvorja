import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dados/biblioteca.dart';
import '../dados/modelos.dart';
import '../dados/referencias.dart';
import '../dados/trechos.dart';
import 'leitor_pdf.dart';
import 'tema.dart';

/// Um trecho de Ellen G. White ou de um pioneiro ligado ao versículo.
///
/// Com o livro baixado, mostra o parágrafo (lido do PDF no aparelho); sem
/// ele, oferece baixar — um toque, alguns MB, do site do Centro White.
class CartaoTrecho extends StatefulWidget {
  const CartaoTrecho({super.key, required this.trecho});
  final Trecho trecho;

  @override
  State<CartaoTrecho> createState() => _CartaoTrechoState();
}

class _CartaoTrechoState extends State<CartaoTrecho> {
  Future<String?>? _texto;
  bool _expandido = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  void _carregar() {
    if (Biblioteca.instancia.disponivel(widget.trecho.obra)) {
      _texto = Trechos.instancia.texto(widget.trecho);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = widget.trecho;
    final t = Theme.of(context);
    final cor = corEgw(context);
    return ListenableBuilder(
      listenable: Biblioteca.instancia,
      builder: (context, _) {
        final bib = Biblioteca.instancia;
        if (_texto == null && bib.disponivel(tr.obra)) _carregar();
        return Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: cor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        tr.referencia,
                        style: t.textTheme.labelMedium?.copyWith(
                          color: cor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr.obra.titulo, style: t.textTheme.titleSmall),
                          if (!tr.obra.deEllenWhite)
                            Text(tr.obra.autor, style: t.textTheme.bodySmall),
                          if (tr.capitulo != null)
                            Text(
                              tr.capitulo!,
                              style: t.textTheme.bodySmall?.copyWith(
                                color: t.hintColor,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                _rotulo(context, tr),
                const SizedBox(height: 6),
                if (bib.disponivel(tr.obra))
                  _textoCarregado(context)
                else
                  _baixar(context, bib),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _rotulo(BuildContext context, Trecho tr) {
    final t = Theme.of(context);
    final passagem = Referencias.formatar(tr.livro, tr.ini, tr.fim);
    final texto = switch (tr.tipo) {
      TipoLigacao.capitulo => 'Capítulo baseado em $passagem',
      TipoLigacao.comentario => 'Comentário de $passagem',
      TipoLigacao.citacao => 'Cita $passagem',
    };
    return Text(
      texto,
      style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.tertiary),
    );
  }

  Widget _textoCarregado(BuildContext context) {
    final t = Theme.of(context);
    return FutureBuilder<String?>(
      future: _texto,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          );
        }
        final texto = snap.data;
        if (texto == null || snap.hasError) {
          return Row(
            children: [
              Expanded(
                child: Text(
                  'Não foi possível ler este trecho do livro.',
                  style: t.textTheme.bodySmall,
                ),
              ),
              _botaoAbrir(context),
            ],
          );
        }
        final longo = texto.length > 420;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              texto,
              maxLines: _expandido ? null : 7,
              overflow: _expandido ? null : TextOverflow.fade,
              style: t.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
            Row(
              children: [
                if (longo)
                  TextButton(
                    onPressed: () => setState(() => _expandido = !_expandido),
                    child: Text(_expandido ? 'Menos' : 'Ler tudo'),
                  ),
                const Spacer(),
                IconButton(
                  tooltip: 'Copiar com a referência',
                  icon: const Icon(Icons.copy, size: 20),
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(
                        text:
                            '$texto\n— ${widget.trecho.obra.autor}, '
                            '${widget.trecho.obra.titulo}, '
                            'p. ${widget.trecho.paginaOriginal ?? widget.trecho.pagina + 1}',
                      ),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Trecho copiado.')),
                    );
                  },
                ),
                _botaoAbrir(context),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _botaoAbrir(BuildContext context) => TextButton.icon(
    onPressed: () => abrirNoLivro(context, widget.trecho),
    icon: const Icon(Icons.open_in_new, size: 18),
    label: const Text('No livro'),
  );

  Widget _baixar(BuildContext context, Biblioteca bib) {
    final obra = widget.trecho.obra;
    final t = Theme.of(context);
    if (bib.baixando(obra) || bib.naFila(obra)) {
      final pr = bib.progresso(obra);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Baixando o livro…', style: t.textTheme.bodySmall),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: bib.naFila(obra) ? 0 : pr),
          ],
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          child: Text(
            'Baixe o livro para ler o trecho aqui.',
            style: t.textTheme.bodySmall,
          ),
        ),
        FilledButton.tonalIcon(
          onPressed: () async {
            try {
              await bib.baixar(obra);
            } on FalhaDownload catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(e.motivo)));
              }
            } catch (_) {}
          },
          icon: const Icon(Icons.download, size: 18),
          label: Text(tamanhoLegivel(obra.bytes)),
        ),
      ],
    );
  }
}

/// Abre o PDF na página do trecho (baixando antes, se preciso).
Future<void> abrirNoLivro(BuildContext context, Trecho tr) =>
    abrirObra(context, tr.obra, tr.pagina, destaque: tr.ancora);

/// Abre um livro numa página, oferecendo baixá-lo se ainda não estiver no
/// aparelho.
Future<void> abrirObra(
  BuildContext context,
  Obra obra,
  int pagina, {
  String? destaque,
}) async {
  final bib = Biblioteca.instancia;
  if (!bib.disponivel(obra)) {
    final baixar = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(obra.titulo),
        content: Text(
          'Este livro ainda não está no aparelho. Baixar agora do site do '
          'Centro White (${tamanhoLegivel(obra.bytes)})?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Agora não'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Baixar'),
          ),
        ],
      ),
    );
    if (baixar != true || !context.mounted) return;
    try {
      await bib.baixar(obra);
    } on FalhaDownload catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.motivo)));
      }
      return;
    } catch (_) {
      return;
    }
    if (!context.mounted) return;
  }
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => TelaPdf(obra: obra, pagina: pagina, destaque: destaque),
    ),
  );
}

/// Abre o trecho numa página própria (usado pelos atalhos de narrativa no
/// topo do capítulo).
Future<void> abrirTrechoCompleto(BuildContext context, Trecho tr) =>
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (c) => Scaffold(
          appBar: AppBar(title: Text(tr.obra.titulo)),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              CartaoTrecho(trecho: tr),
              const SizedBox(height: 8),
              Text(
                'O capítulo inteiro está no livro; toque em "No livro" para '
                'continuar a leitura.',
                style: Theme.of(c).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
