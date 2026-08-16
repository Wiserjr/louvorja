import 'package:flutter_test/flutter_test.dart';
import 'package:louvorja/dados/modelos.dart';
import 'package:louvorja/player/sincronia.dart';

/// Estes testes descrevem UMA das respostas possíveis para o TODO de
/// `Sincronizador.indiceEm`. Se você decidir diferente — por exemplo, já mostrar
/// o primeiro verso durante a introdução — ajuste as expectativas aqui.
void main() {
  Slide slide(int ordem, int ms, String texto) =>
      Slide(id: ordem, ordem: ordem, texto: texto, ms: ms, msPlayback: ms);

  // Tempos reais de "Nosso Sol é Jesus", primeira música do acervo.
  final slides = [
    slide(1, 8000, 'O nosso sol\nVeio iluminar'),
    slide(2, 17000, 'O caminho que\nvamos andar'),
    slide(3, 25000, 'Quero sempre viver\nCom essa Grande Luz'),
  ];
  final sinc = Sincronizador(slides);

  test('durante a introducao instrumental nao ha slide na tela', () {
    expect(sinc.indiceEm(const Duration(milliseconds: 0)), isNull);
    expect(sinc.indiceEm(const Duration(milliseconds: 7999)), isNull);
  });

  test('o slide entra exatamente no seu instante', () {
    expect(sinc.indiceEm(const Duration(milliseconds: 8000)), 0);
    expect(sinc.indiceEm(const Duration(milliseconds: 17000)), 1);
  });

  test('o verso permanece na tela ate o proximo entrar', () {
    expect(sinc.indiceEm(const Duration(milliseconds: 16999)), 0);
    expect(sinc.indiceEm(const Duration(milliseconds: 24999)), 1);
  });

  test('o ultimo verso permanece ate o fim da musica', () {
    expect(sinc.indiceEm(const Duration(minutes: 3)), 2);
  });

  test('musica sem letra nao quebra', () {
    final vazio = Sincronizador(const []);
    expect(vazio.vazio, isTrue);
    expect(vazio.indiceEm(const Duration(seconds: 10)), isNull);
  });

  testesDeSlideVazio();

  test('fimDoSlide aponta para a entrada do proximo', () {
    expect(sinc.fimDoSlide(0), const Duration(milliseconds: 17000));
    expect(sinc.fimDoSlide(2), isNull, reason: 'o ultimo nao tem fim definido');
  });
}

/// Caso extra: os slides de texto vazio são a forma que o acervo tem de dizer
/// "limpe a tela agora". Devem ser tratados como qualquer outro slide.
void testesDeSlideVazio() {
  test('slide vazio entra no seu instante como qualquer outro', () {
    final comLimpeza = Sincronizador([
      Slide(id: 1, ordem: 1, texto: 'Primeiro verso', ms: 5000, msPlayback: 5000),
      Slide(id: 2, ordem: 2, texto: '', ms: 12000, msPlayback: 12000),
      Slide(id: 3, ordem: 3, texto: 'Segundo verso', ms: 20000, msPlayback: 20000),
    ]);
    expect(comLimpeza.indiceEm(const Duration(milliseconds: 11999)), 0);
    expect(comLimpeza.indiceEm(const Duration(milliseconds: 12000)), 1);
    expect(comLimpeza.slideEm(const Duration(milliseconds: 15000))?.texto, '');
    expect(comLimpeza.indiceEm(const Duration(milliseconds: 20000)), 2);
  });
}
