import 'package:flutter_test/flutter_test.dart';
import 'package:louvorja/dados/midia.dart';

/// O acervo migrou de MP3 para Opus na versão 186 e o servidor passou a
/// devolver 404 para os .mp3. Quem copiou a pasta do PC antes disso tem os
/// MP3 no cartão e um catálogo que pede .opus — sem esta tradução, o app para
/// de achar mil músicas que estão ali, do lado.
void main() {
  test('troca nos dois sentidos', () {
    expect(
      Midia.trocarFormato('musics/pt/Album/Faixa.opus'),
      'musics/pt/Album/Faixa.mp3',
    );
    expect(
      Midia.trocarFormato('musics/pt/Album/Faixa.mp3'),
      'musics/pt/Album/Faixa.opus',
    );
  });

  test('preserva o caminho inteiro, com acento e hífen', () {
    expect(
      Midia.trocarFormato('musics/pt/1995 - A Diferença é Cristo/Em Ti - PB.mp3'),
      'musics/pt/1995 - A Diferença é Cristo/Em Ti - PB.opus',
    );
  });

  test('extensão em maiúscula também conta', () {
    expect(Midia.trocarFormato('a/b/C.MP3'), 'a/b/C.opus');
  });

  test('devolve nulo para o que não é áudio', () {
    // As imagens de fundo passam pelo mesmo uriDe; trocar extensão nelas
    // dispararia uma busca inútil a cada slide.
    expect(Midia.trocarFormato('images/generico_010.jpg'), isNull);
    expect(Midia.trocarFormato('covers/album.webp'), isNull);
    expect(Midia.trocarFormato('sem_extensao'), isNull);
  });

  test('não casa extensão no meio do nome', () {
    expect(Midia.trocarFormato('musics/pt/Album/mp3 do ensaio.opus'),
        'musics/pt/Album/mp3 do ensaio.mp3');
  });
}
