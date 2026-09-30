import 'package:flutter_test/flutter_test.dart';
import 'package:louvorja/dados/atualizacao.dart';

/// O manifesto é a porta por onde um APK entra no aparelho. Estes testes
/// prendem o que ele NÃO pode fazer — apontar para outro servidor, oferecer o
/// app errado, pôr texto no diálogo — tanto quanto o que ele deve fazer.
void main() {
  const pacote = 'br.com.wisejr.louvorja';
  const base = 'https://github.com/Wiserjr/louvorja/releases/download/v1.0.10';

  Map<String, dynamic> manifesto({
    Object? applicationId = pacote,
    Object? versionCode = 11,
    Object? versionName = '1.0.10',
    Map<String, dynamic>? apks,
  }) => {
    'applicationId': applicationId,
    'versionCode': versionCode,
    'versionName': versionName,
    'apks':
        apks ??
        {
          'arm64-v8a': '$base/louvorja-arm64-v8a.apk',
          'armeabi-v7a': '$base/louvorja-armeabi-v7a.apk',
        },
  };

  InfoAtualizacao? ler(
    Map<String, dynamic> m, {
    int instalada = 2010,
    List<String> abis = const ['arm64-v8a', 'armeabi-v7a', 'armeabi'],
  }) => interpretarManifesto(
    m,
    pacote: pacote,
    versaoInstalada: instalada,
    abis: abis,
  );

  group('versão', () {
    test('a arquitetura não conta na comparação', () {
      expect(versaoBase(2010), 10);
      expect(versaoBase(1011), 11);
      expect(versaoBase(10), 10, reason: 'APK universal, sem o acréscimo');
    });

    test('versão mais nova é oferecida, com o APK da arquitetura', () {
      final info = ler(manifesto())!;
      expect(info.versionCode, 11);
      expect(info.versionName, '1.0.10');
      expect(info.apk.path, endsWith('louvorja-arm64-v8a.apk'));
    });

    test('mesma versão, ou mais velha, não é oferecida', () {
      expect(ler(manifesto(), instalada: 2011), isNull);
      expect(ler(manifesto(), instalada: 1012), isNull);
    });

    test('aparelho 32 bits recebe o armeabi-v7a', () {
      final info = ler(manifesto(), abis: ['armeabi-v7a', 'armeabi'])!;
      expect(info.apk.path, endsWith('louvorja-armeabi-v7a.apk'));
    });

    test('sem APK para a arquitetura, falha em vez de instalar outro', () {
      expect(
        () => ler(manifesto(), abis: ['x86_64']),
        throwsA(isA<FalhaAtualizacao>()),
      );
    });
  });

  group('o manifesto não pode', () {
    void recusa(Map<String, dynamic> m) =>
        expect(() => ler(m), throwsA(isA<FalhaAtualizacao>()));

    test('oferecer o APK de outro app', () {
      // O Hinários convive com o Louvor JA: um não pode receber o do outro.
      recusa(manifesto(applicationId: 'br.com.wisejr.louvorja.hinarios'));
    });

    test('pôr texto no diálogo pelo versionName', () {
      recusa(manifesto(versionName: '2.0 - APAGUE E REINSTALE O APP'));
      recusa(manifesto(versionName: ''));
    });

    test('trazer versionCode fora do formato', () {
      recusa(manifesto(versionCode: '11'));
      recusa(manifesto(versionCode: 2011));
      recusa(manifesto(versionCode: 0));
    });

    test('apontar para outro servidor ou outro repositório', () {
      for (final link in [
        'https://exemplo.com/louvorja.apk',
        'http://github.com/Wiserjr/louvorja/releases/download/v1/a.apk',
        'https://github.com/outro/louvorja/releases/download/v1/a.apk',
        'https://github.com:8443/Wiserjr/louvorja/releases/download/v1/a.apk',
        'https://x@github.com/Wiserjr/louvorja/releases/download/v1/a.apk',
        'https://github.com/Wiserjr/louvorja/releases/download/v1/a.apk?x=1',
        'https://github.com/Wiserjr/louvorja/releases/download/v1/a.exe',
        'https://github.com/Wiserjr/louvorja/releases/download/../a.apk',
      ]) {
        expect(
          () => ler(manifesto(apks: {'arm64-v8a': link})),
          throwsA(isA<FalhaAtualizacao>()),
          reason: link,
        );
      }
    });
  });

  test('redirecionamento só para os hosts do GitHub', () {
    expect(hostPermitido(Uri.parse('https://github.com/a')), isTrue);
    expect(
      hostPermitido(
        Uri.parse('https://release-assets.githubusercontent.com/x'),
      ),
      isTrue,
    );
    expect(
      hostPermitido(Uri.parse('https://objects.githubusercontent.com/x')),
      isTrue,
    );
    expect(hostPermitido(Uri.parse('http://github.com/a')), isFalse);
    expect(hostPermitido(Uri.parse('https://github.com.evil.io/a')), isFalse);
    expect(hostPermitido(Uri.parse('https://evil.io/github.com')), isFalse);
  });
}
