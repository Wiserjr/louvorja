import 'package:flutter/material.dart';

import '../dados/biblioteca.dart';
import '../dados/estudo.dart';
import '../dados/modelos.dart';
import '../dados/trechos.dart';
import 'leitor_pdf.dart';
import 'tema.dart';

/// Os livros de Ellen G. White e dos pioneiros: baixar, abrir, apagar.
class TelaBiblioteca extends StatefulWidget {
  const TelaBiblioteca({super.key});

  @override
  State<TelaBiblioteca> createState() => _TelaBibliotecaState();
}

class _TelaBibliotecaState extends State<TelaBiblioteca> {
  late final Future<Map<int, Obra>> _obras = Estudo.instancia.obras();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Biblioteca'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Ellen G. White'),
              Tab(text: 'Pioneiros'),
            ],
          ),
        ),
        body: FutureBuilder<Map<int, Obra>>(
          future: _obras,
          builder: (context, snap) {
            final obras = snap.data;
            if (obras == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final egw = [
              for (final o in obras.values)
                if (o.deEllenWhite) o,
            ]..sort((a, b) => a.titulo.compareTo(b.titulo));
            final pio = [
              for (final o in obras.values)
                if (!o.deEllenWhite) o,
            ]..sort((a, b) => a.titulo.compareTo(b.titulo));
            return ListenableBuilder(
              listenable: Biblioteca.instancia,
              builder: (context, _) => TabBarView(
                children: [_lista(context, egw), _lista(context, pio)],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _lista(BuildContext context, List<Obra> obras) {
    final bib = Biblioteca.instancia;
    final t = Theme.of(context);
    final faltam = [
      for (final o in obras)
        if (!bib.disponivel(o)) o,
    ];
    final tamanho = faltam.fold<int>(0, (s, o) => s + o.bytes);
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            'Os livros são baixados do site do Centro de Pesquisas Ellen G. '
            'White (centrowhite.org.br), para uso pessoal, e ficam só neste '
            'aparelho. Com eles baixados, os trechos aparecem no estudo de '
            'cada versículo mesmo sem internet.',
            style: t.textTheme.bodySmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              if (bib.tamanhoFila > 0) ...[
                Expanded(
                  child: Text(
                    'Baixando… faltam ${bib.tamanhoFila} livro(s).',
                    style: t.textTheme.bodyMedium,
                  ),
                ),
                TextButton(onPressed: bib.cancelar, child: const Text('Parar')),
              ] else if (faltam.isEmpty)
                Expanded(
                  child: Text(
                    'Todos os ${obras.length} livros estão no aparelho.',
                    style: t.textTheme.bodyMedium,
                  ),
                )
              else
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () async {
                      await bib.baixarVarias(faltam);
                      if (context.mounted && bib.ultimoErro != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(bib.ultimoErro!)),
                        );
                        bib.ultimoErro = null;
                      }
                    },
                    icon: const Icon(Icons.download),
                    label: Text(
                      'Baixar ${faltam.length} livro(s) '
                      '(${tamanhoLegivel(tamanho)})',
                    ),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        for (final o in obras) _ItemObra(obra: o),
      ],
    );
  }
}

class _ItemObra extends StatelessWidget {
  const _ItemObra({required this.obra});
  final Obra obra;

  @override
  Widget build(BuildContext context) {
    final bib = Biblioteca.instancia;
    final t = Theme.of(context);
    final estado = bib.estado(obra);
    final baixando = bib.baixando(obra) || bib.naFila(obra);
    Widget acao;
    if (baixando) {
      acao = SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
          value: bib.naFila(obra) ? null : bib.progresso(obra),
          strokeWidth: 3,
        ),
      );
    } else if (estado == EstadoObra.ausente) {
      acao = IconButton(
        tooltip: 'Baixar',
        icon: const Icon(Icons.download_outlined),
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
      );
    } else {
      acao = PopupMenuButton<String>(
        onSelected: (op) async {
          if (op == 'apagar') {
            await Trechos.instancia.fechar(obra);
            await bib.apagar(obra);
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'apagar', child: Text('Apagar do aparelho')),
        ],
      );
    }
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: corEgw(context).withValues(alpha: 0.12),
        child: Text(
          obra.sigla,
          style: TextStyle(
            fontSize: obra.sigla.length > 3 ? 10 : 12,
            fontWeight: FontWeight.bold,
            color: corEgw(context),
          ),
        ),
      ),
      title: Text(obra.titulo),
      subtitle: Text(
        [
          if (!obra.deEllenWhite) obra.autor,
          tamanhoLegivel(obra.bytes),
          if (estado == EstadoObra.pronta) 'no aparelho',
          if (estado == EstadoObra.outraEdicao) 'no aparelho (outra edição)',
        ].join(' · '),
        style: t.textTheme.bodySmall,
      ),
      trailing: acao,
      onTap: bib.disponivel(obra)
          ? () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => TelaPdf(obra: obra, pagina: 0)),
            )
          : null,
    );
  }
}
