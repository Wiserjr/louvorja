import 'package:flutter/material.dart';

import '../dados/modelos.dart';
import '../dados/referencias.dart';

/// Escolha de livro e capítulo: abas AT/NT, grade de livros, grade de
/// capítulos.
class TelaSeletor extends StatefulWidget {
  const TelaSeletor({super.key, required this.atual});
  final Posicao atual;

  @override
  State<TelaSeletor> createState() => _TelaSeletorState();
}

class _TelaSeletorState extends State<TelaSeletor> {
  int? _livro;

  @override
  Widget build(BuildContext context) {
    final livro = _livro;
    if (livro != null) return _capitulos(context, livro);
    return DefaultTabController(
      length: 2,
      initialIndex: widget.atual.livro >= 40 ? 1 : 0,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Escolher livro'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Antigo Testamento'),
              Tab(text: 'Novo Testamento'),
            ],
          ),
        ),
        body: TabBarView(
          children: [_grade(context, 1, 39), _grade(context, 40, 66)],
        ),
      ),
    );
  }

  Widget _grade(BuildContext context, int de, int ate) {
    final t = Theme.of(context);
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 170,
        mainAxisExtent: 56,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: ate - de + 1,
      itemBuilder: (context, i) {
        final n = de + i;
        final atual = n == widget.atual.livro;
        return Material(
          color: atual
              ? t.colorScheme.primaryContainer
              : t.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              if (Referencias.capitulos[n - 1] == 1) {
                Navigator.pop(context, Posicao(n, 1));
              } else {
                setState(() => _livro = n);
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 36,
                    child: Text(
                      Referencias.abreviacao(n),
                      style: t.textTheme.labelMedium?.copyWith(
                        color: t.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      Referencias.nome(n),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _capitulos(BuildContext context, int livro) {
    final t = Theme.of(context);
    final total = Referencias.capitulos[livro - 1];
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => setState(() => _livro = null)),
        title: Text(Referencias.nome(livro)),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 64,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: total,
        itemBuilder: (context, i) {
          final cap = i + 1;
          final atual =
              livro == widget.atual.livro && cap == widget.atual.capitulo;
          return Material(
            color: atual
                ? t.colorScheme.primaryContainer
                : t.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => Navigator.pop(context, Posicao(livro, cap)),
              child: Center(
                child: Text('$cap', style: t.textTheme.titleMedium),
              ),
            ),
          );
        },
      ),
    );
  }
}
