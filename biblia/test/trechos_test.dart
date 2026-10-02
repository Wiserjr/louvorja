import 'dart:convert';
import 'dart:io';

import 'package:biblia_estudo/dados/trechos.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizar dá o mesmo que o indexador (casos compartilhados)', () {
    // Os mesmos casos de ferramentas/test_texto_pdf.py: se os dois lados
    // divergirem, o parágrafo recortado no aparelho não é o indexado.
    final casos = jsonDecode(
      File('test/dados/casos_normalizar.json').readAsStringSync(),
    ) as List;
    for (final c in casos) {
      expect(normalizar(c['cru'] as String), c['esperado'], reason: c['cru']);
    }
  });

  group('recortar', () {
    test('junta segmentos de páginas diferentes', () {
      final paginas = {
        3: 'cabeçalho\r\nComeço do parágrafo que se\r\nestende',
        4: '82 Título\r\naté a página seguinte. Outro parágrafo.',
      };
      final p3 = paginas[3]!, p4 = paginas[4]!;
      final texto = recortar(paginas, [
        (3, p3.indexOf('Começo'), p3.length),
        (4, p4.indexOf('até'), p4.indexOf(' Outro')),
      ]);
      expect(
        texto,
        'Começo do parágrafo que se estende até a página seguinte.',
      );
    });

    test('posições fora da página não quebram: devolvem vazio', () {
      expect(recortar({0: 'curto'}, [(0, 2, 99)]), isEmpty);
      expect(recortar({}, [(5, 0, 3)]), isEmpty);
    });

    test('posições contam em UTF-16, como no indexador', () {
      // Caractere fora do plano básico ocupa duas unidades.
      final paginas = {0: '𝔄 Deus é amor. 1 João 4:8.'};
      expect(recortar(paginas, [(0, 3, 15)]), 'Deus é amor.');
    });
  });

  group('contexto (quando o PDF mudou e a posição não vale)', () {
    const texto =
        'Primeira frase sem relação. Jesus respondeu: “Está escrito: Nem só '
        'de pão viverá o homem”. Mateus 4:4. Depois vem outra coisa. E mais.';

    test('volta ao início da frase e segue até o fim dela', () {
      final i = texto.indexOf('Mateus 4:4');
      final c = contexto(texto, i, i + 'Mateus 4:4'.length);
      expect(c, startsWith('… Jesus respondeu'));
      expect(c, contains('Mateus 4:4.'));
      expect(c, isNot(contains('Depois vem')));
    });

    test('no começo do texto, sem reticências na frente', () {
      final c = contexto('Mateus 4:4. Resto.', 0, 10);
      expect(c, startsWith('Mateus 4:4.'));
    });
  });
}
