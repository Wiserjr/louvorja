import 'package:flutter_test/flutter_test.dart';
import 'package:louvorja/dados/fila_download.dart';
import 'package:louvorja/dados/modelos.dart';

/// A montagem do lote decide o que vai ser baixado. Um erro aqui não quebra
/// nada: o lote termina "concluído" e o playback que se pediu simplesmente não
/// veio — que é o tipo de falha que só aparece no culto.
void main() {
  // Caminhos reais do hinário atual; o hino 515 é o único dele sem playback.
  const santo = Musica(
    id: 1728,
    nome: 'Santo, Santo, Santo!',
    audio: 'musics/pt/Hinário Adventista 2022/Santo, Santo, Santo!.mp3',
    audioPlayback:
        'musics/pt/Hinário Adventista 2022/Santo, Santo, Santo! - PB.mp3',
    audioBytes: 3000000,
  );
  const estrelinhas = Musica(
    id: 2262,
    nome: 'Sabe Quantas Estrelinhas?',
    audio: 'musics/pt/Hinário Adventista 2022/Sabe Quantas Estrelinhas.mp3',
    audioBytes: 2000000,
  );
  const semAudio = Musica(id: 9, nome: 'Só letra');

  List<String> caminhos(List<ItemDownload> itens) => [
    for (final i in itens) i.caminho,
  ];

  test('por padrão, só o cantado — como antes do playback existir', () {
    expect(caminhos(FilaDownload.itensDe([santo, estrelinhas, semAudio])), [
      santo.audio,
      estrelinhas.audio,
    ]);
  });

  test('só o playback pula quem não tem playback', () {
    final itens = FilaDownload.itensDe(
      [santo, estrelinhas, semAudio],
      cantado: false,
      playback: true,
    );
    expect(caminhos(itens), [santo.audioPlayback]);
    expect(itens.single.playback, isTrue);
  });

  test('os dois: cada música com a cantada seguida do playback', () {
    final itens = FilaDownload.itensDe([santo, estrelinhas], playback: true);
    expect(caminhos(itens), [
      santo.audio,
      santo.audioPlayback,
      estrelinhas.audio,
    ]);
  });

  test('o playback se identifica no painel', () {
    expect(const ItemDownload(santo).nome, 'Santo, Santo, Santo!');
    expect(
      const ItemDownload(santo, playback: true).nome,
      'Santo, Santo, Santo! (playback)',
    );
  });

  test('a estimativa do playback usa o tamanho da cantada', () {
    final itens = FilaDownload.itensDe([santo, estrelinhas], playback: true);
    expect(FilaDownload.bytesDe(itens), 3000000 + 3000000 + 2000000);
  });
}
