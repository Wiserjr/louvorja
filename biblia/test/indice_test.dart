import 'dart:io';

import 'package:archive/archive.dart';
import 'package:biblia_estudo/dados/banco.dart';
import 'package:biblia_estudo/dados/estudo.dart';
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
