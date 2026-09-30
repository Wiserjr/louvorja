import 'package:flutter/material.dart';

import '../app_atual.dart';
import '../dados/fila_download.dart';
import '../dados/modelos.dart';
import '../dados/repositorio.dart';

/// Escolha do que baixar e acompanhamento da fila.
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
  bool _carregandoListas = true;
  bool _calculando = false;

  /// Quais arquivos de cada música entram no lote. Começa só no cantado, como
  /// era antes de o playback existir aqui: quem não precisa dele não deve
  /// baixar o dobro sem perceber.
  Set<_Arquivo> _tipos = {_Arquivo.cantado};

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
      _carregandoListas = false;
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
    if (_fila.rodando) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Já há um download em andamento.')),
      );
      return;
    }

    final mensageiro = ScaffoldMessenger.of(context);
    // Lido antes da consulta: o lote é o que estava escolhido no toque.
    final tipos = _tipos;
    setState(() => _calculando = true);
    final todos = FilaDownload.itensDe(
      await buscar(),
      cantado: tipos.contains(_Arquivo.cantado),
      playback: tipos.contains(_Arquivo.playback),
    );
    final falta = await _fila.pendentes(todos);
    if (!mounted) return;
    setState(() => _calculando = false);

    if (todos.isEmpty) {
      // Acontece ao pedir só o playback de um álbum que não tem nenhum.
      mensageiro.showSnackBar(
        SnackBar(
          content: Text('$rotulo: não há ${_descricao(tipos)} no acervo.'),
        ),
      );
      return;
    }
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${falta.length} arquivos a baixar, cerca de '
              '${_tamanho(FilaDownload.bytesDe(falta))}.',
            ),
            // Com os dois tipos, diz quanto é de cada: o total sozinho não
            // mostra que um deles já estava quase todo no aparelho.
            if (tipos.length > 1) ...[
              const SizedBox(height: 6),
              Text(
                '${falta.where((i) => !i.playback).length} cantados e '
                '${falta.where((i) => i.playback).length} playbacks.',
              ),
            ],
            const SizedBox(height: 10),
            Text(
              'De ${todos.length} no total, '
              '${todos.length - falta.length} já estão no aparelho.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (falta.length > 200) ...[
              const SizedBox(height: 14),
              Text(
                'Lote grande: o app baixa uma por vez, com pausa entre elas, '
                'para não sobrecarregar o servidor do acervo. Pode levar horas — '
                'e você pode sair desta tela sem interromper.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
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
      appBar: AppBar(
        title: Text(soHinarios ? 'Baixar hinos' : 'Baixar músicas'),
      ),
      body: Column(
        children: [
          ValueListenableBuilder<EstadoFila>(
            valueListenable: _fila.estado,
            builder: (context, e, _) => _painel(e),
          ),
          if (_calculando)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text('Calculando o que falta...'),
                ],
              ),
            ),
          _escolhaDeTipos(),
          Expanded(child: _carregandoListas ? _esqueleto() : _opcoes()),
        ],
      ),
    );
  }

  Widget _esqueleto() => const Center(child: CircularProgressIndicator());

  /// O que foi escolhido, por extenso, para as mensagens.
  static String _descricao(Set<_Arquivo> tipos) => tipos.length > 1
      ? 'áudio'
      : tipos.first == _Arquivo.playback
      ? 'playback'
      : 'áudio cantado';

  /// Cantado, playback ou os dois. Fica fixo acima da lista, e não rolando com
  /// ela: a escolha vale para o toque em qualquer linha, e precisa estar à
  /// vista quando o toque acontece lá embaixo, num álbum qualquer.
  Widget _escolhaDeTipos() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Row(
      children: [
        Text('Baixar', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(width: 12),
        Expanded(
          child: SegmentedButton<_Arquivo>(
            multiSelectionEnabled: true,
            segments: const [
              ButtonSegment(
                value: _Arquivo.cantado,
                label: Text('Cantado'),
                icon: Icon(Icons.mic),
              ),
              ButtonSegment(
                value: _Arquivo.playback,
                label: Text('Playback'),
                icon: Icon(Icons.mic_off),
              ),
            ],
            selected: _tipos,
            // Trocar durante um lote não o afeta: os arquivos dele foram
            // definidos ao começar, e um segundo lote só começa depois.
            onSelectionChanged: (s) => setState(() => _tipos = s),
          ),
        ),
      ],
    ),
  );

  /// Painel de acompanhamento.
  ///
  /// Mostra uma barra só — a do lote. O progresso do arquivo corrente vira um
  /// traço fino sob o nome dele, para não competir com o total: duas barras de
  /// mesmo peso empilhadas era o que tornava a tela anterior confusa.
  Widget _painel(EstadoFila e) {
    if (e.total == 0) return const SizedBox.shrink();
    final tema = Theme.of(context);
    final cor = tema.colorScheme;

    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    e.rodando
                        ? 'Baixando ${e.processadas + 1} de ${e.total}'
                        : e.terminou
                        ? 'Concluído'
                        : 'Interrompido',
                    style: tema.textTheme.titleSmall,
                  ),
                ),
                if (e.rodando)
                  TextButton(
                    onPressed: _fila.cancelar,
                    child: const Text('Parar'),
                  )
                else ...[
                  if (e.falhas.isNotEmpty)
                    TextButton(
                      onPressed: _fila.repetirFalhas,
                      child: Text('Tentar ${e.falhas.length} de novo'),
                    ),
                  IconButton(
                    tooltip: 'Limpar',
                    onPressed: _fila.limpar,
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: e.progressoGeral, minHeight: 8),
            const SizedBox(height: 10),
            if (e.rodando && e.atual != null) ...[
              Text(
                e.atual!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tema.textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: e.aguardando ? null : e.progressoAtual,
                minHeight: 2,
              ),
              if (e.tentativa > 1 || e.aguardando)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    e.aguardando
                        ? 'Falhou; aguardando para tentar de novo '
                              '(tentativa ${e.tentativa})'
                        : 'Tentativa ${e.tentativa}',
                    style: tema.textTheme.labelSmall?.copyWith(
                      color: cor.error,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
            ],
            Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                _contador(
                  Icons.check_circle_outline,
                  '${e.baixadas} baixadas',
                  cor.primary,
                ),
                if (e.falhas.isNotEmpty)
                  _contador(
                    Icons.error_outline,
                    '${e.falhas.length} falharam',
                    cor.error,
                  ),
                if (e.restantes > 0 && e.rodando)
                  _contador(
                    Icons.schedule,
                    '${e.restantes} restantes',
                    cor.onSurfaceVariant,
                  ),
                _contador(
                  Icons.sd_storage_outlined,
                  _tamanho(e.bytesBaixados),
                  cor.onSurfaceVariant,
                ),
              ],
            ),
            if (e.desacelerou)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'O servidor pediu calma; o app reduziu o ritmo.',
                  style: tema.textTheme.labelSmall?.copyWith(
                    color: cor.onSurfaceVariant,
                  ),
                ),
              ),
            if (e.falhas.isNotEmpty && !e.rodando) _listaFalhas(e),
          ],
        ),
      ),
    );
  }

  Widget _contador(IconData icone, String texto, Color cor) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icone, size: 14, color: cor),
      const SizedBox(width: 4),
      Text(
        texto,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: cor),
      ),
    ],
  );

  /// As falhas com o motivo de cada uma.
  ///
  /// Agrupadas por motivo: num lote grande, mil falhas costumam ter duas ou três
  /// causas, e ver "1.200 × Rede: connection closed" diz muito mais do que mil
  /// linhas iguais.
  Widget _listaFalhas(EstadoFila e) {
    final porMotivo = <String, int>{};
    for (final f in e.falhas) {
      porMotivo[f.motivo] = (porMotivo[f.motivo] ?? 0) + 1;
    }
    final motivos = porMotivo.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        title: Text(
          'Por que falharam',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        children: [
          for (final m in motivos)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 44,
                    child: Text(
                      '${m.value}×',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      m.key,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Text(
            'Exemplos: '
            '${e.falhas.take(3).map((f) => f.item.nome).join(', ')}'
            '${e.falhas.length > 3 ? '...' : ''}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }

  Widget _opcoes() => ListView(
    children: [
      const _Titulo('Tudo'),
      ListTile(
        leading: const Icon(Icons.cloud_download_outlined),
        // No Hinários o "acervo" são os dois hinários, e é assim que ele deve
        // se chamar para quem nunca ouviu falar do resto.
        title: Text(soHinarios ? 'Os dois hinários' : 'Todo o acervo'),
        subtitle: Text('${_albuns.length} álbuns'),
        onTap: () => _preparar(
          soHinarios ? 'Os dois hinários' : 'Todo o acervo',
          () => _repo.musicasParaDownload(),
        ),
      ),
      const _Titulo('Por categoria'),
      for (final c in _categorias)
        ListTile(
          leading: Icon(
            c.eHinario ? Icons.menu_book_outlined : Icons.folder_outlined,
          ),
          title: Text(c.nome),
          onTap: () => _preparar(
            c.nome,
            () => _repo.musicasParaDownload(idCategoria: c.id),
          ),
        ),
      // No Hinários cada categoria tem um álbum só: a lista repetiria a de
      // cima.
      if (!soHinarios) const _Titulo('Por álbum'),
      for (final a in soHinarios ? const <Album>[] : _albuns)
        ListTile(
          leading: const Icon(Icons.album_outlined),
          title: Text(a.nome),
          subtitle: Text('${a.totalMusicas} músicas'),
          onTap: () =>
              _preparar(a.nome, () => _repo.musicasParaDownload(idAlbum: a.id)),
        ),
    ],
  );
}

/// Os arquivos que cada música pode ter no acervo.
enum _Arquivo { cantado, playback }

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
