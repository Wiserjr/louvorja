import 'package:flutter_test/flutter_test.dart';
import 'package:louvorja/dados/pacote_fundos.dart';

/// O zip dos fundos vem da rede, e cada entrada dele vira um caminho de
/// arquivo no aparelho. Uma entrada como `images/../../../shared_prefs/x.xml`
/// escreveria fora da pasta do app — o ataque clássico de zip slip. O filtro é
/// de uma linha, mas é a única coisa entre um arquivo baixado e o disco, então
/// vale prender o comportamento.
void main() {
  group('nomeSeguro aceita', () {
    test('uma imagem comum do acervo', () {
      expect(
        PacoteFundos.nomeSeguro('images/generico_010.jpg'),
        'images/generico_010.jpg',
      );
      expect(
        PacoteFundos.nomeSeguro('images/hasd_018.jpg'),
        'images/hasd_018.jpg',
      );
    });

    test('os PNG, que o empacotador não recomprime', () {
      expect(
        PacoteFundos.nomeSeguro('images/generico_111.png'),
        'images/generico_111.png',
      );
    });
  });

  group('nomeSeguro recusa', () {
    test('subida de diretório', () {
      expect(PacoteFundos.nomeSeguro('images/../segredo.txt'), isNull);
      expect(PacoteFundos.nomeSeguro('images/../../etc/passwd'), isNull);
      expect(PacoteFundos.nomeSeguro('../images/x.jpg'), isNull);
    });

    test('barra invertida, que no Windows também separa pasta', () {
      expect(PacoteFundos.nomeSeguro(r'images\..\x.jpg'), isNull);
      expect(PacoteFundos.nomeSeguro(r'images\x.jpg'), isNull);
    });

    test('qualquer coisa fora de images/', () {
      expect(PacoteFundos.nomeSeguro('musics/pt/Album/x.mp3'), isNull);
      expect(PacoteFundos.nomeSeguro('x.jpg'), isNull);
      expect(PacoteFundos.nomeSeguro('/images/x.jpg'), isNull);
      expect(PacoteFundos.nomeSeguro('imagesx/y.jpg'), isNull);
    });

    test('subpasta dentro de images/', () {
      // O empacotador grava tudo plano; uma subpasta indica zip de outra fonte.
      expect(PacoteFundos.nomeSeguro('images/sub/x.jpg'), isNull);
    });

    test('a própria pasta, sem arquivo', () {
      expect(PacoteFundos.nomeSeguro('images/'), isNull);
    });
  });

  group('EstadoPacote', () {
    test('sem tamanho anunciado o progresso é indefinido', () {
      // contentLength vem -1 em resposta chunked; fingir uma fração seria pior
      // que mostrar barra indefinida.
      const baixando = EstadoPacote(etapa: Etapa.baixando, total: -1);
      expect(baixando.progresso, isNull);
    });

    test('com tamanho, progresso é a fração recebida', () {
      const meio = EstadoPacote(
        etapa: Etapa.baixando,
        recebidos: 50,
        total: 200,
      );
      expect(meio.progresso, 0.25);
    });

    test('na extração o progresso conta arquivos, não bytes', () {
      const ext = EstadoPacote(
        etapa: Etapa.extraindo,
        extraidos: 250,
        aExtrair: 1000,
      );
      expect(ext.progresso, 0.25);
    });

    test('parado não tem progresso', () {
      expect(const EstadoPacote().progresso, isNull);
    });

    test('copiar preserva o que não foi passado', () {
      const a = EstadoPacote(etapa: Etapa.baixando, recebidos: 10, total: 100);
      final b = a.copiar(recebidos: 20);
      expect(b.recebidos, 20);
      expect(b.total, 100);
      expect(b.etapa, Etapa.baixando);
    });
  });
}
