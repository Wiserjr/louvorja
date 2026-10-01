import 'package:flutter/material.dart';

import '../dados/modelos.dart';

/// Pedido de leitura vindo de qualquer tela empilhada (mapa, tema, estudo):
/// a tela inicial escuta, fecha o que estiver por cima e abre o versículo.
final destinoLeitura = ValueNotifier<Posicao?>(null);

void irParaVersiculo(BuildContext context, Posicao p) {
  Navigator.of(context).popUntil((r) => r.isFirst);
  destinoLeitura.value = p;
}
