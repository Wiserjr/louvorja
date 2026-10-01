import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;

/// Os dois bancos do app, ambos embarcados compactados em `assets/`:
///
/// - `biblia.db`  o texto das doze traduções (ferramentas/construir_biblia.py)
/// - `estudo.db`  índice de Ellen G. White e pioneiros, referências cruzadas,
///                introduções e notas (ferramentas/construir_estudo.py)
///
/// Na primeira abertura — e sempre que o app é atualizado — cada um é
/// descompactado para a pasta de suporte do app. Os dois são só leitura: o que
/// a pessoa cria (marcações, última leitura) fica nas preferências, para que
/// trocar o banco numa atualização nunca apague nada dela.
class Banco {
  Banco._();
  static final Banco instancia = Banco._();

  late Database biblia;
  late Database estudo;
  bool _aberto = false;

  /// No Windows o sqflite não tem implementação nativa; usa-se a FFI.
  static void configurarPlataforma() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  }

  Future<void> abrir({required String versaoApp}) async {
    if (_aberto) return;
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    biblia = await _abrir(dir, 'biblia', versaoApp);
    estudo = await _abrir(dir, 'estudo', versaoApp);
    _aberto = true;
  }

  Future<Database> _abrir(Directory dir, String nome, String versao) async {
    final arquivo = File(p.join(dir.path, '$nome.db'));
    final marca = File(p.join(dir.path, '$nome.versao'));
    final atual = await marca.exists() ? await marca.readAsString() : '';
    if (atual != versao || !await arquivo.exists()) {
      await _extrair('assets/$nome.db.gz', arquivo);
      await marca.writeAsString(versao);
    }
    return openDatabase(arquivo.path, readOnly: true, singleInstance: false);
  }

  /// Descompacta para um `.parcial` e só então troca: uma interrupção no
  /// meio não deixa um banco pela metade com o nome do bom.
  Future<void> _extrair(String asset, File destino) async {
    final dados = await rootBundle.load(asset);
    final bytes = const GZipDecoder().decodeBytes(
      dados.buffer.asUint8List(dados.offsetInBytes, dados.lengthInBytes),
    );
    final parcial = File('${destino.path}.parcial');
    await parcial.writeAsBytes(bytes, flush: true);
    if (await destino.exists()) await destino.delete();
    await parcial.rename(destino.path);
  }
}
