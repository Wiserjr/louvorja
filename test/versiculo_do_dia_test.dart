import 'package:flutter_test/flutter_test.dart';
import 'package:louvorja/dados/versiculo_do_dia.dart';

/// O calendário é indexado por dia do ano, então essa conta é a única peça de
/// lógica entre a data do aparelho e a passagem que aparece na tela. Errar por
/// um dia não quebra nada visivelmente — mostra o versículo de ontem —, e por
/// isso vale testar as bordas: virada de ano, ano bissexto e horário de verão.
void main() {
  // Necessário para o rootBundle enxergar o asset do calendário.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('o primeiro e o último dia caem onde deveriam', () {
    expect(VersiculoDoDia.diaDoAno(DateTime(2026, 1, 1)), 1);
    expect(VersiculoDoDia.diaDoAno(DateTime(2026, 12, 31)), 365);
  });

  test('ano bissexto tem 366 dias', () {
    expect(VersiculoDoDia.diaDoAno(DateTime(2028, 12, 31)), 366);
    expect(VersiculoDoDia.diaDoAno(DateTime(2028, 2, 29)), 60);
  });

  test('a virada de fevereiro desloca o resto do ano', () {
    // 1º de março é o dia 60 em ano comum e 61 em bissexto. É exatamente aqui
    // que um cálculo ingênuo com tabela fixa de meses erraria.
    expect(VersiculoDoDia.diaDoAno(DateTime(2026, 3, 1)), 60);
    expect(VersiculoDoDia.diaDoAno(DateTime(2028, 3, 1)), 61);
  });

  test('a hora do dia não altera o resultado', () {
    // Conferido contra o app da YouVersion: 18/08/2026 é o dia 230.
    for (final hora in [0, 1, 12, 23]) {
      expect(
        VersiculoDoDia.diaDoAno(DateTime(2026, 8, 18, hora, 59, 59)),
        230,
        reason: 'às ${hora}h',
      );
    }
  });

  test('o calendário embarcado cobre o ano inteiro', () async {
    // Varre os 366 dias de um ano bissexto: nenhum pode ficar sem passagem,
    // senão o cartão some justamente naquele dia.
    for (var dia = 1; dia <= 366; dia++) {
      final ref = await VersiculoDoDia.de(
        DateTime(2028, 1, 1).add(Duration(days: dia - 1)),
      );
      expect(ref, isNotNull, reason: 'dia $dia sem versículo');
      expect(ref!.dia, dia);
      expect(ref.livro, inInclusiveRange(1, 66), reason: 'livro fora do cânon');
      expect(ref.capitulo, greaterThan(0));
      expect(ref.versiculo, greaterThan(0));
      expect(ref.ate, greaterThanOrEqualTo(ref.versiculo));
    }
  });

  test('29 de fevereiro tem passagem própria', () async {
    final ref = await VersiculoDoDia.de(DateTime(2028, 2, 29));
    expect(ref?.dia, 60);
  });
}
