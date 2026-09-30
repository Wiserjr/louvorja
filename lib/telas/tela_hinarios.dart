import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../dados/download.dart';
import '../dados/hinario.dart';
import '../dados/midia.dart';
import '../dados/modelos.dart';
import '../dados/repositorio.dart';
import 'tela_letra.dart';
import 'tela_player.dart';

/// Os dois hinários adventistas, na forma do site app.louvorja.com.br: um
/// seletor entre o atual e o de 1996, a busca por número ou nome, e para cada
/// hino as mesmas opções — cantado, playback, sem áudio, letra e os arquivos.
///
/// Os hinários também aparecem na aba Álbuns, como qualquer outro álbum. Aqui
/// eles ganham uma tela própria porque o uso é outro: na igreja se procura o
/// hino pelo número anunciado, e a pergunta seguinte é *como* cantá-lo.
class TelaHinarios extends StatefulWidget {
  const TelaHinarios({super.key});

  @override
  State<TelaHinarios> createState() => _TelaHinariosState();
}

class _TelaHinariosState extends State<TelaHinarios> {
  static const _chaveHinario = 'hinario_escolhido';

  final _repo = const Repositorio();
  final _campo = TextEditingController();

  List<Album>? _hinarios;
  Album? _atual;
  String? _erro;
  String _termo = '';

  /// Um Future por hinário, memorizado: alternar entre os dois não relê o
  /// catálogo, e o termo digitado continua valendo no outro — dá para procurar
  /// "santo" e comparar as duas edições com um toque.
  final Map<int, Future<List<Musica>>> _hinos = {};

