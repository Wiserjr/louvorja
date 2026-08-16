import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../dados/modelos.dart';
import '../dados/repositorio.dart';

/// Coletâneas on-line: canais, playlists e vídeos do YouTube.
///
/// A navegação inteira funciona sem rede, porque as miniaturas vêm embutidas no
/// catálogo — o programa original já as guardava em base64. Só a reprodução do
/// vídeo em si exige conexão.
class TelaOnline extends StatefulWidget {
  const TelaOnline({super.key});

  @override
  State<TelaOnline> createState() => _TelaOnlineState();
}

class _TelaOnlineState extends State<TelaOnline> {
  final _repo = const Repositorio();
  late Future<List<PlaylistOnline>> _playlists;
  List<Canal> _canais = const [];
  Canal? _canal;

  @override
  void initState() {
    super.initState();
    _playlists = _repo.playlists();
    _repo.canais().then((c) {
      if (mounted) setState(() => _canais = c);
    });
  }

  void _filtrar(Canal? c) {
    setState(() {
      _canal = c;
      _playlists = _repo.playlists(idCanal: c?.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          if (_canais.isNotEmpty)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: const Text('Todos os canais'),
                      selected: _canal == null,
                      onSelected: (_) => _filtrar(null),
                    ),
                  ),
                  for (final c in _canais)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(c.nome),
                        selected: _canal?.id == c.id,
                        onSelected: (_) => _filtrar(c),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: FutureBuilder<List<PlaylistOnline>>(
              future: _playlists,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final lista = snap.data ?? const <PlaylistOnline>[];
                if (lista.isEmpty) {
                  return const Center(
                    child: Text('Nenhuma coletânea on-line.'),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: lista.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, indent: 96),
                  itemBuilder: (context, i) {
                    final p = lista[i];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      leading: _Miniatura(bytes: p.thumb, largura: 72),
                      title: Text(
                        p.nome,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        [
                          if (p.canalNome != null) p.canalNome!,
                          '${p.totalVideos} vídeos',
                        ].join(' · '),
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => TelaPlaylistOnline(playlist: p),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class TelaPlaylistOnline extends StatelessWidget {
  const TelaPlaylistOnline({super.key, required this.playlist});

  final PlaylistOnline playlist;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(playlist.nome, maxLines: 2)),
      body: FutureBuilder<List<VideoOnline>>(
        future: const Repositorio().videos(playlist.id),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final videos = snap.data!;
          return ListView.separated(
            itemCount: videos.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 104),
            itemBuilder: (context, i) {
              final v = videos[i];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                leading: _Miniatura(bytes: v.thumb, largura: 80),
                title: Text(
                  v.nome,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TelaVideo(videos: videos, inicial: i),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Reprodução dentro do app, pelo player oficial embutido do YouTube.
class TelaVideo extends StatefulWidget {
  const TelaVideo({super.key, required this.videos, required this.inicial});

  final List<VideoOnline> videos;
  final int inicial;

  @override
  State<TelaVideo> createState() => _TelaVideoState();
}

class _TelaVideoState extends State<TelaVideo> {
  late final YoutubePlayerController _controle;
  late int _atual;

  @override
  void initState() {
    super.initState();
    _atual = widget.inicial;
    _controle = YoutubePlayerController.fromVideoId(
      videoId: widget.videos[_atual].videoId,
      autoPlay: true,
      params: const YoutubePlayerParams(showFullscreenButton: true),
    );
  }

  @override
  void dispose() {
    _controle.close();
    super.dispose();
  }

  void _tocar(int i) {
    setState(() => _atual = i);
    _controle.loadVideoById(videoId: widget.videos[i].videoId);
  }

  @override
  Widget build(BuildContext context) {
    // A partir da 6.0 o próprio YoutubePlayer cuida da tela cheia por
    // OverlayPortal; o antigo YoutubePlayerScaffold virou desnecessário.
    return YoutubePlayerControllerProvider(
      controller: _controle,
      child: Scaffold(
        appBar: AppBar(title: Text(widget.videos[_atual].nome, maxLines: 1)),
        body: Column(
          children: [
            YoutubePlayer(controller: _controle),
            Expanded(
              child: ListView.separated(
                itemCount: widget.videos.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final v = widget.videos[i];
                  final tocando = i == _atual;
                  return ListTile(
                    dense: true,
                    selected: tocando,
                    leading: tocando
                        ? const Icon(Icons.play_arrow)
                        : _Miniatura(bytes: v.thumb, largura: 56),
                    title: Text(
                      v.nome,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _tocar(i),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Miniatura vinda do catálogo.
///
/// O rótulo MIME da origem diz `image/png` mas os bytes são JPEG; guardar os
/// bytes crus e deixar o decodificador identificar evita depender desse rótulo.
class _Miniatura extends StatelessWidget {
  const _Miniatura({required this.bytes, required this.largura});

  final Uint8List? bytes;
  final double largura;

  @override
  Widget build(BuildContext context) {
    final vazio = Container(
      width: largura,
      height: largura * 9 / 16,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(Icons.smart_display_outlined, size: 20),
    );
    if (bytes == null) return vazio;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.memory(
        bytes!,
        width: largura,
        height: largura * 9 / 16,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => vazio,
      ),
    );
  }
}
