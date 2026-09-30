import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:saf_stream/saf_stream.dart';

import '../dados/compartilhar.dart';
import '../dados/download.dart';
import '../dados/midia.dart';

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../dados/modelos.dart';
import '../dados/repositorio.dart';
import '../player/sincronia.dart';
import 'tela_letra.dart';

class TelaPlayer extends StatefulWidget {
  const TelaPlayer({
    super.key,
    required this.fila,
    required this.indice,
    required this.nomeAlbum,
    this.modo = ModoAudio.cantado,
    this.tocarAoAbrir = false,
  });

  /// Abre o player numa música só, sem faixa seguinte.
  TelaPlayer.avulsa({
    Key? key,
    required Musica musica,
    required String nomeAlbum,
    ModoAudio modo = ModoAudio.cantado,
    bool tocarAoAbrir = false,
  }) : this(
         key: key,
         fila: [musica],
         indice: 0,
         nomeAlbum: nomeAlbum,
         modo: modo,
         tocarAoAbrir: tocarAoAbrir,
       );

  /// As músicas que o player percorre, na ordem em que aparecem na tela de
  /// origem. Sem isto não há "próxima" — e sem próxima não há repetir nem
  /// aleatório, que são os modos de percorrê-la.
  final List<Musica> fila;

  /// Onde começar dentro de [fila].
  final int indice;

  /// Só o nome: a busca global abre o player sem ter o objeto do álbum em mãos.
  final String nomeAlbum;

  /// Com que áudio começar — as opções "Executar" do site, hino a hino.
  final ModoAudio modo;

  /// Começa a tocar sem esperar o play, baixando o áudio antes se preciso.
  ///
  /// É o que acontece quando se escolhe "Cantado" ou "Playback" no menu do
  /// hino: a escolha já foi o comando. Vindo da lista de um álbum, o toque só
  /// abre a música, e aí baixar sozinho gastaria dados sem ninguém ter pedido.
  final bool tocarAoAbrir;

  @override
  State<TelaPlayer> createState() => _TelaPlayerState();
}

class _TelaPlayerState extends State<TelaPlayer> {
  final _repo = const Repositorio();
  final _player = AudioPlayer();

  Sincronizador? _sinc;
  String? _erro;
  bool _carregando = true;

  /// Cantado, playback ou sem áudio. Vale para a fila inteira: quem está
  /// cantando com o playback quer o playback também no hino seguinte.
  late ModoAudio _modo = widget.modo;
  List<Slide> _slides = const [];

  /// Slide mostrado quando não há áudio conduzindo a letra — no modo sem áudio,
  /// ou enquanto o arquivo não foi baixado. Posição em [_versos].
  int _manual = 0;

  /// Progresso do download do áudio que falta, de 0 a 1; `null` fora dele.
  double? _baixando;
  String? _falhaDownload;
  CancelToken? _cancelamento;

  /// Caminho do fundo atual, resolvido sob demanda e memorizado: são 1.003
  /// imagens e a mesma se repete em vários slides seguidos.
  final Map<String, String?> _fundos = {};
  final Map<String, Uint8List?> _bytes = {};

  /// Último fundo que chegou a ser exibido.
  ///
  /// Serve de ponte enquanto o próximo carrega. Sem ele, a troca de slide para
  /// uma imagem ainda não lida pinta o fundo liso por um instante — e se a
  /// imagem não estiver na pasta, o app vai buscá-la na API e o liso fica.
  /// Numa projeção durante o culto isso aparece como se o slide travasse.
  Uint8List? _ultimoFundo;

  /// Ordem de reprodução: posições de `widget.fila`, não as músicas.
  ///
  /// No aleatório a lista é embaralhada em vez de sortear a cada faixa. Sorteio
  /// puro repete música antes de tocar todas, que é justamente a queixa comum
  /// contra o modo aleatório dos outros aplicativos.
  late List<int> _ordem;
  late int _pos;

