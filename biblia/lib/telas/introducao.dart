import 'package:flutter/material.dart';

import '../dados/estudo.dart';
import '../dados/modelos.dart';
import '../dados/referencias.dart';
import 'tema.dart';

/// Introdução ao livro: autor, data, local, tema, esboço, mensagem, Cristo no
/// livro e onde Ellen G. White trata dele.
class TelaIntroducao extends StatefulWidget {
  const TelaIntroducao({super.key, required this.livro});
  final int livro;

  @override
  State<TelaIntroducao> createState() => _TelaIntroducaoState();
}

class _TelaIntroducaoState extends State<TelaIntroducao> {
  late final Future<Introducao?> _intro = Estudo.instancia.introducao(
    widget.livro,
  );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Introdução a ${Referencias.nome(widget.livro)}'),
      ),
      body: FutureBuilder<Introducao?>(
        future: _intro,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final i = snap.data;
          if (i == null) {
            return const Center(child: Text('Sem introdução para este livro.'));
          }
          Widget campo(String rotulo, String? valor, {IconData? icone}) {
            if (valor == null || valor.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (icone != null) ...[
                        Icon(icone, size: 18, color: t.colorScheme.primary),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        rotulo,
                        style: t.textTheme.labelLarge?.copyWith(
                          color: t.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    valor,
                    style: t.textTheme.bodyLarge?.copyWith(height: 1.5),
                  ),
                ],
              ),
            );
          }

          final esboco = (i['esboco'] ?? '')
              .split('\n')
              .where((l) => l.trim().isNotEmpty)
              .toList();
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    Referencias.nome(widget.livro),
                    style: t.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          _linha(context, 'Autor', i['autor']),
                          _linha(context, 'Data', i['data']),
                          _linha(context, 'Local', i['local']),
                          _linha(context, 'Para', i['destinatarios']),
                          _linha(
                            context,
                            'Versículo-chave',
                            i['versiculo_chave'],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  campo('Tema', i['tema'], icone: Icons.lightbulb_outline),
                  campo(
                    'Mensagem',
                    i['mensagem'],
                    icone: Icons.campaign_outlined,
                  ),
                  if (esboco.isNotEmpty) ...[
                    Row(
                      children: [
                        Icon(
                          Icons.list_alt,
                          size: 18,
                          color: t.colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Esboço',
                          style: t.textTheme.labelLarge?.copyWith(
                            color: t.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    for (final l in esboco)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text('•  $l', style: t.textTheme.bodyLarge),
                      ),
                    const SizedBox(height: 14),
                  ],
                  campo(
                    'Cristo no livro',
                    i['cristo'],
                    icone: Icons.favorite_border,
                  ),
                  Card(
                    color: corEgw(context).withValues(alpha: 0.08),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.menu_book_outlined,
                            color: corEgw(context),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Em Ellen G. White',
                                  style: t.textTheme.labelLarge?.copyWith(
                                    color: corEgw(context),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  i['egw'] ?? '',
                                  style: t.textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.tonalIcon(
                    onPressed: () =>
                        Navigator.pop(context, Posicao(widget.livro, 1)),
                    icon: const Icon(Icons.chrome_reader_mode_outlined),
                    label: const Text('Ler o livro'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _linha(BuildContext context, String rotulo, String? valor) {
    if (valor == null || valor.isEmpty) return const SizedBox.shrink();
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              rotulo,
              style: t.textTheme.labelMedium?.copyWith(color: t.hintColor),
            ),
          ),
          Expanded(child: Text(valor, style: t.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
