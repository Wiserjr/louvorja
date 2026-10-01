import 'dart:io';

import 'package:archive/archive.dart';
import 'package:biblia_estudo/dados/banco.dart';
import 'package:biblia_estudo/dados/estudo.dart';
import 'package:biblia_estudo/dados/mapas.dart';
import 'package:biblia_estudo/dados/sinotico.dart';
import 'package:biblia_estudo/dados/temas.dart';
import 'package:biblia_estudo/dados/modelos.dart';
import 'package:biblia_estudo/dados/trechos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Confere o banco de estudo que vai no app (assets/estudo.db.gz) e, se os
/// PDFs estiverem em ferramentas/cache/pdf (rode indexar_obras.py), que o
/// pdfrx — o leitor de PDF do app — devolve exatamente o parágrafo que o
/// indexador em Python registrou.
void main() {
  late Directory tmp;

  setUpAll(() async {
    sqfliteFfiInit();
    tmp = await Directory.systemTemp.createTemp('estudo');
    final bytes = const GZipDecoder().decodeBytes(
      File('assets/estudo.db.gz').readAsBytesSync(),
    );
    final arq = File('${tmp.path}/estudo.db')..writeAsBytesSync(bytes);
    Banco.instancia.estudo = await databaseFactoryFfi.openDatabase(
      arq.path,
      options: OpenDatabaseOptions(readOnly: true),
    );
  });

  tearDownAll(() async {
    await Banco.instancia.estudo.close();
    await tmp.delete(recursive: true);
  });

  test('Mateus 4:4 leva ao capítulo "A tentação" de O Desejado', () async {
    final trechos = await Estudo.instancia.trechos(40, 4, 4);
    expect(trechos, isNotEmpty);
    final primeiro = trechos.first;
    expect(primeiro.tipo, TipoLigacao.capitulo);
    expect(primeiro.obra.sigla, 'DTN');
    expect(primeiro.capitulo, contains('tentação'));
    expect(
      trechos.where(
        (t) => t.tipo == TipoLigacao.citacao && t.obra.sigla == 'DTN',
      ),
      isNotEmpty,
    );
  });

  test(
    'Daniel 2 tem o comentário versículo a versículo de Urias Smith',
    () async {
      final trechos = await Estudo.instancia.trechos(27, 2, 31);
      expect(
        trechos.where(
          (t) => t.tipo == TipoLigacao.comentario && t.obra.sigla == 'DA',
        ),
        isNotEmpty,
      );
    },
  );

  test('Mateus 4:4 cita Deuteronômio 8:3, e a recíproca', () async {
    final refs = await Estudo.instancia.referencias(40, 4, 4);
    expect(refs.any((r) => r.livro == 5 && r.ini == 8003 && r.citacao), isTrue);
    final volta = await Estudo.instancia.referencias(5, 8, 3);
    expect(volta.any((r) => r.livro == 40 && r.ini == 4004), isTrue);
  });

  group('mapas', () {
    test('lugares de um versículo, com nome em português', () async {
      // Mateus 2:1 — "Belém da Judéia", "Jerusalém".
      final l = await Mapas.instancia.doVersiculo(40, 2, 1);
      final nomes = l.map((x) => x.nome).toSet();
      expect(nomes, containsAll(['Belém', 'Jerusalém']));
    });

    test(
      'mapas temáticos: rotas com lugares e coordenadas plausíveis',
      () async {
        final mapas = await Mapas.instancia.tematicos();
        expect(mapas.length, greaterThanOrEqualTo(15));
        final paulo = mapas.firstWhere((m) => m.id == 'paulo-2');
        final rota = await Mapas.instancia.lugares(paulo.rotas.first.lugares);
        expect(rota.first.nome, contains('Antioquia'));
        expect(rota.map((l) => l.nome), contains('Corinto'));
        for (final l in rota) {
          expect(l.lon, inInclusiveRange(8, 60), reason: l.nome);
          expect(l.lat, inInclusiveRange(20, 46), reason: l.nome);
        }
      },
    );

    test('a geometria tem terra, lagos e rios', () async {
      final g = await Mapas.instancia.geometria();
      expect(g.terra, isNotEmpty);
      expect(g.lagos, isNotEmpty);
      expect(g.rios, isNotEmpty);
    });
  });

  group('temas e estudos', () {
    test('o sábado tem versículos e leituras de Ellen G. White', () async {
      final passagens = await Temas.instancia.passagens('sabado');
      expect(passagens.first.livro, 1); // Gênesis 2:2-3
      final leituras = await Temas.instancia.leituras('sabado');
      expect(leituras, isNotEmpty);
      expect(leituras.first.versiculos, greaterThanOrEqualTo(2));
    });

    test('João 3:16 aparece em temas', () async {
      final t = await Temas.instancia.doVersiculo(43, 3, 16);
      expect(t.map((x) => x.id), contains('amor-de-deus'));
    });

    test('estudos bíblicos em ordem, com perguntas', () async {
      final e = await Temas.instancia.estudos();
      expect(e.first.titulo, startsWith('1.'));
      final q = await Temas.instancia.perguntas(e.first.id);
      expect(q, isNotEmpty);
    });

    test('título curto de capítulo', () {
      expect(tituloCurto('Capítulo 29 — O Sábado'), 'cap. 29 — O Sábado');
      expect(
        tituloCurto(
          'Capítulo 17 — Poesias e cânticos “Os Teus estatutos têm sido',
        ),
        'cap. 17 — Poesias e cânticos',
      );
    });
  });

  group('notas de estudo', () {
    test('todo o Novo Testamento tem notas em todos os capítulos', () async {
      for (final (livro, caps) in [
        (40, 28),
        (41, 16),
        (42, 24),
        (43, 21),
        (44, 28),
        (45, 16),
      ]) {
        for (var c = 1; c <= caps; c++) {
          final rows = await Banco.instancia.estudo.rawQuery(
            'SELECT count(*) AS n FROM nota WHERE livro=? AND ini BETWEEN ? AND ?',
            [livro, c * 1000, c * 1000 + 999],
          );
          expect(rows.first['n'], greaterThan(0), reason: '$livro:$c');
        }
      }
    });

    test('João 3:16 tem nota', () async {
      final n = await Estudo.instancia.notas(43, 3, 16);
      expect(n.single.texto, contains('amor de Deus'));
    });

    test('Romanos 3:31 tem nota sobre a lei', () async {
      final n = await Estudo.instancia.notas(45, 3, 31);
      expect(n.single.texto, contains('confirmamos a lei'));
    });

    test('1 Coríntios 15:51 tem nota sobre a ressurreição', () async {
      final n = await Estudo.instancia.notas(46, 15, 51);
      expect(n.single.texto, contains('imortalidade'));
    });

    test('Colossenses 2:16 distingue os sábados cerimoniais', () async {
      final n = await Estudo.instancia.notas(51, 2, 16);
      expect(n.single.texto, contains('cerimoniais'));
    });

    test('1 Tessalonicenses 4:13 trata a morte como sono', () async {
      final n = await Estudo.instancia.notas(52, 4, 13);
      expect(n.single.texto, contains('sono'));
    });

    test('Hebreus 8:2 fala do santuário celestial', () async {
      final n = await Estudo.instancia.notas(58, 8, 2);
      expect(n.single.texto, contains('santuário'));
    });

    test('Apocalipse 14:7 liga o primeiro anjo ao quarto mandamento', () async {
      final n = await Estudo.instancia.notas(66, 14, 7);
      expect(n.single.texto, contains('quarto mandamento'));
    });

    test('Daniel tem notas em todos os capítulos; 8:14 leva a 1844', () async {
      for (var c = 1; c <= 12; c++) {
        final rows = await Banco.instancia.estudo.rawQuery(
          'SELECT count(*) AS n FROM nota WHERE livro=27 AND ini BETWEEN ? AND ?',
          [c * 1000, c * 1000 + 999],
        );
        expect(rows.first['n'], greaterThan(0), reason: 'Daniel $c');
      }
      final n = await Estudo.instancia.notas(27, 9, 25);
      expect(n.single.texto, contains('457 a.C.'));
    });
  });

  group('guia sinótico', () {
    test('episódios em ordem, do prólogo à ascensão', () async {
      final e = await Sinotico.instancia.eventos();
      expect(e.length, greaterThan(150));
      expect(e.first.passagens.keys, [43]);
      expect(e.last.titulo, contains('ascensão'));
    });

    test('a tentação está nos três sinóticos e em O Desejado', () async {
      final e = await Sinotico.instancia.doVersiculo(40, 4, 4);
      final tentacao = e.firstWhere((x) => x.titulo.contains('tentação'));
      expect(tentacao.passagens.keys, containsAll([40, 41, 42]));
      expect(tentacao.leituras.first.obra.sigla, 'DTN');
      expect(tentacao.leituras.first.capitulo, contains('A tentação'));
    });

    test('a multiplicação para cinco mil está nos quatro', () async {
      final e = await Sinotico.instancia.doVersiculo(43, 6, 10);
      expect(e.single.quantosEvangelhos, 4);
    });

    test('parábola leva a Parábolas de Jesus', () async {
      final e = await Sinotico.instancia.doVersiculo(42, 15, 11);
      expect(e.single.leituras.map((l) => l.obra.sigla), contains('PJ'));
    });

    test('fora dos evangelhos, nada', () async {
      expect(await Sinotico.instancia.doVersiculo(1, 1, 1), isEmpty);
    });
  });

  test('todos os livros têm introdução', () async {
    for (var l = 1; l <= 66; l++) {
      final i = await Estudo.instancia.introducao(l);
      expect(i?['tema'], isNotEmpty, reason: 'livro $l');
    }
  });

  test('marcadores do leitor: João 3 tem versículos citados', () async {
    final c = await Estudo.instancia.contagem(43, 3);
    expect(c[16], greaterThan(10));
  });

  group('paridade com o indexador (precisa dos PDFs em cache)', () {
    // O pdfrx no teste (sem Flutter) precisa de um libpdfium: aponte
    // PDFIUM_PATH para o que vem com o pypdfium2, por exemplo
    //   PDFIUM_PATH=$(python3 -c "import pypdfium2_raw,os;print(os.path.join(os.path.dirname(pypdfium2_raw.__file__),'libpdfium.so'))")
    final pasta = Directory('ferramentas/cache/pdf');
    final pdfium = Platform.environment['PDFIUM_PATH'];
    final temPdfs =
        pasta.existsSync() && pdfium != null && File(pdfium).existsSync();

    setUpAll(() async {
      if (temPdfs) await pdfrxInitialize();
    });

    test(
      'o pdfrx recorta o mesmo parágrafo que o PDFium do Python',
      () async {
        final obras = await Estudo.instancia.obras();
        var conferidos = 0;
        for (final sigla in ['DTN', 'PP', 'GC', 'DA', 'HS']) {
          final obra = obras.values.firstWhere((o) => o.sigla == sigla);
          final arq = File('${pasta.path}/${obra.arquivo}.pdf');
          if (!arq.existsSync()) continue;
          final doc = await PdfDocument.openFile(arq.path);
          final rows = await Banco.instancia.estudo.rawQuery(
            'SELECT segmentos, ancora FROM trecho WHERE obra=? '
            'AND ancora IS NOT NULL ORDER BY id LIMIT 40',
            [obra.id],
          );
          for (final r in rows) {
            final segs = Trecho.lerSegmentos(r['segmentos'] as String);
            final paginas = <int, String>{};
            for (final (p, _, _) in segs) {
              paginas[p] ??= (await doc.pages[p].loadText())?.fullText ?? '';
            }
            final texto = recortar(paginas, segs);
            final ancora = (r['ancora'] as String).replaceAll(' ', '');
            expect(
              texto.replaceAll(RegExp(r'\s'), ''),
              contains(ancora),
              reason: '$sigla ${r['segmentos']}',
            );
            conferidos++;
          }
          await doc.dispose();
        }
        expect(conferidos, greaterThan(0));
      },
      skip: temPdfs
          ? false
          : 'Sem PDFs em cache (indexar_obras.py) ou sem PDFIUM_PATH',
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}
