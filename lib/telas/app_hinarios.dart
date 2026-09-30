import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../dados/download.dart';
import 'atualizacao_app.dart';
import 'tela_downloads.dart';
import 'tela_hinarios.dart';

/// O app Hinários: só os dois hinários, para quem tem pouco espaço no celular.
///
/// Mesmo código do Louvor JA, com outra casca. O que fica de fora não é só
/// esconder abas: o catálogo embarcado tem ~1 MB em vez de 27 MB (só os
/// hinários, sem Bíblia nem coletâneas), e nada é baixado sem a pessoa tocar
/// um hino. Cada hino tocado ocupa ~3,5 MB, e os Ajustes mostram o total e
/// apagam tudo com um toque.
class AppHinarios extends StatelessWidget {
  const AppHinarios({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hinários',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1B5E9C),
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF1B5E9C),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const _Inicio(),
    );
  }
}

class _Inicio extends StatefulWidget {
  const _Inicio();

  @override
  State<_Inicio> createState() => _InicioState();
}

class _InicioState extends State<_Inicio> {
  @override
  void initState() {
    super.initState();
    // Silenciosa: só aparece algo se houver versão nova.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) FluxoAtualizacao.verificar(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: TelaHinarios(
        aoAbrirAjustes: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const TelaAjustesHinarios())),
      ),
    );
  }
}

/// Os Ajustes do Hinários: espaço ocupado, atualização e créditos.
///
/// Nada da pasta copiada do PC, da URL do servidor ou da voz da Bíblia — quem
/// usa este app não tem o acervo inteiro e não deve precisar entender o que
/// essas opções significam.
class TelaAjustesHinarios extends StatefulWidget {
  const TelaAjustesHinarios({super.key});

  @override
  State<TelaAjustesHinarios> createState() => _TelaAjustesHinariosState();
}

class _TelaAjustesHinariosState extends State<TelaAjustesHinarios> {
  int? _bytes;
  String? _versao;

  @override
  void initState() {
    super.initState();
    _medir();
    PackageInfo.fromPlatform().then((p) {
      if (mounted) setState(() => _versao = '${p.version} (${p.buildNumber})');
    });
  }

  Future<void> _medir() async {
    final b = await Download.instancia.bytesOcupados();
    if (mounted) setState(() => _bytes = b);
  }

  Future<void> _apagar() async {
    final confirma = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Apagar hinos baixados?'),
        content: const Text(
          'Libera o espaço que os áudios ocupam. As letras continuam no app, e '
          'cada hino é baixado de novo quando você tocar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (confirma != true) return;
    await Download.instancia.limparTudo();
    await _medir();
  }

  static String _tamanho(int bytes) => bytes < 1048576
      ? '${(bytes / 1024).toStringAsFixed(0)} KB'
      : bytes < 1073741824
      ? '${(bytes / 1048576).toStringAsFixed(1).replaceAll('.', ',')} MB'
      : '${(bytes / 1073741824).toStringAsFixed(2).replaceAll('.', ',')} GB';

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        children: [
          const _Titulo('Espaço no aparelho'),
          ListTile(
            leading: const Icon(Icons.sd_storage_outlined),
            title: const Text('Hinos baixados'),
            subtitle: Text(
              bytes == null
                  ? 'Calculando…'
                  : bytes == 0
                  ? 'Nenhum. Os hinos são baixados quando você toca.'
                  : '${_tamanho(bytes)} — só os hinos que você tocou ou baixou',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Apagar hinos baixados'),
            subtitle: const Text('Libera o espaço; as letras continuam no app'),
            enabled: (bytes ?? 0) > 0,
            onTap: _apagar,
          ),
          ListTile(
            leading: const Icon(Icons.download_for_offline_outlined),
            title: const Text('Baixar um hinário inteiro'),
            // Um hinário inteiro, só cantado, são uns 2 GB: o oposto do motivo
            // de este app existir. Fica disponível para quem quer usar sem
            // internet, com o tamanho dito antes de começar.
            subtitle: const Text(
              'Para usar sem internet. Ocupa alguns GB; o tamanho aparece '
              'antes de começar.',
            ),
            onTap: () async {
              await Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const TelaDownloads()));
              await _medir();
            },
          ),

          const _Titulo('Sobre'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Versão do app'),
            subtitle: Text(_versao ?? '—'),
          ),
          ListTile(
            leading: const Icon(Icons.system_update_outlined),
            title: const Text('Procurar atualização'),
            subtitle: const Text(
              'O app baixa a versão nova e pede a sua confirmação',
            ),
            onTap: () => FluxoAtualizacao.verificar(context, manual: true),
          ),

          const _Titulo('Créditos'),
          const ListTile(
            leading: Icon(Icons.library_music_outlined),
            title: Text('Acervo LouvorJA'),
            subtitle: Text(
              'Letras, gravações e playbacks dos hinários: louvorja.com.br',
            ),
          ),
        ],
      ),
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
    child: Text(
      texto.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        letterSpacing: 1.1,
      ),
    ),
  );
}
