import 'package:flutter/material.dart';

import '../dados/midia.dart';
import '../dados/modelos.dart';
import '../dados/repositorio.dart';
import 'capa_album.dart';
import 'tela_album.dart';
import 'tela_player.dart';

/// Grade de álbuns organizada por categoria.
///
/// O programa original usa uma faixa de botões — Hinário Adventista, CDs
/// Oficiais/Ano, Adoradores, Diversas... Numa tela de celular o equivalente
/// natural são chips de filtro acima da grade.
class TelaAlbuns extends StatefulWidget {
  const TelaAlbuns({super.key});

  @override
  State<TelaAlbuns> createState() => _TelaAlbunsState();
}

class _TelaAlbunsState extends State<TelaAlbuns> {
  final _repo = const Repositorio();

  List<Categoria> _categorias = const [];
  Categoria? _selecionada;
  late Future<List<Album>> _albuns;
  String _busca = '';

  /// Resultados da busca global. Enquanto o campo está vazio segue valendo a
  /// grade por categoria; com texto, o acervo inteiro é varrido de uma vez.
  Future<_Resultados>? _resultados;

  void _buscar(String v) {
    final termo = v.trim();
    setState(() {
      _busca = termo;
      _resultados = termo.isEmpty ? null : _procurar(termo);
    });
  }

  Future<_Resultados> _procurar(String termo) async {
    final t = termo.toLowerCase();
    final todos = await _repo.albuns();
    return _Resultados(
      albuns: todos.where((a) => a.nome.toLowerCase().contains(t)).toList(),
      musicas: await _repo.buscarMusicas(termo),
    );
  }

  @override
  void initState() {
    super.initState();
    _albuns = _repo.albuns();
    _carregarCategorias();
  }

  Future<void> _carregarCategorias() async {
    final cats = await _repo.categorias();
    if (mounted) setState(() => _categorias = cats);
  }

  void _selecionar(Categoria? c) {
    setState(() {
      _selecionada = c;
      _albuns = c == null ? _repo.albuns() : _repo.albunsDaCategoria(c.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: SearchBar(
              hintText: 'Buscar álbum, música ou nº do hino',
              leading: const Icon(Icons.search),
              onChanged: _buscar,
            ),
          ),
          if (_categorias.isNotEmpty && _resultados == null)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: const Text('Todos'),
                      selected: _selecionada == null,
                      onSelected: (_) => _selecionar(null),
                    ),
                  ),
                  for (final c in _categorias)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        avatar: c.eHinario
                            ? const Icon(Icons.menu_book_outlined, size: 18)
                            : null,
                        label: Text(c.nome),
                        selected: _selecionada?.id == c.id,
                        onSelected: (_) => _selecionar(c),
                      ),
                    ),
                ],
              ),
            ),
          if (_resultados != null)
            Expanded(child: _listaResultados())
          else
            Expanded(
              child: FutureBuilder<List<Album>>(
                future: _albuns,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Center(
                      child: Text('Erro ao ler o catálogo:\n${snap.error}'),
                    );
                  }
                  final albuns = snap.data!;
                  if (albuns.isEmpty) {
                    return const Center(
                      child: Text('Nenhum álbum encontrado.'),
                    );
                  }
                  return GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 180,
                          childAspectRatio: 0.72,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    itemCount: albuns.length,
                    itemBuilder: (context, i) => _Cartao(album: albuns[i]),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _listaResultados() {
    return FutureBuilder<_Resultados>(
      future: _resultados,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final r = snap.data!;
        if (r.vazio) {
          return Center(child: Text('Nada encontrado para "$_busca".'));
        }
        return ListView(
          children: [
            if (r.albuns.isNotEmpty) ...[
              _Secao('Álbuns', r.albuns.length),
              for (final a in r.albuns)
                ListTile(
                  leading: SizedBox(
                    width: 48,
                    child: CapaAlbum(album: a, raio: 6),
                  ),
                  title: Text(a.nome),
                  subtitle: Text(
                    [
                      if (a.subtitulo != null) a.subtitulo!,
                      '${a.totalMusicas} músicas',
                    ].join(' · '),
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => TelaAlbum(album: a)),
                  ),
                ),
            ],
            if (r.musicas.isNotEmpty) ...[
              _Secao('Músicas', r.musicas.length),
              for (final m in r.musicas)
                ListTile(
                  // Nem todo álbum numera faixas: a Doxologia usa 0. O número
                  // só aparece quando significa algo — nos hinários ele é o
                  // número do hino.
                  leading: CircleAvatar(
                    radius: 18,
                    child: (m.faixa ?? 0) > 0
                        ? Text(
                            '${m.faixa}',
                            style: const TextStyle(fontSize: 12),
                          )
                        : const Icon(Icons.music_note, size: 16),
                  ),
                  title: Text(m.nome),
                  subtitle: Text(
                    [
                      if (m.albumNome != null) m.albumNome!,
                      if ((m.duracaoMs ?? 0) > 0) _mmss(m.duracaoMs!),
                    ].join(' · '),
                  ),
                  trailing: m.temLetra
                      ? const Icon(Icons.lyrics_outlined, size: 16)
                      : null,
                  onTap: () => _abrirMusica(m),
                ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _abrirMusica(Musica m) async {
    final temAudio = m.audio != null && await Midia.instancia.existe(m.audio!);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TelaPlayer(
          musica: m,
          nomeAlbum: m.albumNome ?? '',
          temAudio: temAudio,
        ),
      ),
    );
  }

  static String _mmss(int ms) {
    final d = Duration(milliseconds: ms);
    return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }
}

class _Resultados {
  const _Resultados({required this.albuns, required this.musicas});

  final List<Album> albuns;
  final List<Musica> musicas;

  bool get vazio => albuns.isEmpty && musicas.isEmpty;
}

class _Secao extends StatelessWidget {
  const _Secao(this.titulo, this.quantidade);

  final String titulo;
  final int quantidade;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
    child: Text(
      '${titulo.toUpperCase()} · $quantidade',
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        letterSpacing: 1.1,
      ),
    ),
  );
}

class _Cartao extends StatelessWidget {
  const _Cartao({required this.album});

  final Album album;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () =>
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => TelaAlbum(album: album))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CapaAlbum(album: album),
          const SizedBox(height: 6),
          // Altura fixa de duas linhas: sem isso, um título que quebra empurra o
          // subtítulo para baixo e as células da mesma fileira deixam de se
          // alinhar — o que dava à grade o aspecto desalinhado.
          SizedBox(
            height: 30,
            child: Text(
              album.nome,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: tema.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.15,
              ),
            ),
          ),
          Text(
            [
              if (album.subtitulo != null) album.subtitulo!,
              '${album.totalMusicas} músicas',
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tema.textTheme.labelSmall?.copyWith(
              color: tema.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
