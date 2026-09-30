import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../dados/download.dart';
import '../dados/pacote_fundos.dart';
import '../dados/repositorio.dart';
import '../dados/sincronizacao.dart';
import 'atualizacao_app.dart';
import 'secao_pasta.dart';
import 'tela_downloads.dart';
import 'tela_audio_biblia.dart';
import 'tela_voz.dart';

class TelaAjustes extends StatefulWidget {
  const TelaAjustes({super.key, this.aoMudarPasta});

  final Future<void> Function()? aoMudarPasta;

  @override
  State<TelaAjustes> createState() => _TelaAjustesState();
}

class _TelaAjustesState extends State<TelaAjustes> {
  final _urlCtrl = TextEditingController();
  ResultadoTeste? _teste;
  bool _testando = false;
  int _bytesBaixados = 0;
  String? _ondeGrava;

  /// "1.0.5 (6)" - versao e versionCode do APK instalado.
  ///
  /// Sem loja para gerenciar atualizacao, e aqui que alguem descobre se esta
  /// desatualizado. O versionCode vai junto porque e ele que o Android compara
  /// ao instalar por cima, e foi justamente ele que travou as versoes 1.0.0 a
  /// 1.0.3 umas sobre as outras.
  String? _versaoApp;

  /// Quantos fundos do catálogo já estão no aparelho. Null enquanto confere.
  ({int presentes, int total})? _fundos;

  Diagnostico? _diag;
  bool _sincronizando = false;
  String _etapa = '';
  double? _progresso;
  String? _resultadoSync;

  @override
  void initState() {
    super.initState();
    Download.instancia.urlBase.then((v) {
      if (mounted) _urlCtrl.text = v;
    });
    PackageInfo.fromPlatform().then((p) {
      if (mounted) {
        setState(() => _versaoApp = '${p.version} (${p.buildNumber})');
      }
    });
    _atualizarEspaco();
    _verificarCatalogo();
    _conferirFundos();
  }

  Future<void> _conferirFundos() async {
    final lista = await const Repositorio().fundosDoCatalogo();
    final r = await PacoteFundos.instancia.conferir(lista);
    if (mounted) setState(() => _fundos = r);
  }

