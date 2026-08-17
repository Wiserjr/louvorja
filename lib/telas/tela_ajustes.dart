import 'package:flutter/material.dart';

import '../dados/download.dart';
import '../dados/sincronizacao.dart';
import 'tela_downloads.dart';
import '../dados/midia.dart';

class TelaAjustes extends StatefulWidget {
  const TelaAjustes({super.key, this.aoMudarPasta});

  final Future<void> Function()? aoMudarPasta;

  @override
  State<TelaAjustes> createState() => _TelaAjustesState();
}

class _TelaAjustesState extends State<TelaAjustes> {
  String? _pasta;
  int _indexados = 0;
  bool _indexando = false;

  final _urlCtrl = TextEditingController();
  ResultadoTeste? _teste;
  bool _testando = false;
  int _bytesBaixados = 0;
  String? _ondeGrava;

  Diagnostico? _diag;
  ({int encontradas, int total})? _cobertura;
  bool _sincronizando = false;
  String _etapa = '';
  double? _progresso;
  String? _resultadoSync;

  @override
  void initState() {
    super.initState();
    Midia.instancia.raiz.then((v) {
      if (mounted) setState(() => _pasta = v);
    });
    Download.instancia.urlBase.then((v) {
      if (mounted) _urlCtrl.text = v;
    });
    _atualizarEspaco();
    _verificarCatalogo();
    _medirCobertura();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _medirCobertura() async {
    if (await Midia.instancia.raiz == null) return;
    final c = await Midia.instancia.cobertura();
    if (mounted) setState(() => _cobertura = c);
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

  Future<void> _escolher() async {
    final ok = await Midia.instancia.escolherPasta();
    if (!ok || !mounted) return;

    setState(() {
      _pasta = null;
      _indexando = true;
      _indexados = 0;
    });
    Midia.instancia.raiz.then(
      (v) => mounted ? setState(() => _pasta = v) : null,
    );

    final total = await Midia.instancia.indexar(
      aoProgredir: (n) => mounted ? setState(() => _indexados = n) : null,
    );
    if (mounted) {
      setState(() {
        _indexando = false;
        _indexados = total;
      });
    }
    await _medirCobertura();
    await widget.aoMudarPasta?.call();
  }

  /// Refaz a varredura da mesma pasta.
  ///
  /// Necessário depois de copiar mais álbuns: o índice é um retrato do momento
  /// da escolha, não um observador do sistema de arquivos.
  Future<void> _reindexar() async {
    setState(() {
      _indexando = true;
      _indexados = 0;
    });
    final total = await Midia.instancia.indexar(
      aoProgredir: (n) => mounted ? setState(() => _indexados = n) : null,
    );
    if (mounted) {
      setState(() {
        _indexando = false;
        _indexados = total;
      });
    }
    await _medirCobertura();
    await widget.aoMudarPasta?.call();
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
          const _Titulo('Fonte principal: pasta copiada'),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Pasta das músicas'),
            subtitle: Text(
              _pasta == null
                  ? 'Nenhuma pasta escolhida'
                  : Uri.decodeFull(_pasta!).split('/').last,
            ),
            trailing: FilledButton.tonal(
              onPressed: _indexando ? null : _escolher,
              child: Text(_pasta == null ? 'Escolher' : 'Trocar'),
            ),
          ),
          if (_cobertura != null && !_indexando)
            ListTile(
              leading: Icon(
                _cobertura!.encontradas == 0
                    ? Icons.error_outline
                    : _cobertura!.encontradas < _cobertura!.total
                    ? Icons.info_outline
                    : Icons.check_circle_outline,
              ),
              title: Text(
                '${_cobertura!.encontradas} de ${_cobertura!.total} faixas '
                'encontradas na pasta',
              ),
              // Quando a conta não fecha, o motivo quase sempre é o nível de
              // pasta escolhido ou uma cópia parcial — dizer isso poupa o
              // usuário de adivinhar.
              subtitle: Text(
                _cobertura!.encontradas == 0
                    ? 'Nenhuma. Confira se apontou a pasta que contém "musics" '
                          'ou "musicas", e refaça a varredura.'
                    : _cobertura!.encontradas < _cobertura!.total
                    ? 'O resto pode ser baixado, ou copiado depois para a mesma '
                          'pasta. Refaça a varredura após copiar.'
                    : 'A pasta cobre todo o catálogo.',
              ),
              trailing: TextButton(
                onPressed: _indexando ? null : _reindexar,
                child: const Text('Varrer'),
              ),
            ),
          if (_indexando)
            ListTile(
              leading: const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              title: const Text('Indexando a pasta...'),
              subtitle: Text('$_indexados arquivos'),
            )
          else if (_indexados > 0)
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: Text('$_indexados arquivos indexados'),
            ),

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
          ListTile(
            leading: const Icon(Icons.sd_storage_outlined),
            title: const Text('Mídia baixada'),
            // Dizer onde está gravando importa: quando o externo não aceita
            // escrita, o app cai para o interno silenciosamente, e o usuário
            // merece saber por que o espaço some de outro lugar.
            subtitle: Text(
              [
                _mb(_bytesBaixados),
                ?_ondeGrava,
              ].join(' · '),
            ),
            trailing: TextButton(
              onPressed: _bytesBaixados == 0 ? null : _limpar,
              child: const Text('Apagar'),
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