  /// Progresso, de 0 a 1, dos arquivos sendo baixados, por caminho.
  final Map<String, double> _baixando = {};

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _campo.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final hinarios = await _repo.hinarios();
      int? salvo;
      try {
        salvo = (await SharedPreferences.getInstance()).getInt(_chaveHinario);
      } catch (_) {
        // Sem preferência, abre no primeiro — o hinário atual.
      }
      if (!mounted) return;
      setState(() {
        _hinarios = hinarios;
        _atual =
            hinarios.where((h) => h.id == salvo).firstOrNull ??
            hinarios.firstOrNull;
      });
    } catch (e) {
      if (mounted) setState(() => _erro = '$e');
    }
  }

  Future<List<Musica>> _hinosDe(Album a) =>
      _hinos[a.id] ??= _repo.musicasDoAlbum(a.id);

  /// Troca de hinário e lembra da escolha: quem usa o de 1996 na sua igreja
  /// não deve precisar escolhê-lo toda vez que abre o app.
  Future<void> _escolher(Album a) async {
    setState(() => _atual = a);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_chaveHinario, a.id);
    } catch (_) {
      // Vale para esta sessão mesmo sem gravar.
    }
  }

  /// Enter no campo: um número exato, ou uma busca com resultado único, abre o
  /// hino direto — o atalho de quem já sabe o número anunciado.
  Future<void> _abrirPrimeiro(String termo) async {
    final atual = _atual;
    if (atual == null) return;
    final hinos = filtrarHinos(await _hinosDe(atual), termo);
    if (hinos.isEmpty || !mounted) return;
    final numero = int.tryParse(termo.trim());
    if (hinos.first.faixa == numero || hinos.length == 1) _opcoes(hinos, 0);
  }

  String _origem(Musica m) => (m.faixa ?? 0) > 0
      ? 'Hino ${m.faixa} · ${_atual?.nome ?? ''}'
      : _atual?.nome ?? '';

  Future<void> _opcoes(List<Musica> hinos, int i) async {
    final m = hinos[i];
    final acao = await showModalBottomSheet<_Acao>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _MenuHino(
        musica: m,
        hinario: _atual?.nome ?? '',
        baixando: _baixando.keys.toSet(),
      ),
    );
    if (acao == null || !mounted) return;

    switch (acao) {
      case _Acao.cantado:
        _executar(hinos, i, ModoAudio.cantado);
      case _Acao.playback:
        _executar(hinos, i, ModoAudio.playback);
      case _Acao.semAudio:
        _executar(hinos, i, ModoAudio.semAudio);
      case _Acao.letra:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TelaLetra(musica: m, origem: _origem(m)),
          ),
        );
      case _Acao.baixarCantado:
        _baixar(m, playback: false);
      case _Acao.baixarPlayback:
        _baixar(m, playback: true);
    }
  }

  /// Abre o player com a lista visível como fila: o "próximo" leva ao hino
  /// seguinte do hinário, ou do resultado da busca, se houver uma.
  void _executar(List<Musica> hinos, int i, ModoAudio modo) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TelaPlayer(
          fila: hinos,
          indice: i,
          nomeAlbum: _atual?.nome ?? '',
          modo: modo,
          // Escolher "Cantado" ou "Playback" já foi o comando de tocar. Sem
          // áudio não há o que tocar.
          tocarAoAbrir: modo != ModoAudio.semAudio,
        ),
      ),
    );
  }

  Future<void> _baixar(Musica m, {required bool playback}) async {
    final caminho = playback ? m.audioPlayback : m.audio;
    if (caminho == null || _baixando.containsKey(caminho)) return;

    // Guardado antes: o download pode terminar depois de a pessoa ter trocado
    // de aba, e o aviso ainda precisa chegar.
    final aviso = ScaffoldMessenger.of(context);
    final qual = playback ? 'Playback' : 'Cantado';
    setState(() => _baixando[caminho] = 0);
    try {
      await Download.instancia.baixar(
        m.id,
        caminho,
        instrumental: playback,
        aoProgredir: (recebidos, total) {
          if (!mounted || total <= 0) return;
          setState(() => _baixando[caminho] = recebidos / total);
        },
      );
      aviso.showSnackBar(
        SnackBar(content: Text('$qual de "${m.nome}" baixado.')),
      );
    } on FalhaDownload catch (e) {
      aviso.showSnackBar(SnackBar(content: Text('${m.nome}: ${e.motivo}')));
    } catch (e) {
      aviso.showSnackBar(
        SnackBar(content: Text('Falha ao baixar "${m.nome}": $e')),
      );
    } finally {
      _baixando.remove(caminho);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_erro != null) {
      return Center(child: Text('Erro ao ler o catálogo:\n$_erro'));
    }
    final hinarios = _hinarios;
    final atual = _atual;
    if (hinarios == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (atual == null) {
      return const Center(child: Text('Nenhum hinário no catálogo.'));
    }

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: SearchBar(
              controller: _campo,
              hintText: 'Número ou nome do hino',
              leading: const Icon(Icons.search),
              textInputAction: TextInputAction.search,
              trailing: [
                if (_termo.isNotEmpty)
                  IconButton(
                    tooltip: 'Limpar',
                    onPressed: () {
                      _campo.clear();
                      setState(() => _termo = '');
                    },
                    icon: const Icon(Icons.close),
                  ),
              ],
              onChanged: (v) => setState(() => _termo = v),
              onSubmitted: _abrirPrimeiro,
            ),
          ),
          if (hinarios.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: [
                    for (final h in hinarios)
                      ButtonSegment(
                        value: h.id,
                        label: Text(rotuloDoHinario(h.nome)),
                      ),
                  ],
                  selected: {atual.id},
                  onSelectionChanged: (s) =>
                      _escolher(hinarios.firstWhere((h) => h.id == s.first)),
                ),
              ),
            ),
          Expanded(
            child: FutureBuilder<List<Musica>>(
              future: _hinosDe(atual),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Text('Erro ao ler o hinário:\n${snap.error}'),
                  );
                }
                final todos = snap.data!;
                final hinos = filtrarHinos(todos, _termo);
                return Column(
                  children: [
                    _cabecalho(atual, todos.length, hinos.length),
                    Expanded(
                      child: hinos.isEmpty
                          ? Center(
                              child: Text(
                                'Nenhum hino encontrado para "${_termo.trim()}".',
                              ),
                            )
                          : ListView.builder(
                              itemCount: hinos.length,
                              itemBuilder: (context, i) => _linha(hinos, i),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Nome do hinário e a contagem — o "Total de registros" do site.
  Widget _cabecalho(Album hinario, int total, int achados) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              hinario.nome,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tema.textTheme.titleSmall,
            ),
          ),
          Text(
            _termo.trim().isEmpty ? '$total hinos' : '$achados de $total',
            style: tema.textTheme.labelMedium?.copyWith(
              color: tema.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _linha(List<Musica> hinos, int i) {
    final m = hinos[i];
    final tema = Theme.of(context);
    final progresso = [
      _baixando[m.audio],
      _baixando[m.audioPlayback],
    ].nonNulls.firstOrNull;

    return ListTile(
      leading: SizedBox(
        width: 40,
        child: Text(
          '${m.faixa ?? ''}',
          textAlign: TextAlign.end,
          style: tema.textTheme.titleMedium?.copyWith(
            color: tema.colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      title: Text(m.nome),
      subtitle: progresso != null
          ? LinearProgressIndicator(value: progresso == 0 ? null : progresso)
          : (m.duracaoMs ?? 0) > 0
          ? Text(_mmss(m.duracaoMs!))
          : null,
      trailing: const Icon(Icons.more_vert),
      onTap: () => _opcoes(hinos, i),
    );
  }
}

String _mmss(int ms) {
  final d = Duration(milliseconds: ms);
  return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}

String _mb(int bytes) =>
    '${(bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} MB';

enum _Acao { cantado, playback, semAudio, letra, baixarCantado, baixarPlayback }

/// O menu de um hino: "Executar" e "Arquivos", como no site.
///
/// Confere na abertura se cada áudio já está no aparelho, para dizer antes do
/// toque o que vai acontecer — tocar na hora, ou baixar primeiro. A conferência
/// é por hino, sob demanda: fazê-la para os 601 da lista custaria uma consulta
/// à pasta por linha antes de mostrar qualquer coisa.
class _MenuHino extends StatefulWidget {
  const _MenuHino({
    required this.musica,
    required this.hinario,
    required this.baixando,
  });

  final Musica musica;
  final String hinario;

  /// Caminhos com download em curso, para não oferecer baixar de novo.
  final Set<String> baixando;

  @override
  State<_MenuHino> createState() => _MenuHinoState();
}

class _MenuHinoState extends State<_MenuHino> {
  late final Future<({bool cantado, bool playback})> _noAparelho = _conferir();

  Future<({bool cantado, bool playback})> _conferir() async {
    final m = widget.musica;
    return (
      cantado: m.audio != null && await Midia.instancia.existe(m.audio!),
      playback:
          m.audioPlayback != null &&
          await Midia.instancia.existe(m.audioPlayback!),
    );
  }

  void _escolher(_Acao a) => Navigator.of(context).pop(a);

  @override
  Widget build(BuildContext context) {
    final m = widget.musica;
    final tema = Theme.of(context);
    return FutureBuilder<({bool cantado, bool playback})>(
      future: _noAparelho,
      builder: (context, snap) {
        final conferido = snap.data;

        String comoToca(bool? presente, int? bytes) => switch (presente) {
          null => 'Conferindo…',
          true => 'Toca na hora',
          false => 'Baixa e toca${bytes == null ? '' : ' (${_mb(bytes)})'}',
        };

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      '${m.faixa ?? ''}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  title: Text(m.nome, style: tema.textTheme.titleMedium),
                  subtitle: Text(
                    [
                      widget.hinario,
                      if ((m.duracaoMs ?? 0) > 0) _mmss(m.duracaoMs!),
                    ].join(' · '),
                  ),
                ),
                const Divider(),
                const _Secao('Executar'),
                ListTile(
                  leading: const Icon(Icons.play_circle_outline),
                  title: const Text('Cantado'),
                  subtitle: Text(comoToca(conferido?.cantado, m.audioBytes)),
                  enabled: m.audio != null,
                  onTap: () => _escolher(_Acao.cantado),
                ),
                ListTile(
                  leading: const Icon(Icons.mic_off_outlined),
                  title: const Text('Playback'),
                  subtitle: Text(
                    m.audioPlayback == null
                        ? 'Este hino não tem playback'
                        : comoToca(conferido?.playback, null),
                  ),
                  enabled: m.audioPlayback != null,
                  onTap: () => _escolher(_Acao.playback),
                ),
                ListTile(
                  leading: const Icon(Icons.slideshow_outlined),
                  title: const Text('Sem áudio'),
                  subtitle: const Text('Os slides, passados à mão'),
                  enabled: m.temLetra,
                  onTap: () => _escolher(_Acao.semAudio),
                ),
                ListTile(
                  leading: const Icon(Icons.lyrics_outlined),
                  title: const Text('Letra'),
                  subtitle: const Text('O hino inteiro, para ler'),
                  enabled: m.temLetra,
                  onTap: () => _escolher(_Acao.letra),
                ),
                const Divider(),
                const _Secao('Arquivos'),
                _arquivo(
                  titulo: 'Baixar cantado',
                  caminho: m.audio,
                  presente: conferido?.cantado,
                  bytes: m.audioBytes,
                  acao: _Acao.baixarCantado,
                ),
                _arquivo(
                  titulo: 'Baixar playback',
                  caminho: m.audioPlayback,
                  presente: conferido?.playback,
                  acao: _Acao.baixarPlayback,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _arquivo({
    required String titulo,
    required String? caminho,
    required bool? presente,
    required _Acao acao,
    int? bytes,
  }) {
    final baixando = caminho != null && widget.baixando.contains(caminho);
    final (texto, pode) = switch ((caminho, presente, baixando)) {
      (null, _, _) => ('Não disponível para este hino', false),
      (_, _, true) => ('Baixando…', false),
      (_, null, _) => ('Conferindo…', false),
      (_, true, _) => ('Já está no aparelho', false),
      _ => (
        'Para usar sem internet${bytes == null ? '' : ' · ${_mb(bytes)}'}',
        true,
      ),
    };
    return ListTile(
      leading: const Icon(Icons.audio_file_outlined),
      title: Text(titulo),
      subtitle: Text(texto),
      trailing: presente == true
          ? Icon(
              Icons.check_circle,
              color: Theme.of(context).colorScheme.primary,
            )
          : null,
      enabled: pode,
      onTap: () => _escolher(acao),
    );
  }
}

class _Secao extends StatelessWidget {
  const _Secao(this.titulo);

  final String titulo;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
    child: Text(
      titulo.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        letterSpacing: 1.1,
      ),
    ),
  );
}