  Future<void> _baixarFundos() async {
    try {
      await PacoteFundos.instancia.baixarEExtrair();
    } catch (_) {
      // A mensagem já foi para o estado do pacote e aparece no subtítulo.
    }
    await _conferirFundos();
    await _atualizarEspaco();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _verificarCatalogo() async {
    final d = await Sincronizacao.instancia.verificar();
    if (mounted) setState(() => _diag = d);
  }

  Future<void> _sincronizar({bool forcar = false}) async {
    setState(() {
      _sincronizando = true;
      _resultadoSync = null;
      _etapa = 'Consultando o servidor';
      _progresso = null;
    });
    try {
      final r = await Sincronizacao.instancia.sincronizar(
        forcar: forcar,
        aoProgredir: (etapa, feito, total) {
          if (!mounted) return;
          setState(() {
            _etapa = etapa;
            _progresso = total > 0 ? feito / total : null;
          });
        },
      );
      if (mounted) setState(() => _resultadoSync = r.toString());
      await _verificarCatalogo();
    } catch (e) {
      if (mounted) setState(() => _resultadoSync = 'Falhou: $e');
    } finally {
      if (mounted) setState(() => _sincronizando = false);
    }
  }

  Future<void> _atualizarEspaco() async {
    final b = await Download.instancia.bytesOcupados();
    final onde = await Download.instancia.descricaoDaPasta;
    if (mounted) {
      setState(() {
        _bytesBaixados = b;
        _ondeGrava = onde;
      });
    }
  }

  Future<void> _testar() async {
    setState(() {
      _testando = true;
      _teste = null;
    });
    await Download.instancia.definirUrlBase(_urlCtrl.text);
    // A sonda é o endpoint de configuração: 115 bytes, e ainda informa a
    // versão do acervo publicada pelo servidor.
    final r = await Download.instancia.testarConexao();
    if (mounted) {
      setState(() {
        _teste = r;
        _testando = false;
      });
    }
  }

  Future<void> _limpar() async {
    final confirma = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Apagar mídia baixada?'),
        content: Text(
          'Serão removidos ${_mb(_bytesBaixados)} de arquivos baixados pelo '
          'servidor. A pasta que você copiou à mão não é afetada.',
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
    await _atualizarEspaco();
  }

  static String _mb(int bytes) => bytes < 1048576
      ? '${(bytes / 1024).toStringAsFixed(0)} KB'
      : bytes < 1073741824
      ? '${(bytes / 1048576).toStringAsFixed(1)} MB'
      : '${(bytes / 1073741824).toStringAsFixed(2)} GB';

  @override
  Widget build(BuildContext context) {
    final cor = Theme.of(context).colorScheme;

    return SafeArea(
      child: ListView(
        children: [
          const _Titulo('Catálogo'),
          ListTile(
            leading: const Icon(Icons.library_music_outlined),
            // Toque longo refaz a sincronização mesmo com o catálogo em dia —
            // saída para quando uma atualização anterior parou no meio.
            onLongPress: _sincronizando
                ? null
                : () => _sincronizar(forcar: true),
            title: const Text('Versão do acervo'),
            subtitle: Text(
              _diag == null
                  ? 'Verificando...'
                  : _diag!.erro != null
                  ? 'Local: ${_diag!.local}. ${_diag!.erro}'
                  : _diag!.temAtualizacao
                  ? 'Local ${_diag!.local} · disponível ${_diag!.remota}'
                  : 'Versão ${_diag!.local}, em dia '
                        '(toque longo para refazer)',
            ),
            trailing: FilledButton.tonal(
              onPressed: _sincronizando ? null : _sincronizar,
              child: Text(
                _diag?.temAtualizacao == true ? 'Atualizar' : 'Verificar',
              ),
            ),
          ),
          if (_sincronizando)
            ListTile(
              title: Text(_etapa),
              subtitle: LinearProgressIndicator(value: _progresso),
            )
          else if (_resultadoSync != null)
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: Text(_resultadoSync!),
            ),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.headphones_outlined),
            title: const Text('Biblia em audio'),
            subtitle: const Text('Gravacoes narradas, via Bible Brain'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const TelaAudioBiblia())),
          ),
          ListTile(
            leading: const Icon(Icons.record_voice_over_outlined),
            title: const Text('Voz da leitura bíblica'),
            subtitle: const Text(
              'Motor, voz e velocidade da leitura em voz alta',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const TelaVoz())),
          ),
          const Divider(height: 32),
          const _Titulo('Fonte principal: pasta copiada'),
          SecaoPastaMusicas(aoMudarPasta: widget.aoMudarPasta),

          const Divider(height: 32),
          const _Titulo('Fonte alternativa: download'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Baixa da API oficial as músicas que não estiverem na pasta. '
              'Só altere o endereço se quiser usar outro servidor.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _urlCtrl,
              decoration: const InputDecoration(
                labelText: 'URL base',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: _testando ? null : _testar,
                  icon: _testando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_find),
                  label: const Text('Testar conexão'),
                ),
              ],
            ),
          ),
          if (_teste != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _teste!.ok ? Icons.check_circle : Icons.error_outline,
                    color: _teste!.ok ? cor.primary : cor.error,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_teste!.mensagem)),
                ],
              ),
            ),
          ListTile(
            leading: const Icon(Icons.cloud_download_outlined),
            title: const Text('Baixar músicas'),
            subtitle: const Text('Por álbum, categoria ou o acervo inteiro'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const TelaDownloads())),
          ),
          _fundosDosSlides(cor),
          ListTile(
            leading: const Icon(Icons.sd_storage_outlined),
            title: const Text('Mídia baixada'),
            // Dizer onde está gravando importa: quando o externo não aceita
            // escrita, o app cai para o interno silenciosamente, e o usuário
            // merece saber por que o espaço some de outro lugar.
            subtitle: Text([_mb(_bytesBaixados), ?_ondeGrava].join(' · ')),
            trailing: TextButton(
              onPressed: _bytesBaixados == 0 ? null : _limpar,
              child: const Text('Apagar'),
            ),
          ),

          const _Titulo('Sobre'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Versão do app'),
            // Distinto da "Versão do acervo" logo acima, que é a do catálogo
            // de músicas. Confundir os dois manda o usuário conferir o número
            // errado justamente quando está tentando saber se atualizou.
            subtitle: Text(_versaoApp ?? '—'),
          ),
          ListTile(
            leading: const Icon(Icons.system_update_outlined),
            title: const Text('Procurar atualização'),
            // A abertura do app já procura sozinha; isto é para quem ouviu
            // falar de uma versão nova e não quer esperar a próxima abertura.
            subtitle: const Text(
              'O app baixa a versão nova e pede a sua confirmação',
            ),
            onTap: () => FluxoAtualizacao.verificar(context, manual: true),
          ),

          // A atribuição da Bíblia Livre não é cortesia: a licença Creative
          // Commons que permite embarcá-la no app a exige. Os autores aceitam
          // a sigla sozinha onde falta espaço — num slide, num cartão —, e é
          // por isso que o crédito por extenso mora aqui.
          const _Titulo('Créditos'),
          const ListTile(
            leading: Icon(Icons.menu_book_outlined),
            title: Text('Bíblia Livre (BLIVRE)'),
            subtitle: Text(
              'Diego Santos, Mário Sérgio e Marco Teles\n'
              'Creative Commons Atribuição 3.0 Brasil\n'
              'sites.google.com/site/biblialivre',
            ),
            isThreeLine: true,
          ),
          const ListTile(
            leading: Icon(Icons.wb_sunny_outlined),
            title: Text('Versículo do dia'),
            subtitle: Text('Calendário de leituras da YouVersion'),
          ),
        ],
      ),
    );
  }

  /// Baixar de uma vez os fundos que faltam.
  ///
  /// O contador existe porque a resposta certa depende do aparelho: quem copiou
  /// a pasta inteira do PC já tem tudo e não deve baixar nada, e quem copiou
  /// alguns álbuns só descobriria a falta quando um slide ficasse sem fundo no
  /// meio do culto.
  Widget _fundosDosSlides(ColorScheme cor) {
    return ValueListenableBuilder<EstadoPacote>(
      valueListenable: PacoteFundos.instancia.estado,
      builder: (context, est, _) {
        final rodando = est.etapa != Etapa.parado;
        final faltam = _fundos == null
            ? null
            : _fundos!.total - _fundos!.presentes;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: const Icon(Icons.wallpaper_outlined),
              title: const Text('Fundos dos slides'),
              subtitle: Text(switch (est.etapa) {
                Etapa.baixando => 'Baixando o pacote...',
                Etapa.extraindo =>
                  'Extraindo ${est.extraidos} de ${est.aExtrair}...',
                Etapa.parado when est.erro != null => est.erro!,
                Etapa.parado when faltam == null => 'Conferindo...',
                Etapa.parado when faltam == 0 =>
                  'Todas as ${_fundos!.total} imagens estão no aparelho',
                Etapa.parado =>
                  'Faltam $faltam de ${_fundos!.total} — cerca de 158 MB',
              }),
              trailing: rodando
                  ? TextButton(
                      onPressed: PacoteFundos.instancia.cancelar,
                      child: const Text('Cancelar'),
                    )
                  : (faltam != null && faltam > 0
                        ? FilledButton.tonal(
                            onPressed: _baixarFundos,
                            child: const Text('Baixar'),
                          )
                        : null),
            ),
            if (rodando)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                // Sem valor a barra fica indefinida: contentLength vem -1 em
                // resposta chunked, e fingir uma porcentagem seria pior.
                child: LinearProgressIndicator(value: est.progresso),
              ),
            if (!rodando && est.concluidos > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  '${est.concluidos} imagens gravadas.',
                  style: TextStyle(color: cor.primary),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Text(
      texto.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        letterSpacing: 1.1,
      ),
    ),
  );
}
