import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'modelos.dart';

/// Envio de versículos e músicas para outros aplicativos.
///
/// Os textos são montados aqui, num lugar só, porque a forma como uma citação
/// chega ao WhatsApp é parte do produto: referência antes ou depois, aspas,
/// sigla da tradução. Espalhar isso pelas telas garantiria versões divergentes.
class Compartilhar {
  Compartilhar._();
  static final Compartilhar instancia = Compartilhar._();

  static const _assinatura = 'Compartilhado pelo app Louvor JA';

  /// `"No princípio criou Deus..." — Gênesis 1:1 (ACRF)`
  static String textoDoVersiculo(Versiculo v, {String? sigla}) =>
      '"${v.texto.trim()}"\n— ${v.referencia}${sigla == null ? '' : ' ($sigla)'}';

  /// Vários versículos seguidos viram um bloco só, com a referência em faixa.
  static String textoDaPassagem(List<Versiculo> versos, {String? sigla}) {
    if (versos.isEmpty) return '';
    if (versos.length == 1) return textoDoVersiculo(versos.first, sigla: sigla);
    final corpo = versos.map((v) => '${v.numero} ${v.texto.trim()}').join(' ');
    final ref =
        '${versos.first.livro} ${versos.first.capitulo}:'
        '${versos.first.numero}-${versos.last.numero}';
    return '"$corpo"\n— $ref${sigla == null ? '' : ' ($sigla)'}';
  }

  static String textoDaMusica(Musica m, {String? album}) => [
    m.nome,
    ?(album == null ? null : 'do álbum $album'),
    '',
    _assinatura,
  ].join('\n');

  /// Letra completa, para quem quer mandar a música inteira escrita.
  static String textoDaLetra(Musica m, List<Slide> slides, {String? album}) {
    final versos = slides
        .map((s) => s.texto.trim())
        .where((t) => t.isNotEmpty)
        .join('\n\n');
    return [m.nome, ?album, '', versos, '', _assinatura].join('\n');
  }

  Future<void> texto(String conteudo, {String? assunto}) async {
    await SharePlus.instance.share(
      ShareParams(text: conteudo, subject: assunto),
    );
  }

  /// Envia uma imagem gerada na hora.
  ///
  /// O arquivo vai para o diretório temporário: quem recebe é o outro app, e
  /// deixar cópias no armazenamento do usuário seria lixo acumulado a cada
  /// compartilhamento.
  Future<void> imagem(
    Uint8List bytes, {
    String nome = 'versiculo',
    String? texto,
  }) async {
    final dir = await getTemporaryDirectory();
    final arquivo = File(
      p.join(dir.path, '${nome}_${DateTime.now().millisecondsSinceEpoch}.png'),
    );
    await arquivo.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(arquivo.path, mimeType: 'image/png')],
        text: texto,
      ),
    );
  }
}
