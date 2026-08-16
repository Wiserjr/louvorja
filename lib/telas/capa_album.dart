import 'package:flutter/material.dart';

import '../dados/modelos.dart';

/// A capa de um álbum, sempre quadrada.
///
/// As capas do acervo são quadradas na origem — 137×137, e 88×88 nas mais
/// antigas. Exibi-las numa célula mais alta com `BoxFit.cover` cortava a arte em
/// cima e embaixo, que era o enquadramento errado que o app mostrava.
///
/// O tamanho pequeno também é deliberado: com 137 px de origem, uma célula de
/// 150 px chega perto do 1:1 e fica nítida; esticar para 180 ou mais só deixa
/// o resultado borrado.
class CapaAlbum extends StatelessWidget {
  const CapaAlbum({super.key, required this.album, this.raio = 10});

  final Album album;
  final double raio;

  /// Cor do álbum vinda do catálogo (`#RRGGBB`), usada quando não há capa.
  Color? get _cor {
    final c = album.cor;
    if (c == null || !c.startsWith('#') || c.length < 7) return null;
    final v = int.tryParse(c.substring(1, 7), radix: 16);
    return v == null ? null : Color(0xFF000000 | v);
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(raio),
        child: Image.asset(
          album.assetCapa,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => _semCapa(context),
        ),
      ),
    );
  }

  /// Um álbum do acervo — "Músicas Infantis" — não tem imagem cadastrada na
  /// origem. Em vez de deixar um buraco cinza, o espaço vira uma peça sólida na
  /// cor do próprio álbum com a inicial, que se lê como parte do conjunto.
  Widget _semCapa(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final fundo = _cor ?? esquema.primaryContainer;
    final claro =
        ThemeData.estimateBrightnessForColor(fundo) == Brightness.light;
    final tinta = claro ? Colors.black87 : Colors.white;

    return Container(
      color: fundo,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.library_music_outlined, size: 28, color: tinta),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              album.nome,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: tinta, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
