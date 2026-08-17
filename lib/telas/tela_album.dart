import 'package:flutter/material.dart';

import '../dados/download.dart';
import '../dados/midia.dart';
import '../dados/modelos.dart';
import '../dados/repositorio.dart';
import 'tela_player.dart';

class TelaAlbum extends StatefulWidget {
  const TelaAlbum({super.key, required this.album});

  final Album album;

  @override
  State<TelaAlbum> createState() => _TelaAlbumState();
}

class _TelaAlbumState extends State<TelaAlbum> {
  final _repo = const Repositorio();
  late Future<List<Musica>> _futuro;

  /// Quais músicas têm o áudio disponível, seja na pasta copiada ou baixado.
  /// Resolvido em lote para não disparar uma consulta SAF por linha da lista.
  final Map<int, bool> _disponivel = {};

  /// Progresso de 0 a 1 das faixas sendo baixadas agora.
  final Map<int, double> _baixando = {};

  /// Filtro por nome ou número. Nos hinários a faixa É o número do hino, então
  /// digitar "43" leva direto ao hino 43 — o mesmo atalho do programa original.
  String _filtro = '';
  final Map<int, CancelToken> _cancelamentos = {};

  bool _baixandoAlbum = false;

  @override
  void initState() {
    super.initState();
    _futuro = _carregar();
  }

  @override
  void dispose() {
    for (final c in _cancelamentos.values) {
      c.cancelar();
    }
    super.dispose();
  }

  Future<List<Musica>> _carregar() async {
    final musicas = await _repo.musicasDoAlbum(widget.album.id);
    for (final m in musicas) {
      if (m.audio != null) {
        _disponivel[m.id] = await Midia.instancia.existe(m.audio!);
      }
    }
    return musicas;
  }

  Future<void> _baixar(Musica m) async {
    if (m.audio == null || _baixando.containsKey(m.id)) return;

    final cancel = CancelToken();
    _cancelamentos[m.id] = cancel;
    setState(() => _baixando[m.id] = 0);

    try {
      await Download.instancia.baixar(
        m.id,
        m.audio!,
        cancelamento: cancel,
        aoProgredir: (recebidos, total) {
          if (!mounted || total <= 0) return;
          setState(() => _baixando[m.id] = recebidos / total);
        },
      );
      if (mounted) {
        setState(() {
          _disponivel[m.id] = true;
          _baixando.remove(m.id);
        });
      }
    } on DownloadCancelado {
      if (mounted) setState(() => _baixando.remove(m.id));
    } on FalhaDownload catch (e) {
      // Mostra o motivo em vez de um "falhou" genérico: rede, servidor e
      // ausência do arquivo pedem reações diferentes de quem está usando.
      if (mounted) {
        setState(() => _baixando.remove(m.id));
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${m.nome}: ${e.motivo}')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _baixando.remove(m.id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha ao baixar "${m.nome}": $e')),
        );
      }
    } finally {
      _cancelamentos.remove(m.id);
    }
  }

  Future<void> _baixarAlbum(List<Musica> musicas) async {
    setState(() => _baixandoAlbum = true);
    // Sequencial de propósito: baixar doze faixas em paralelo satura a conexão
    // e deixa todas as barras andando devagar, o que parece travamento.
    for (final m in musicas) {
      if (!mounted) break;
      if (_disponivel[m.id] == true || m.audio == null) continue;
      await _baixar(m);
    }
    if (mounted) setState(() => _baixandoAlbum = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.album.nome),
        actions: [
          FutureBuilder<List<Musica>>(
            future: _futuro,
            builder: (context, snap) {
              final musicas = snap.data ?? const <Musica>[];
              final faltando = musicas
                  .where((m) => m.audio != null && _disponivel[m.id] != true)
                  .toList();
              if (faltando.isEmpty) return const SizedBox.shrink();
              return IconButton(
                tooltip: 'Baixar ${faltando.length} faixas',
                onPressed: _baixandoAlbum ? null : () => _baixarAlbum(musicas),
                icon: _baixandoAlbum
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_for_offline_outlined),
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<List<Musica>>(
        future: _futuro,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final todas = snap.data ?? const <Musica>[];
          final musicas = _filtrar(todas);
          return Column(
            children: [
              if (todas.length > 12)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Buscar por nome ou número',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _filtro = v.trim()),
                  ),
                ),
              Expanded(
                child: musicas.isEmpty
                    ? const Center(child: Text('Nada encontrado.'))
                    : ListView.separated(
                        itemCount: musicas.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) => _linha(musicas[i], i),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Musica> _filtrar(List<Musica> todas) {
    if (_filtro.isEmpty) return todas;
    final numero = int.tryParse(_filtro);
    final termo = _filtro.toLowerCase();
    return todas
        .where(
          (m) =>
              (numero != null && m.faixa == numero) ||
              m.nome.toLowerCase().contains(termo),
        )
        .toList();
  }

  static String _duracao(int ms) {
    final d = Duration(milliseconds: ms);
    return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  Widget _linha(Musica m, int i) {
    final temAudio = _disponivel[m.id] ?? false;
    final progresso = _baixando[m.id];

    return ListTile(
      leading: CircleAvatar(child: Text('${m.faixa ?? i + 1}')),
      title: Text(m.nome),
      subtitle: progresso != null
          ? LinearProgressIndicator(value: progresso == 0 ? null : progresso)
          : Row(
              children: [
                if (m.temLetra)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(Icons.lyrics_outlined, size: 14),
                  ),
                Text(
                  [
                    if ((m.duracaoMs ?? 0) > 0) _duracao(m.duracaoMs!),
                    if (!temAudio) 'não baixado',
                  ].join(' · '),
                ),
              ],
            ),
      trailing: progresso != null
          ? IconButton(
              tooltip: 'Cancelar',
              onPressed: () => _cancelamentos[m.id]?.cancelar(),
              icon: const Icon(Icons.close),
            )
          : temAudio
          ? const Icon(Icons.play_arrow)
          : m.audio != null
          ? IconButton(
              tooltip: 'Baixar',
              onPressed: () => _baixar(m),
              icon: const Icon(Icons.download_outlined),
            )
          : const Icon(Icons.text_snippet_outlined),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TelaPlayer(
            musica: m,
            nomeAlbum: widget.album.nome,
            temAudio: temAudio,
          ),
        ),
      ),
    );
  }
}
