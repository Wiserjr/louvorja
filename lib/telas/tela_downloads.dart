import 'package:flutter/material.dart';

import '../dados/fila_download.dart';
import '../dados/modelos.dart';
import '../dados/repositorio.dart';

/// Escolha do que baixar: um álbum, uma categoria inteira ou todo o acervo.
///
/// O tamanho é estimado **antes** de começar e conta apenas o que falta — quem
/// já copiou metade do acervo à mão não deve ver 8 GB anunciados.
class TelaDownloads extends StatefulWidget {
  const TelaDownloads({super.key});

  @override
  State<TelaDownloads> createState() => _TelaDownloadsState();
}

class _TelaDownloadsState extends State<TelaDownloads> {
  final _repo = const Repositorio();
  final _fila = FilaDownload.instancia;

  List<Categoria> _categorias = const [];
  List<Album> _albuns = const [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final cats = await _repo.categorias();
    final albs = await _repo.albuns();
    if (!mounted) return;
    setState(() {
      _categorias = cats;
      _albuns = albs;
      _carregando = false;
    });
  }

  static String _tamanho(int bytes) => bytes < 1048576
      ? '${(bytes / 1024).toStringAsFixed(0)} KB'
      : bytes < 1073741824
      ? '${(bytes / 1048576).toStringAsFixed(0)} MB'
      : '${(bytes / 1073741824).toStringAsFixed(2)} GB';

  Future<void> _preparar(
    String rotulo,
    Future<List<Musica>> Function() buscar,
  ) async {
    final mensageiro = ScaffoldMessenger.of(context);
    setState(() => _carregando = true);
    final todas = await buscar();
    final falta = await _fila.pendentes(todas);
    if (!mounted) return;
    setState(() => _carregando = false);

    if (falta.isEmpty) {
      mensageiro.showSnackBar(
        SnackBar(content: Text('$rotulo: tudo já está no aparelho.')),
      );
      return;
    }

    final confirma = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(rotulo),
        content: Text(
          '${falta.length} faixas a baixar, cerca de '
          '${_tamanho(FilaDownload.bytesDe(falta))}.\n\n'
          'De ${todas.length} faixas no total, '
          '${todas.length - falta.length} já estão no aparelho.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Baixar'),
          ),
        ],
      ),
    );
    if (confirma == true) _fila.iniciar(falta);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Baixar músicas')),
      body: Column(
        children: [
          ValueListenableBuilder<EstadoFila>(
            valueListenable: _fila.estado,
            builder: (context, e, _) {
              if (!e.rodando && e.total == 0) return const SizedBox.shrink();
              return Card(
                margin: const EdgeInsets.all(12),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              e.rodando
                                  ? (e.atual ?? 'Preparando...')
                                  : 'Concluído',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          if (e.rodando)
                            TextButton(
                              onPressed: _fila.cancelar,
                              child: const Text('Parar'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: e.progressoAtual),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: e.progressoGeral,
                        minHeight: 6,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${e.concluidas} de ${e.total} · '
                        '${_tamanho(e.bytesBaixados)} baixados'
                        '${e.falhas > 0 ? ' · ${e.falhas} falharam' : ''}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          if (_carregando) const LinearProgressIndicator(),
          Expanded(
            child: ListView(
              children: [
                const _Titulo('Tudo'),
                ListTile(
                  leading: const Icon(Icons.cloud_download_outlined),
                  title: const Text('Todo o acervo'),
                  subtitle: Text('${_albuns.length} álbuns'),
                  onTap: () => _preparar(
                    'Todo o acervo',
                    () => _repo.musicasParaDownload(),
                  ),
                ),
                const _Titulo('Por categoria'),
                for (final c in _categorias)
                  ListTile(
                    leading: Icon(
                      c.eHinario
                          ? Icons.menu_book_outlined
                          : Icons.folder_outlined,
                    ),
                    title: Text(c.nome),
                    onTap: () => _preparar(
                      c.nome,
                      () => _repo.musicasParaDownload(idCategoria: c.id),
                    ),
                  ),
                const _Titulo('Por álbum'),
                for (final a in _albuns)
                  ListTile(
                    leading: const Icon(Icons.album_outlined),
                    title: Text(a.nome),
                    subtitle: Text('${a.totalMusicas} músicas'),
                    onTap: () => _preparar(
                      a.nome,
                      () => _repo.musicasParaDownload(idAlbum: a.id),
                    ),
                  ),
              ],
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
