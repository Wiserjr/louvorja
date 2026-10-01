import 'package:biblia_estudo/dados/atualizacao.dart';
import 'package:flutter_test/flutter_test.dart';

/// O manifesto é a porta por onde um instalador entra no aparelho. Estes
/// testes prendem o que ele NÃO pode fazer — apontar para outro servidor,
/// oferecer o app errado, pôr texto no diálogo — tanto quanto o que ele deve
/// fazer.
void main() {
  const pacote = 'br.com.wisejr.bibliaestudo';
  const base =
      'https://github.com/Wiserjr/louvorja/releases/download/biblia-v1.0.1';

  Map<String, dynamic> manifesto({
    Object? applicationId = pacote,
    Object? versionCode = 2,
    Object? versionName = '1.0.1',
    Map<String, dynamic>? apks,
    Object? windows = '$base/biblia-windows.zip',
  }) => {
    'applicationId': applicationId,
    'versionCode': versionCode,
    'versionName': versionName,
    'apks':
        apks ??
        {
          'arm64-v8a': '$base/biblia-arm64-v8a.apk',
          'armeabi-v7a': '$base/biblia-armeabi-v7a.apk',
        },
    'windows': windows,
  };

  InfoAtualizacao? ler(
    Map<String, dynamic> m, {
    int instalada = 2001,
    List<String> abis = const ['arm64-v8a', 'armeabi-v7a', 'armeabi'],
    bool windows = false,
  }) => interpretarManifesto(
    m,
    pacote: pacote,
    versaoInstalada: instalada,
    abis: abis,
    windows: windows,
  );

  group('Android', () {
    test('a arquitetura não conta na comparação', () {
      expect(versaoBase(2001), 1);
      expect(versaoBase(1002), 2);
      expect(versaoBase(2), 2, reason: 'APK universal, sem o acréscimo');
    });

    test('versão mais nova é oferecida, com o APK da arquitetura', () {
      final info = ler(manifesto())!;
      expect(info.versionCode, 2);
      expect(info.versionName, '1.0.1');
      expect(info.arquivo.path, endsWith('biblia-arm64-v8a.apk'));
    });

    test('mesma versão, ou mais velha, não é oferecida', () {
      expect(ler(manifesto(), instalada: 2002), isNull);
      expect(ler(manifesto(), instalada: 1003), isNull);
    });

    test('aparelho 32 bits recebe o armeabi-v7a', () {
      final info = ler(manifesto(), abis: ['armeabi-v7a', 'armeabi'])!;
      expect(info.arquivo.path, endsWith('biblia-armeabi-v7a.apk'));
    });

    test('sem APK para a arquitetura, falha em vez de instalar outro', () {
      expect(
        () => ler(manifesto(), abis: ['x86_64']),
        throwsA(isA<FalhaAtualizacao>()),
      );
    });
  });

  group('Windows', () {
    test('versão mais nova é oferecida, com o zip', () {
      final info = ler(manifesto(), instalada: 1, windows: true)!;
      expect(info.arquivo.path, endsWith('biblia-windows.zip'));
    });

    test('a versão do Windows é comparada sem acréscimo de arquitetura', () {
      expect(ler(manifesto(), instalada: 2, windows: true), isNull);
    });

    test('sem zip para Windows, falha', () {
      expect(
        () => ler(manifesto(windows: null), instalada: 1, windows: true),
        throwsA(isA<FalhaAtualizacao>()),
      );
    });

    test('o zip também só vem de uma release deste repositório', () {
      for (final link in [
        'https://exemplo.com/biblia-windows.zip',
        'http://github.com/Wiserjr/louvorja/releases/download/v1/a.zip',
        'https://github.com/outro/louvorja/releases/download/v1/a.zip',
        'https://github.com/Wiserjr/louvorja/releases/download/v1/a.exe',
        'https://github.com/Wiserjr/louvorja/releases/download/v1/a.zip?x=1',
        'https://github.com/Wiserjr/louvorja/releases/download/../a.zip',
      ]) {
        expect(
          () => ler(manifesto(windows: link), instalada: 1, windows: true),
          throwsA(isA<FalhaAtualizacao>()),
          reason: link,
        );
      }
    });

    test('o script espera o app fechar, copia e reabre', () {
      final s = scriptWindows(
        origem: r'C:\tmp\novo',
        destino: r'C:\Users\x\Biblia',
        executavel: 'biblia_estudo.exe',
      );
      expect(s, contains('tasklist /FI "PID eq %PID%"'));
      expect(s, contains(r'robocopy "C:\tmp\novo" "C:\Users\x\Biblia" /E'));
      expect(s, contains('biblia_estudo.exe'));
      expect(s, contains('\r\n'), reason: 'cmd.exe espera CRLF');
    });

    test('aspas no caminho não quebram o script', () {
      final s = scriptWindows(
        origem: r'C:\tmp\a" & del *.* & "',
        destino: r'C:\x',
        executavel: 'biblia_estudo.exe',
      );
      expect(s, isNot(contains('" & del')));
    });
  });

  group('o manifesto não pode', () {
    void recusa(Map<String, dynamic> m) =>
        expect(() => ler(m), throwsA(isA<FalhaAtualizacao>()));

    test('oferecer o instalador de outro app', () {
      // O Louvor JA e o Hinários publicam no mesmo repositório.
      recusa(manifesto(applicationId: 'br.com.wisejr.louvorja'));
      recusa(manifesto(applicationId: 'br.com.wisejr.louvorja.hinarios'));
    });

    test('pôr texto no diálogo pelo versionName', () {
      recusa(manifesto(versionName: '2.0 - APAGUE E REINSTALE O APP'));
      recusa(manifesto(versionName: ''));
    });

    test('trazer versionCode fora do formato', () {
      recusa(manifesto(versionCode: '2'));
      recusa(manifesto(versionCode: 2002));
      recusa(manifesto(versionCode: 0));
    });

    test('apontar para outro servidor ou outro repositório', () {
      for (final link in [
        'https://exemplo.com/biblia.apk',
        'http://github.com/Wiserjr/louvorja/releases/download/v1/a.apk',
        'https://github.com/outro/louvorja/releases/download/v1/a.apk',
        'https://github.com:8443/Wiserjr/louvorja/releases/download/v1/a.apk',
        'https://x@github.com/Wiserjr/louvorja/releases/download/v1/a.apk',
        'https://github.com/Wiserjr/louvorja/releases/download/v1/a.apk?x=1',
        'https://github.com/Wiserjr/louvorja/releases/download/v1/a.apk#x',
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

  test('o manifesto fica numa release fixa, não na latest do Louvor JA', () {
    expect(
      Atualizacao.instancia.urlManifesto.toString(),
      'https://github.com/Wiserjr/louvorja/releases/download/biblia-atual/'
      'atualizacao-br.com.wisejr.bibliaestudo.json',
    );
  });
}
