import 'package:flutter/material.dart';

import '../dados/modelos.dart';

/// Cartão do versículo do dia, no topo da lista de livros.
///
/// Toque abre o capítulo no leitor — quem se interessou pelo versículo
/// costuma querer o contexto em volta. O ícone leva ao cartão de imagem, que
/// é o caminho de quem já decidiu compartilhar.
class CartaoDoDia extends StatelessWidget {
  const CartaoDoDia({
    super.key,
    required this.versiculos,
    required this.onAbrir,
    required this.onCompartilhar,
    this.sigla,
  });

  final List<Versiculo> versiculos;
  final VoidCallback onAbrir;
  final VoidCallback onCompartilhar;
  final String? sigla;

  /// "João 3:16" ou "Isaías 43:18-19".
  String get _referencia {
    final primeiro = versiculos.first;
    final ultimo = versiculos.last;
    final faixa = ultimo.numero > primeiro.numero
        ? '${primeiro.numero}-${ultimo.numero}'
        : '${primeiro.numero}';
    return '${primeiro.livro} ${primeiro.capitulo}:$faixa';
  }

  @override
  Widget build(BuildContext context) {
    if (versiculos.isEmpty) return const SizedBox.shrink();

    final cores = Theme.of(context).colorScheme;
    final texto = versiculos.map((v) => v.texto).join(' ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Card(
        margin: EdgeInsets.zero,
        color: cores.secondaryContainer,
        child: InkWell(
          onTap: onAbrir,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.wb_sunny_outlined,
                      size: 16,
                      color: cores.onSecondaryContainer,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Versículo do dia',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: cores.onSecondaryContainer,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Compartilhar como imagem',
                      visualDensity: VisualDensity.compact,
                      onPressed: onCompartilhar,
                      icon: Icon(
                        Icons.ios_share,
                        size: 20,
                        color: cores.onSecondaryContainer,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    texto,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cores.onSecondaryContainer,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  sigla == null ? _referencia : '$_referencia · $sigla',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cores.onSecondaryContainer.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
