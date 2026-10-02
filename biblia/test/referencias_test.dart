import 'package:biblia_estudo/dados/modelos.dart';
import 'package:biblia_estudo/dados/referencias.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatar', () {
    test('versículo, intervalo, capítulo inteiro, entre capítulos', () {
      expect(Referencias.formatar(43, 3016, 3016), 'João 3:16');
      expect(Referencias.formatar(43, 3016, 3017), 'João 3:16-17');
      expect(Referencias.formatar(19, 23000, 23999), 'Salmos 23');
      expect(Referencias.formatar(1, 4025, 6002), 'Gênesis 4:25-6:2');
      expect(Referencias.formatar(46, 13004, 13004, curto: true), '1Co 13:4');
    });
  });

  group('interpretar o que se digita na busca', () {
    test('formas comuns', () {
      expect(Referencias.interpretar('jo 3:16'), const Posicao(43, 3, 16));
      expect(Referencias.interpretar('João 3 16'), const Posicao(43, 3, 16));
      expect(Referencias.interpretar('joao 3.16'), const Posicao(43, 3, 16));
      expect(Referencias.interpretar('Jó 19:25'), const Posicao(18, 19, 25));
      expect(Referencias.interpretar('1co 13'), const Posicao(46, 13));
      expect(
        Referencias.interpretar('1 Coríntios 13:4'),
        const Posicao(46, 13, 4),
      );
      expect(Referencias.interpretar('salmo 23'), const Posicao(19, 23));
      expect(Referencias.interpretar('gen'), const Posicao(1, 1));
      expect(
        Referencias.interpretar('apocalipse 22:20'),
        const Posicao(66, 22, 20),
      );
    });

    test('livro de um capítulo: o número é o versículo', () {
      expect(Referencias.interpretar('Judas 3'), const Posicao(65, 1, 3));
    });

    test('o que não é referência', () {
      expect(Referencias.interpretar(''), isNull);
      expect(Referencias.interpretar('amor ao próximo'), isNull);
      expect(Referencias.interpretar('Mateus 29'), isNull);
    });
  });

  test('sem acento preserva o tamanho (o destaque da busca depende disso)', () {
    const s = 'Ação de graças à Deus, Êxodo';
    expect(Referencias.semAcento(s).length, s.length);
    expect(Referencias.semAcento(s), 'Acao de gracas a Deus, Exodo');
  });
}
