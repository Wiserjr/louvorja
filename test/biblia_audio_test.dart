import 'package:flutter_test/flutter_test.dart';
import 'package:louvorja/dados/biblia_audio.dart';

/// A ponte entre o catálogo e a Bible Brain é a conversão do número do livro
/// (1 a 66, como está em `biblia_livro.numero`) para o código USFM que a API
/// espera. Um deslocamento de uma posição aqui não quebra nada visivelmente —
/// simplesmente toca o livro errado —, e é por isso que vale testar.
void main() {
  test('a lista USFM tem exatamente os 66 livros', () {
    expect(BibleBrain.livrosUsfm.length, 66);
    expect(BibleBrain.livrosUsfm.toSet().length, 66, reason: 'sem repetidos');
  });

  test('as âncoras do cânon caem no lugar certo', () {
    // Primeiro, último e as fronteiras que costumam sair deslocadas.
    expect(BibleBrain.usfmDoLivro(1), 'GEN');
    expect(BibleBrain.usfmDoLivro(19), 'PSA', reason: 'Salmos');
    expect(BibleBrain.usfmDoLivro(39), 'MAL', reason: 'fim do Antigo');
    expect(BibleBrain.usfmDoLivro(40), 'MAT', reason: 'início do Novo');
    expect(BibleBrain.usfmDoLivro(66), 'REV');
  });

  test('número fora da faixa devolve nulo em vez de estourar', () {
    expect(BibleBrain.usfmDoLivro(0), isNull);
    expect(BibleBrain.usfmDoLivro(67), isNull);
    expect(BibleBrain.usfmDoLivro(-3), isNull);
  });

  test('todo código tem três caracteres', () {
    for (final c in BibleBrain.livrosUsfm) {
      expect(c.length, 3, reason: 'código inesperado: $c');
    }
  });
}
