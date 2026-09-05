import 'package:flutter_test/flutter_test.dart';
import 'package:louvorja/telas/tela_player.dart';

/// A ordem aleatória é o único pedaço da fila com lógica de verdade, e o modo
/// de errar é silencioso: ninguém percebe que uma música ficou de fora, só que
/// "às vezes repete". Estas asserções prendem as duas propriedades que fazem o
/// aleatório ser útil — cobertura total e a atual não ser trocada ao ligar.
void main() {
  test('a música atual encabeça a ordem', () {
    for (var atual = 0; atual < 10; atual++) {
      expect(ordemAleatoria(10, atual).first, atual);
    }
  });

  test('toda música aparece exatamente uma vez', () {
    final ordem = ordemAleatoria(40, 7);
    expect(ordem.length, 40);
    expect(ordem.toSet().length, 40, reason: 'sem repetidas');
    expect(ordem.toSet(), {for (var i = 0; i < 40; i++) i});
  });

  test('fila de uma música só devolve ela', () {
    expect(ordemAleatoria(1, 0), [0]);
  });

  test('embaralha de fato em fila grande', () {
    // Com 200 itens, a chance de sair na ordem natural é desprezível; se sair,
    // é porque o shuffle não rodou.
    final ordem = ordemAleatoria(200, 0);
    final natural = [for (var i = 0; i < 200; i++) i];
    expect(ordem, isNot(equals(natural)));
  });
}
