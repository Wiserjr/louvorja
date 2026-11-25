import 'package:flutter_test/flutter_test.dart';
import 'package:louvorja/dados/download.dart';

void main() {
  group('Download.caminhoDaApi', () {
    test('URL completa vira caminho relativo', () {
      expect(
        Download.caminhoDaApi(
          'https://files.louvorja.com.br/musics/pt/2027 - Somos a Igreja/'
          'Somos a Igreja.mp3',
        ),
        'musics/pt/2027 - Somos a Igreja/Somos a Igreja.mp3',
      );
    });

    test('mantém acentos e espaços do nome do arquivo', () {
      expect(
        Download.caminhoDaApi(
          'https://files.louvorja.com.br/musics/pt/Hinário Adventista 2022/'
          'Somos Igreja - PB.mp3',
        ),
        'musics/pt/Hinário Adventista 2022/Somos Igreja - PB.mp3',
      );
    });

    test('formato antigo, com barra inicial, continua valendo', () {
      expect(
        Download.caminhoDaApi('/musics/pt/Álbum/Faixa.mp3'),
        'musics/pt/Álbum/Faixa.mp3',
      );
    });

    test('caminho já relativo passa intacto', () {
      expect(
        Download.caminhoDaApi('images/hasd_287.jpg'),
        'images/hasd_287.jpg',
      );
    });

    test('é idempotente: reparar duas vezes não muda nada', () {
      const url = 'https://files.louvorja.com.br/covers/2027.jpg';
      final uma = Download.caminhoDaApi(url);
      expect(uma, 'covers/2027.jpg');
      expect(Download.caminhoDaApi(uma), uma);
    });

    test('vazio, nulo ou só o host viram null', () {
      expect(Download.caminhoDaApi(null), isNull);
      expect(Download.caminhoDaApi(''), isNull);
      expect(Download.caminhoDaApi('https://files.louvorja.com.br'), isNull);
      expect(Download.caminhoDaApi(42), isNull);
    });
  });
}
