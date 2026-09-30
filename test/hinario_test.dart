import 'package:flutter_test/flutter_test.dart';
import 'package:louvorja/dados/hinario.dart';
import 'package:louvorja/dados/modelos.dart';

void main() {
  Musica hino(int numero, String nome) =>
      Musica(id: numero, nome: nome, faixa: numero);

  // Títulos reais dos dois hinários, com a pontuação e os acentos de origem.
  final hinos = [
    hino(1, 'Ó Deus de Amor'),
    hino(2, 'Ó, Adorai o Senhor'),
    hino(3, 'O Deus Eterno Reina'),
    hino(4, 'Louvor ao Trino Deus'),
    hino(10, 'Louvemos o Rei'),
    hino(14, 'Jubilosos Te Adoramos'),
    hino(40, 'Oh! Que Esperança!'),
    hino(43, 'Vem, Santo Espírito, Agora'),
    hino(430, 'Não Temas, Pequeno Rebanho'),
    hino(435, 'Santo, Santo, Santo!'),
  ];

  List<int> numeros(List<Musica> r) => [for (final m in r) m.faixa!];

  group('normalizar', () {
    test('tira acento, caixa e pontuação', () {
      expect(normalizar('Ó, Adorai o Senhor'), 'o adorai o senhor');
      expect(normalizar('Oh! Que Esperança!'), 'oh que esperanca');
      expect(normalizar('  Vem,   Santo  '), 'vem santo');
    });
  });

  group('busca por número', () {
    test('o número exato vem primeiro, seguido dos que começam por ele', () {
      expect(numeros(filtrarHinos(hinos, '43')), [43, 430, 435]);
    });

    test('um dígito já estreita a lista', () {
      expect(numeros(filtrarHinos(hinos, '4')), [4, 40, 43, 430, 435]);
    });

    test('número inexistente não devolve nada', () {
      expect(filtrarHinos(hinos, '999'), isEmpty);
    });

    test('dois hinos com o mesmo número aparecem juntos', () {
      // O hinário atual tem o 587 em duas versões, "A" e "B".
      final r = filtrarHinos([
        hino(586, 'Venham Todos'),
        Musica(id: 1, nome: 'Chegou a Hora - A', faixa: 587),
        Musica(id: 2, nome: 'Chegou a Hora - B', faixa: 587),
      ], '587');
      expect([for (final m in r) m.id], [1, 2]);
    });
  });

  group('busca por nome', () {
    test('ignora acento e pontuação', () {
      expect(numeros(filtrarHinos(hinos, 'o adorai')), [2]);
      expect(numeros(filtrarHinos(hinos, 'ESPERANCA')), [40]);
    });

    test('as palavras podem vir em qualquer ordem', () {
      expect(numeros(filtrarHinos(hinos, 'espirito vem')), [43]);
    });

    test('títulos que começam pelo termo sobem para o topo', () {
      expect(numeros(filtrarHinos(hinos, 'santo')), [435, 43]);
    });

    test('termo vazio devolve o hinário inteiro, na ordem', () {
      expect(filtrarHinos(hinos, '  '), hinos);
    });
  });

  group('estrofes', () {
    test('o slide vazio separa as estrofes', () {
      // Início real do hino 1 do hinário de 1996.
      final r = estrofes([
        'Ó Deus de amor\r\nvimos nós Te adorar',
        'Vós, ó nações\r\nrendei louvor',
        '',
        'Por Teu poder nos\r\ncriaste, Senhor',
        '',
      ]);
      expect(r, [
        [
          'Ó Deus de amor',
          'vimos nós Te adorar',
          'Vós, ó nações',
          'rendei louvor',
        ],
        ['Por Teu poder nos', 'criaste, Senhor'],
      ]);
    });

    test('vazios seguidos ou nas pontas não criam estrofe vazia', () {
      expect(estrofes(['', 'Amém', '', '', '']), [
        ['Amém'],
      ]);
    });

    test('letra sem separador vira uma estrofe só', () {
      expect(estrofes(['Paz\nPaz', 'Paz de Deus']), [
        ['Paz', 'Paz', 'Paz de Deus'],
      ]);
    });

    test('música sem letra não tem estrofes', () {
      expect(estrofes(const []), isEmpty);
    });
  });

  test('rótulo curto dos hinários', () {
    expect(rotuloDoHinario('Hinário Adventista'), 'Hinário Novo');
    expect(rotuloDoHinario('Hinário Adventista 1996'), 'Hinário 1996');
  });
}
