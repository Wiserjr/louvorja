import 'package:flutter/material.dart';

import '../dados/ajustes.dart';
import '../dados/modelos.dart';
import '../dados/referencias.dart';

/// Versículos marcados e anotados. Tocar leva ao versículo.
class TelaMarcacoes extends StatelessWidget {
  const TelaMarcacoes({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Marcações e anotações'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Marcações'),
              Tab(text: 'Anotações'),
            ],
          ),
        ),
        body: ListenableBuilder(
          listenable: Ajustes.instancia,
          builder: (context, _) {
            final marcas = Ajustes.instancia.todasMarcacoes();
            final notas = Ajustes.instancia.todasAnotacoes();
            String ref((int, int, int) k) =>
                '${Referencias.nome(k.$1)} ${k.$2}:${k.$3}';
            Widget vazio(String s) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  s,
                  textAlign: TextAlign.center,
                  style: t.textTheme.bodyMedium?.copyWith(color: t.hintColor),
                ),
              ),
            );
            return TabBarView(
              children: [
                marcas.isEmpty
                    ? vazio(
                        'Segure o dedo sobre um versículo (ou use o painel de '
                        'estudo) para marcá-lo com uma cor.',
                      )
                    : ListView(
                        children: [
                          for (final (k, cor) in marcas)
                            ListTile(
                              leading: CircleAvatar(
                                radius: 10,
                                backgroundColor:
                                    coresMarcacao[cor % coresMarcacao.length],
                              ),
                              title: Text(ref(k)),
                              onTap: () => Navigator.pop(
                                context,
                                Posicao(k.$1, k.$2, k.$3),
                              ),
                            ),
                        ],
                      ),
                notas.isEmpty
                    ? vazio('Suas anotações sobre os versículos aparecem aqui.')
                    : ListView(
                        children: [
                          for (final (k, texto) in notas)
                            ListTile(
                              leading: const Icon(Icons.edit_note),
                              title: Text(ref(k)),
                              subtitle: Text(
                                texto,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => Navigator.pop(
                                context,
                                Posicao(k.$1, k.$2, k.$3),
                              ),
                            ),
                        ],
                      ),
              ],
            );
          },
        ),
      ),
    );
  }
}