  ModoRepeticao _repeticao = ModoRepeticao.nenhum;
  bool _aleatorio = false;
  bool _temAudio = false;

  Musica get _musica => widget.fila[_ordem[_pos]];
  bool get _temFila => widget.fila.length > 1;

  /// O modo que de fato vale para a música atual: pedir o playback de uma
  /// faixa que não tem playback toca a cantada, e a tela deve dizer isso.
  ModoAudio get _modoEfetivo =>
      _modo == ModoAudio.playback && _musica.audioPlayback == null
      ? ModoAudio.cantado
      : _modo;

  /// Arquivo que o modo atual toca, ou `null` no modo sem áudio.
  String? get _caminhoDoModo => switch (_modoEfetivo) {
    ModoAudio.cantado => _musica.audio,
    ModoAudio.playback => _musica.audioPlayback,
    ModoAudio.semAudio => null,
  };

  /// Sem áudio tocando, quem avança a letra é a pessoa.
  bool get _letraManual => !_temAudio;

  /// Os slides que têm o que mostrar. Na navegação manual os vazios só
  /// custariam um toque a mais: eles existem para limpar a projeção no tempo
  /// certo, e aqui não há tempo.
  List<Slide> get _versos =>
      _slides.where((s) => s.texto.trim().isNotEmpty).toList();

  @override
  void initState() {
    super.initState();
    _ordem = List.generate(widget.fila.length, (i) => i);
    _pos = widget.indice.clamp(0, widget.fila.length - 1);
    _player.playerStateStream.listen(_aoMudarEstado);
    _preparar(tocarAoFim: widget.tocarAoAbrir);
  }

  /// Avança sozinho quando a faixa termina, conforme o modo escolhido.
  void _aoMudarEstado(PlayerState estado) {
    if (estado.processingState != ProcessingState.completed) return;
    switch (_repeticao) {
      case ModoRepeticao.uma:
        _player.seek(Duration.zero);
        _player.play();
      case ModoRepeticao.todas:
        _irPara(_pos + 1);
      case ModoRepeticao.nenhum:
        // Sem repetição a fila acaba quando acaba: parar no fim é o esperado,
        // e voltar ao início surpreenderia quem deixou tocando.
        if (_pos + 1 < _ordem.length) _irPara(_pos + 1);
    }
  }

  Future<void> _irPara(int novaPos, {bool tocar = true}) async {
    if (_ordem.isEmpty) return;
    final pos = novaPos % _ordem.length;
    _pararDownload();
    await _player.stop();
    setState(() {
      _pos = pos < 0 ? pos + _ordem.length : pos;
      _carregando = true;
      _erro = null;
      // Os caches de fundo são por música: a próxima tem as suas imagens.
      _fundos.clear();
      _bytes.clear();
    });
    await _preparar(tocarAoFim: tocar);
  }

  /// Volta ao início da faixa se ela já andou — como em qualquer player.
  void _anterior() {
    if (_player.position > const Duration(seconds: 3)) {
      _player.seek(Duration.zero);
      return;
    }
    _irPara(_pos - 1);
  }

  void _alternarAleatorio() {
    setState(() {
      _aleatorio = !_aleatorio;
      final atual = _ordem[_pos];
      _ordem = _aleatorio
          ? ordemAleatoria(widget.fila.length, atual)
          : List.generate(widget.fila.length, (i) => i);
      _pos = _ordem.indexOf(atual);
    });
  }

  Future<void> _preparar({bool tocarAoFim = false}) async {
    try {
      _slides = await _repo.slidesDe(_musica.id);
      _manual = 0;
      // Os tempos do playback só valem para o arquivo do playback. Quando a
      // faixa não tem um e o modo recai na cantada, os tempos são os dela.
      _sinc = Sincronizador(
        _slides,
        usarTemposPlayback: _modoEfetivo == ModoAudio.playback,
      );

      // Sem await: o áudio não precisa esperar as imagens, e cada fundo que
      // chega já dispara o setState de _bytesDoFundo.
      unawaited(_precarregarFundos());

      final caminho = _caminhoDoModo;

      // Conferido aqui, não recebido pronto: cada faixa da fila tem o seu
      // arquivo, e a tela de origem só sabia da primeira.
      final uri = caminho == null ? null : await Midia.instancia.uriDe(caminho);

      // Só passa a valer depois de o player aceitar o arquivo. Se ele recusar,
      // a letra continua acessível pela navegação manual em vez de ficar
      // presa no instante zero de um áudio que não vai tocar.
      _temAudio = false;
      if (uri != null) {
        // O ExoPlayer lê URIs content:// nativamente — é o que torna o
        // acesso via SAF viável sem copiar os arquivos para dentro do app.
        await _player.setAudioSource(AudioSource.uri(Uri.parse(uri)));
        _temAudio = true;
        if (tocarAoFim) _player.play();
      } else if (caminho != null && tocarAoFim) {
        // Pediram para tocar e o arquivo não está no aparelho: baixa e toca,
        // como o site faz ao executar um hino.
        unawaited(_baixarETocar());
      }
    } catch (e) {
      _erro = '$e';
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _mudarModo(ModoAudio novo) async {
    // Pedir o que já está valendo não recarrega nada — por exemplo, "cantado"
    // numa faixa sem playback, que já estava tocando a cantada.
    if (novo == _modoEfetivo) {
      _modo = novo;
      return;
    }
    final tocando = _player.playing;
    _pararDownload();
    setState(() {
      _modo = novo;
      _carregando = true;
      _erro = null;
    });
    await _player.stop();
    await _preparar(tocarAoFim: tocando);
  }

  /// Baixa o arquivo do modo atual e começa a tocar.
  ///
  /// Toda troca de faixa ou de modo cancela o download em curso (ver
  /// [_pararDownload]). Por isso, chegar ao fim sem cancelamento garante que a
  /// música e o modo ainda são os mesmos de quando ele começou — e o arquivo
  /// não toma o lugar de outra música que a pessoa escolheu nesse meio-tempo.
  Future<void> _baixarETocar() async {
    final caminho = _caminhoDoModo;
    if (!mounted || caminho == null || _baixando != null) return;

    final cancel = CancelToken();
    _cancelamento = cancel;
    setState(() {
      _baixando = 0;
      _falhaDownload = null;
    });

    void falhou(String motivo) {
      if (!mounted || cancel.cancelado) return;
      setState(() {
        _baixando = null;
        _falhaDownload = motivo;
      });
    }

    try {
      await Download.instancia.baixar(
        _musica.id,
        caminho,
        instrumental: _modoEfetivo == ModoAudio.playback,
        cancelamento: cancel,
        aoProgredir: (recebidos, total) {
          if (!mounted || total <= 0 || cancel.cancelado) return;
          setState(() => _baixando = recebidos / total);
        },
      );
    } on DownloadCancelado {
      return;
    } on FalhaDownload catch (e) {
      falhou(e.motivo);
      return;
    } catch (e) {
      falhou('$e');
      return;
    } finally {
      if (identical(_cancelamento, cancel)) _cancelamento = null;
    }

    if (!mounted || cancel.cancelado) return;
    setState(() {
      _baixando = null;
      _carregando = true;
    });
    await _preparar(tocarAoFim: true);
  }

  /// Interrompe o download do áudio, se houver. Chamado a cada troca de faixa
  /// ou de modo, e ao sair da tela.
  void _pararDownload() {
    _cancelamento?.cancelar();
    _cancelamento = null;
    _baixando = null;
    _falhaDownload = null;
  }

  void _passar(int delta) {
    final total = _versos.length;
    if (total == 0) return;
    setState(() => _manual = (_manual + delta).clamp(0, total - 1));
  }

  /// Resolve o fundo de um slide, memorizando o resultado.
  Future<String?> _fundoDe(String? rel) async {
    if (rel == null) return null;
    if (_fundos.containsKey(rel)) return _fundos[rel];
    final uri = await Midia.instancia.uriDe(rel);
    _fundos[rel] = uri;
    return uri;
  }

  @override
  void dispose() {
    _cancelamento?.cancelar();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          if (_slides.any((s) => s.texto.trim().isNotEmpty))
            IconButton(
              tooltip: 'Letra',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TelaLetra(
                    musica: _musica,
                    origem: widget.nomeAlbum.isEmpty ? null : widget.nomeAlbum,
                  ),
                ),
              ),
              icon: const Icon(Icons.lyrics_outlined),
            ),
          _menuModo(),
          PopupMenuButton<String>(
            tooltip: 'Compartilhar',
            icon: const Icon(Icons.share_outlined),
            onSelected: (opcao) {
              if (opcao == 'titulo') {
                Compartilhar.instancia.texto(
                  Compartilhar.textoDaMusica(
                    _musica,
                    album: widget.nomeAlbum.isEmpty ? null : widget.nomeAlbum,
                  ),
                );
              } else {
                Compartilhar.instancia.texto(
                  Compartilhar.textoDaLetra(
                    _musica,
                    _slides,
                    album: widget.nomeAlbum.isEmpty ? null : widget.nomeAlbum,
                  ),
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'titulo',
                child: Text('Compartilhar o título'),
              ),
              // Só oferece a letra quando ela existe: um item que produz texto
              // vazio é pior do que item nenhum.
              if (_slides.any((s) => s.texto.trim().isNotEmpty))
                const PopupMenuItem(
                  value: 'letra',
                  child: Text('Compartilhar a letra'),
                ),
            ],
          ),
        ],
        title: Text(_musica.nome),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(18),
          child: Text(
            widget.nomeAlbum,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(child: _letraManual ? _letraAMao() : _letra()),
                if (_erro != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Erro: $_erro',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                // O modo pede áudio e ele não está no aparelho.
                if (_letraManual && _caminhoDoModo != null) _faltaAudio(),
                if (_temAudio) _controles() else _controlesManuais(),
              ],
            ),
    );
  }

  /// Cantado, playback ou sem áudio — o mesmo trio do menu "Executar" do site.
  Widget _menuModo() {
    final atual = _modoEfetivo;
    return PopupMenuButton<ModoAudio>(
      tooltip: 'Áudio: ${atual.rotulo}',
      enabled: !_carregando,
      icon: Icon(atual.icone),
      onSelected: _mudarModo,
      itemBuilder: (context) => [
        for (final m in ModoAudio.values)
          CheckedPopupMenuItem(
            value: m,
            checked: m == atual,
            // Nem toda faixa tem playback. Oferecê-lo e tocar a cantada no
            // lugar seria pior do que mostrar que ele não existe.
            enabled: m != ModoAudio.playback || _musica.audioPlayback != null,
            child: Text(m.rotulo),
          ),
      ],
    );
  }

  /// A letra passada à mão, slide a slide, sobre o mesmo fundo da projeção.
  ///
  /// Toque no terço esquerdo volta; no resto da tela, avança — avançar é o
  /// gesto de quase todo toque, e merece a área maior. Arrastar para o lado faz
  /// o mesmo, para quem está acostumado a passar fotos.
  Widget _letraAMao() {
    final versos = _versos;
    if (versos.isEmpty) {
      return const Center(child: Text('Esta música não tem letra cadastrada.'));
    }
    final slide = versos[_manual.clamp(0, versos.length - 1)];
    return LayoutBuilder(
      builder: (context, limites) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) =>
            _passar(d.localPosition.dx < limites.maxWidth / 3 ? -1 : 1),
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v.abs() < 100) return;
          _passar(v < 0 ? 1 : -1);
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            _fundo(slide.imagem ?? _musica.imagem),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _versoProjetado(context, slide),
            ),
          ],
        ),
      ),
    );
  }

  /// Aviso de que o áudio do modo atual não está no aparelho, com o botão que
  /// resolve — e o progresso, enquanto resolve.
  Widget _faltaAudio() {
    final cor = Theme.of(context).colorScheme;
    final qual = _modoEfetivo == ModoAudio.playback ? 'playback' : 'áudio';
    final progresso = _baixando;
    return Material(
      color: cor.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        child: progresso != null
            ? Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Baixando o $qual…'),
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          value: progresso == 0 ? null : progresso,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cancelar',
                    onPressed: () => setState(_pararDownload),
                    icon: const Icon(Icons.close),
                  ),
                ],
              )
            : Row(
                children: [
                  Icon(
                    _falhaDownload == null
                        ? Icons.cloud_download_outlined
                        : Icons.error_outline,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _falhaDownload == null
                          ? 'O $qual desta música não está no aparelho.'
                          : 'Não foi possível baixar: $_falhaDownload',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: _baixarETocar,
                    child: Text(
                      _falhaDownload == null
                          ? 'Baixar e tocar'
                          : 'Tentar de novo',
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  /// Verso anterior e seguinte, com a posição entre eles; nas pontas, a música
  /// anterior e a seguinte da fila.
  Widget _controlesManuais() {
    final total = _versos.length;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_temFila)
              IconButton(
                iconSize: 30,
                tooltip: 'Música anterior',
                onPressed: () => _irPara(_pos - 1, tocar: false),
                icon: const Icon(Icons.skip_previous),
              ),
            IconButton.filledTonal(
              iconSize: 34,
              tooltip: 'Verso anterior',
              onPressed: _manual > 0 ? () => _passar(-1) : null,
              icon: const Icon(Icons.chevron_left),
            ),
            SizedBox(
              width: 76,
              child: Text(
                total == 0 ? '—' : '${_manual + 1} de $total',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            IconButton.filledTonal(
              iconSize: 34,
              tooltip: 'Próximo verso',
              onPressed: _manual < total - 1 ? () => _passar(1) : null,
              icon: const Icon(Icons.chevron_right),
            ),
            if (_temFila)
              IconButton(
                iconSize: 30,
                tooltip: 'Próxima música',
                onPressed: () => _irPara(_pos + 1, tocar: false),
                icon: const Icon(Icons.skip_next),
              ),
          ],
        ),
      ),
    );
  }

  Widget _letra() {
    final sinc = _sinc;
    if (sinc == null || sinc.vazio) {
      return const Center(child: Text('Esta música não tem letra cadastrada.'));
    }

    return StreamBuilder<Duration>(
      stream: _player.positionStream,
      builder: (context, snap) {
        final pos = snap.data ?? Duration.zero;

        Slide? atual;
        try {
          atual = sinc.slideEm(pos);
        } on UnimplementedError {
          return _pendente(context);
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            _fundo(atual?.imagem ?? _musica.imagem),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: atual == null || atual.texto.trim().isEmpty
                  // Antes do primeiro verso, e nos slides de texto vazio que o
                  // acervo usa para limpar a projeção, a tela fica só com o fundo.
                  ? const SizedBox.expand(key: ValueKey('vazio'))
                  : _versoProjetado(context, atual),
            ),
          ],
        );
      },
    );
  }

  /// Fundo do slide, no estilo da projeção do programa original.
  ///
  /// A imagem pode vir da pasta escolhida (`content://`) ou do download
  /// (`file://`). O `content://` não é legível por `Image.file`, então os bytes
  /// são lidos pelo SAF — e memorizados, porque a mesma imagem costuma valer
  /// para vários slides seguidos.
  Widget _fundo(String? rel) {
    if (rel == null) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      );
    }
    return FutureBuilder<Uint8List?>(
      future: _bytesDoFundo(rel),
      builder: (context, snap) {
        // Enquanto o próximo fundo não chega, segura o anterior em vez de
        // piscar o fundo liso.
        final bytes = snap.data ?? _ultimoFundo;
        if (bytes == null) {
          return Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          );
        }
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        );
      },
    );
  }

  Future<Uint8List?> _bytesDoFundo(String rel) async {
    if (_bytes.containsKey(rel)) return _bytes[rel];
    var uri = await _fundoDe(rel);

    // Não está na pasta copiada? Busca no servidor. A imagem é pequena perto do
    // MP3 e fica em cache para os próximos slides.
    if (uri == null) {
      final f = await Download.instancia.baixarArquivo(rel);
      uri = f?.uri.toString();
      if (uri != null) _fundos[rel] = uri;
    }

    Uint8List? dados;
    try {
      if (uri == null) {
        dados = null;
      } else if (uri.startsWith('content://')) {
        dados = await SafStream().readFileBytes(uri);
      } else {
        dados = await File(Uri.parse(uri).toFilePath()).readAsBytes();
      }
    } catch (_) {
      dados = null;
    }
    _bytes[rel] = dados;
    if (dados != null) _ultimoFundo = dados;
    if (mounted) setState(() {});
    return dados;
  }

  /// Carrega os fundos da música toda antes que os slides comecem a trocar.
  ///
  /// São poucas imagens distintas por música — quase sempre uma ou duas — e
  /// resolvê-las de uma vez evita duas coisas: a espera no meio da reprodução,
  /// quando um slide entra e sua imagem ainda não foi lida, e a rajada de
  /// requisições à API que as buscas sob demanda geram numa música inteira.
  Future<void> _precarregarFundos() async {
    final rels = <String>{
      if (_musica.imagem != null) _musica.imagem!,
      for (final s in _slides)
        if (s.imagem != null) s.imagem!,
    };
    for (final rel in rels) {
      if (!mounted) return;
      await _bytesDoFundo(rel);
    }
  }

  /// O verso na tela: maiúsculas sobre faixa escura, como na projeção.
  Widget _versoProjetado(BuildContext context, Slide slide) {
    return Center(
      key: ValueKey(slide.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.62),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                child: Text(
                  slide.texto.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: const Color(0xFFFFC107),
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
              ),
            ),
            if ((slide.textoAux ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Text(
                    slide.textoAux!.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Mostrado enquanto `Sincronizador.indiceEm` não estiver implementado.
  Widget _pendente(BuildContext context) => Center(
    child: Card(
      margin: const EdgeInsets.all(24),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.construction, size: 40),
            const SizedBox(height: 12),
            Text(
              'Sincronização pendente',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Implemente Sincronizador.indiceEm em\n'
              'lib/player/sincronia.dart para a letra acompanhar o áudio.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _controles() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            StreamBuilder<Duration>(
              stream: _player.positionStream,
              builder: (context, snap) {
                final pos = snap.data ?? Duration.zero;
                final total = _player.duration ?? Duration.zero;
                final max = total.inMilliseconds.toDouble();
                return Column(
                  children: [
                    Slider(
                      value: pos.inMilliseconds
                          .clamp(0, total.inMilliseconds)
                          .toDouble(),
                      max: max <= 0 ? 1 : max,
                      onChanged: max <= 0
                          ? null
                          : (v) =>
                                _player.seek(Duration(milliseconds: v.toInt())),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [Text(_mmss(pos)), Text(_mmss(total))],
                    ),
                  ],
                );
              },
            ),
            StreamBuilder<PlayerState>(
              stream: _player.playerStateStream,
              builder: (context, snap) {
                final tocando = snap.data?.playing ?? false;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_temFila)
                      IconButton(
                        iconSize: 32,
                        tooltip: 'Anterior',
                        onPressed: _anterior,
                        icon: const Icon(Icons.skip_previous),
                      ),
                    IconButton(
                      iconSize: 32,
                      tooltip: 'Voltar 10 segundos',
                      onPressed: () => _player.seek(
                        _player.position - const Duration(seconds: 10),
                      ),
                      icon: const Icon(Icons.replay_10),
                    ),
                    IconButton.filled(
                      iconSize: 44,
                      onPressed: () =>
                          tocando ? _player.pause() : _player.play(),
                      icon: Icon(tocando ? Icons.pause : Icons.play_arrow),
                    ),
                    IconButton(
                      iconSize: 32,
                      tooltip: 'Avançar 10 segundos',
                      onPressed: () => _player.seek(
                        _player.position + const Duration(seconds: 10),
                      ),
                      icon: const Icon(Icons.forward_10),
                    ),
                    if (_temFila)
                      IconButton(
                        iconSize: 32,
                        tooltip: 'Próxima',
                        onPressed: () => _irPara(_pos + 1),
                        icon: const Icon(Icons.skip_next),
                      ),
                  ],
                );
              },
            ),
            if (_temFila) _modos(),
          ],
        ),
      ),
    );
  }

  /// Aleatório, repetição e a posição na fila.
  ///
  /// Ficam numa linha própria, abaixo do transporte: são estados que ficam
  /// ligados, não ações momentâneas, e o realce colorido mostra isso sem
  /// precisar de rótulo.
  Widget _modos() {
    final cor = Theme.of(context).colorScheme;
    final (icone, dica) = switch (_repeticao) {
      ModoRepeticao.nenhum => (Icons.repeat, 'Repetir: desligado'),
      ModoRepeticao.todas => (Icons.repeat_on_outlined, 'Repetir: todas'),
      ModoRepeticao.uma => (Icons.repeat_one_on_outlined, 'Repetir: esta'),
    };

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          tooltip: _aleatorio ? 'Aleatório: ligado' : 'Aleatório: desligado',
          onPressed: _alternarAleatorio,
          isSelected: _aleatorio,
          color: _aleatorio ? cor.primary : null,
          icon: Icon(_aleatorio ? Icons.shuffle_on_outlined : Icons.shuffle),
        ),
        Text(
          '${_pos + 1} de ${widget.fila.length}',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        IconButton(
          tooltip: dica,
          // Percorre desligado → todas → esta, como na maioria dos players.
          onPressed: () => setState(() {
            _repeticao = ModoRepeticao
                .values[(_repeticao.index + 1) % ModoRepeticao.values.length];
          }),
          isSelected: _repeticao != ModoRepeticao.nenhum,
          color: _repeticao != ModoRepeticao.nenhum ? cor.primary : null,
          icon: Icon(icone),
        ),
      ],
    );
  }

  static String _mmss(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// Ordem embaralhada de [total] posições, começando por [atual].
///
/// Embaralhar a lista em vez de sortear a cada faixa é o que garante que toda
/// música toque uma vez antes de qualquer repetição — sorteio independente
/// repete cedo, que é a queixa comum contra o aleatório dos outros players.
///
/// [atual] fica na frente porque ela já está tocando quando o usuário liga o
/// modo: reembaralhar sem isso trocaria a música no meio.
List<int> ordemAleatoria(int total, int atual) {
  final resto = [
    for (var i = 0; i < total; i++)
      if (i != atual) i,
  ]..shuffle();
  return [atual, ...resto];
}

/// Que áudio acompanha a letra.
enum ModoAudio {
  /// A gravação com as vozes.
  cantado('Cantado', Icons.mic),

  /// Só o acompanhamento, para a congregação cantar por cima. Tem tempos de
  /// letra próprios no catálogo (`ms_pb`).
  playback('Playback', Icons.mic_off),

  /// Nenhum áudio: a letra é passada à mão, slide a slide.
  semAudio('Sem áudio', Icons.slideshow_outlined);

  const ModoAudio(this.rotulo, this.icone);

  final String rotulo;
  final IconData icone;
}

/// Como a fila se comporta quando a faixa termina.
enum ModoRepeticao {
  /// Toca até o fim da fila e para.
  nenhum,

  /// Volta ao começo da fila depois da última.
  todas,

  /// Repete a faixa atual indefinidamente.
  uma,
}
