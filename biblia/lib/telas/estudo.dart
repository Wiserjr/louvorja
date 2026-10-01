import 'package:flutter/material.dart';

import '../dados/ajustes.dart';
import '../dados/biblia.dart';
import '../dados/estudo.dart';
import '../dados/mapas.dart';
import '../dados/modelos.dart';
import '../dados/referencias.dart';
import '../dados/sinotico.dart';
import '../dados/temas.dart';
import 'acoes_versiculo.dart';
import 'biblioteca.dart';
import 'cartao_trecho.dart';
import 'mapa_vista.dart';
import 'mapas.dart';
import 'sinotico.dart';
import 'tema.dart';
import 'temas.dart';
import 'texto_biblico.dart';

/// Tudo sobre um versículo, como nas margens de uma Bíblia de estudo:
/// notas, Ellen G. White, pioneiros, citações do AT/NT e paralelos,
/// referências cruzadas e as outras traduções.
class PainelEstudo extends StatefulWidget {
  const PainelEstudo({
    super.key,
    required this.posicao,
    required this.versao,
    required this.aoIr,
    this.rolagem,
  });

  final Posicao posicao;
  final Versao versao;
  final ValueChanged<Posicao> aoIr;

  /// Controlador da folha arrastável, no celular.
  final ScrollController? rolagem;

  @override
  State<PainelEstudo> createState() => _PainelEstudoState();
}

class _Dados {
  _Dados({
    required this.texto,
    required this.trechos,
    required this.referencias,
    required this.notas,
    required this.lugares,
    required this.temas,
    required this.eventos,
  });
  final String texto;
  final List<Trecho> trechos;
  final List<RefCruzada> referencias;
  final List<Nota> notas;
  final List<Lugar> lugares;
  final List<Tema> temas;
  final List<EventoSinotico> eventos;
}

class _PainelEstudoState extends State<PainelEstudo> {
  late final Future<_Dados> _dados = _carregar();

  int get _livro => widget.posicao.livro;
  int get _cap => widget.posicao.capitulo;
  int get _ver => widget.posicao.versiculo!;

  Future<_Dados> _carregar() async {
    final b = Biblia.instancia, e = Estudo.instancia;
    final r = await Future.wait([
      b.intervalo(
        widget.versao.id,
        _livro,
        chave(_cap, _ver),
        chave(_cap, _ver),
      ),
      e.trechos(_livro, _cap, _ver),
      e.referencias(_livro, _cap, _ver),
      e.notas(_livro, _cap, _ver),
      Mapas.instancia.doVersiculo(_livro, _cap, _ver),
      Temas.instancia.doVersiculo(_livro, _cap, _ver),
      Sinotico.instancia.doVersiculo(_livro, _cap, _ver),
    ]);
    final linhas = r[0] as List<(int, int, String)>;
    return _Dados(
      texto: linhas.isEmpty ? '' : linhas.first.$3,
      trechos: r[1] as List<Trecho>,
      referencias: r[2] as List<RefCruzada>,
      notas: r[3] as List<Nota>,
      lugares: r[4] as List<Lugar>,
      temas: r[5] as List<Tema>,
      eventos: r[6] as List<EventoSinotico>,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Dados>(
      future: _dados,
      builder: (context, snap) {
        final d = snap.data;
        if (d == null) {
          return Center(
            child: snap.hasError
                ? Text('Erro: ${snap.error}')
                : const CircularProgressIndicator(),
          );
        }
        return ListenableBuilder(
          listenable: Ajustes.instancia,
          builder: (context, _) => _lista(context, d),
        );
      },
    );
  }

  Widget _lista(BuildContext context, _Dados d) {
    final t = Theme.of(context);
    final aj = Ajustes.instancia;
    final egw = [
      for (final x in d.trechos)
        if (x.obra.deEllenWhite) x,
    ];
    final pioneiros = aj.mostrarPioneiros
        ? [
            for (final x in d.trechos)
              if (!x.obra.deEllenWhite) x,
          ]
        : const <Trecho>[];
    final especiais = [
      for (final r in d.referencias)
        if (r.tipo != 0) r,
    ];
    final tematicas = [
      for (final r in d.referencias)
        if (r.tipo == 0) r,
    ];
    final anotacao = aj.anotacao(_livro, _cap, _ver);
    final ref = '${Referencias.nome(_livro)} $_cap:$_ver';

    return ListView(
      controller: widget.rolagem,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        Text(ref, style: t.textTheme.titleLarge),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(
            children: spansDoTexto(
              d.texto,
              estilo: t.textTheme.bodyLarge!.copyWith(height: 1.5),
              corJesus: corJesus(context),
              vermelho: aj.letrasVermelhas,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(child: BarraMarcacao(posicao: widget.posicao)),
            IconButton(
              tooltip: 'Anotar',
              icon: const Icon(Icons.edit_note),
              onPressed: () => editarAnotacao(context, widget.posicao),
            ),
            IconButton(
              tooltip: 'Copiar, compartilhar',
              icon: const Icon(Icons.more_horiz),
              onPressed: () => mostrarAcoesVersiculo(
                context,
                widget.posicao,
                d.texto,
                widget.versao,
              ),
            ),
          ],
        ),
        if (anotacao != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('Sua anotação'),
              subtitle: Text(anotacao),
              onTap: () => editarAnotacao(context, widget.posicao),
            ),
          ),
        if (d.notas.isNotEmpty)
          _Secao(
            titulo: 'Nota de estudo',
            icone: Icons.sticky_note_2_outlined,
            inicialmenteAberta: true,
            filhos: [
              for (final n in d.notas)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (n.ini != n.fim)
                        Text(
                          Referencias.formatar(n.livro, n.ini, n.fim),
                          style: t.textTheme.labelMedium,
                        ),
                      Text(n.texto, style: t.textTheme.bodyMedium),
                    ],
                  ),
                ),
              Text(
                'Nota escrita com inteligência artificial para este app. '
                'Confira sempre com a Bíblia.',
                style: t.textTheme.labelSmall?.copyWith(color: t.hintColor),
              ),
            ],
          ),
        _Secao(
          titulo: 'Ellen G. White',
          contagem: egw.length,
          icone: Icons.menu_book_outlined,
          cor: corEgw(context),
          inicialmenteAberta: true,
          vazio:
              'Nenhum dos livros indexados cita este versículo diretamente. '
              'Veja as referências cruzadas: os versículos ligados a este '
              'costumam ter comentários.',
          rodape: egw.isEmpty ? null : const _AvisoBiblioteca(),
          filhos: [for (final x in egw) CartaoTrecho(trecho: x)],
          limite: 6,
        ),
        if (aj.mostrarPioneiros)
          _Secao(
            titulo: 'Pioneiros adventistas',
            contagem: pioneiros.length,
            icone: Icons.history_edu_outlined,
            vazio: 'Nenhum livro dos pioneiros cita este versículo.',
            filhos: [for (final x in pioneiros) CartaoTrecho(trecho: x)],
            limite: 4,
          ),
        if (especiais.isNotEmpty)
          _Secao(
            titulo: _livro >= 40
                ? 'Citações do AT e paralelos'
                : 'Citado no NT e paralelos',
            contagem: especiais.length,
            icone: Icons.format_quote,
            inicialmenteAberta: true,
            filhos: [
              _ListaReferencias(
                refs: especiais,
                versao: widget.versao,
                aoIr: widget.aoIr,
              ),
            ],
          ),
        if (d.eventos.isNotEmpty)
          _Secao(
            titulo: 'Nos quatro evangelhos',
            icone: Icons.view_column_outlined,
            inicialmenteAberta: true,
            filhos: [
              for (final e in d.eventos)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(e.titulo),
                  subtitle: Text(
                    [
                      for (final l in evangelhos)
                        if (e.passagens[l] != null)
                          '${Referencias.abreviacao(l)} '
                              '${refCurta(e.passagens[l]!)}',
                    ].join(' · '),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => abrirEvento(context, e, widget.versao),
                ),
            ],
          ),
        if (d.lugares.isNotEmpty)
          _Secao(
            titulo: 'Lugares',
            contagem: d.lugares.length,
            icone: Icons.place_outlined,
            inicialmenteAberta: true,
            filhos: [_MiniMapa(lugares: d.lugares, versao: widget.versao)],
          ),
        if (d.temas.isNotEmpty)
          _Secao(
            titulo: 'Temas',
            contagem: d.temas.length,
            icone: Icons.topic_outlined,
            inicialmenteAberta: true,
            filhos: [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final x in d.temas)
                    ActionChip(
                      label: Text(x.titulo),
                      onPressed: () => abrirTema(context, x, widget.versao),
                    ),
                ],
              ),
            ],
          ),
        _Secao(
          titulo: 'Referências cruzadas',
          contagem: tematicas.length,
          icone: Icons.link,
          vazio: 'Sem referências cruzadas para este versículo.',
          filhos: [
            if (tematicas.isNotEmpty)
              _ListaReferencias(
                refs: tematicas,
                versao: widget.versao,
                aoIr: widget.aoIr,
              ),
          ],
        ),
        _Secao(
          titulo: 'Comparar traduções',
          icone: Icons.translate,
          filhos: [_Comparar(posicao: widget.posicao)],
        ),
      ],
    );
  }
}

class _AvisoBiblioteca extends StatelessWidget {
  const _AvisoBiblioteca();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TelaBiblioteca()),
        ),
        icon: const Icon(Icons.local_library_outlined, size: 18),
        label: const Text('Baixar a biblioteca inteira para ler sem internet'),
      ),
    );
  }
}

/// Seção recolhível com contagem.
class _Secao extends StatefulWidget {
  const _Secao({
    required this.titulo,
    required this.icone,
    required this.filhos,
    this.contagem,
    this.cor,
    this.vazio,
    this.rodape,
    this.limite,
    this.inicialmenteAberta = false,
  });

  final String titulo;
  final IconData icone;
  final List<Widget> filhos;
  final int? contagem;
  final Color? cor;
  final String? vazio;
  final Widget? rodape;
  final int? limite;
  final bool inicialmenteAberta;

  @override
  State<_Secao> createState() => _SecaoState();
}

class _SecaoState extends State<_Secao> {
  late bool _aberta = widget.inicialmenteAberta;
  late int _mostrar = widget.limite ?? 1 << 30;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cor = widget.cor ?? t.colorScheme.primary;
    final filhos = widget.filhos;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _aberta = !_aberta),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(widget.icone, size: 20, color: cor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.titulo,
                      style: t.textTheme.titleSmall?.copyWith(color: cor),
                    ),
                  ),
                  if (widget.contagem != null)
                    Text(
                      '${widget.contagem}',
                      style: t.textTheme.labelMedium?.copyWith(
                        color: t.hintColor,
                      ),
                    ),
                  Icon(_aberta ? Icons.expand_less : Icons.expand_more),
                ],
              ),
            ),
          ),
          if (_aberta) ...[
            if (filhos.isEmpty && widget.vazio != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(widget.vazio!, style: t.textTheme.bodySmall),
              ),
            ...filhos.take(_mostrar),
            if (filhos.length > _mostrar)
              TextButton(
                onPressed: () => setState(() => _mostrar += 10),
                child: Text('Mostrar mais (${filhos.length - _mostrar})'),
              ),
            ?widget.rodape,
          ],
        ],
      ),
    );
  }
}

class _ListaReferencias extends StatefulWidget {
  const _ListaReferencias({
    required this.refs,
    required this.versao,
    required this.aoIr,
  });
  final List<RefCruzada> refs;
  final Versao versao;
  final ValueChanged<Posicao> aoIr;

  @override
  State<_ListaReferencias> createState() => _ListaReferenciasState();
}

class _ListaReferenciasState extends State<_ListaReferencias> {
  int _mostrar = 12;

  @override
  Widget build(BuildContext context) {
    final lista = widget.refs.take(_mostrar).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final r in lista)
          _ItemReferencia(
            key: ValueKey('${r.livro}:${r.ini}:${r.fim}'),
            ref: r,
            versao: widget.versao,
            aoIr: widget.aoIr,
          ),
        if (widget.refs.length > _mostrar)
          TextButton(
            onPressed: () => setState(() => _mostrar += 20),
            child: Text('Mostrar mais (${widget.refs.length - _mostrar})'),
          ),
      ],
    );
  }
}

class _ItemReferencia extends StatefulWidget {
  const _ItemReferencia({
    super.key,
    required this.ref,
    required this.versao,
    required this.aoIr,
  });
  final RefCruzada ref;
  final Versao versao;
  final ValueChanged<Posicao> aoIr;

  @override
  State<_ItemReferencia> createState() => _ItemReferenciaState();
}

class _ItemReferenciaState extends State<_ItemReferencia> {
  late final Future<List<(int, int, String)>> _texto = Biblia.instancia
      .intervalo(
        widget.versao.id,
        widget.ref.livro,
        widget.ref.ini,
        widget.ref.fim,
        limite: 4,
      );

  @override
  Widget build(BuildContext context) {
    final r = widget.ref;
    final t = Theme.of(context);
    final rotulo = r.citacao
        ? 'Citação'
        : r.paralelo
        ? 'Paralelo'
        : r.alusao
        ? 'Alusão'
        : null;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => widget.aoIr(
        Posicao(
          r.livro,
          r.ini ~/ 1000,
          r.ini % 1000 == 0 ? null : r.ini % 1000,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  Referencias.formatar(r.livro, r.ini, r.fim),
                  style: t.textTheme.labelLarge?.copyWith(
                    color: t.colorScheme.primary,
                  ),
                ),
                if (rotulo != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: t.colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      rotulo,
                      style: t.textTheme.labelSmall?.copyWith(
                        color: t.colorScheme.onTertiaryContainer,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            FutureBuilder<List<(int, int, String)>>(
              future: _texto,
              builder: (context, snap) {
                final linhas = snap.data ?? const [];
                if (linhas.isEmpty) return const SizedBox.shrink();
                final texto = linhas
                    .map(
                      (l) => linhas.length > 1
                          ? '${l.$2} ${textoPuro(l.$3)}'
                          : textoPuro(l.$3),
                    )
                    .join(' ');
                return Text(
                  texto,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: t.textTheme.bodySmall?.copyWith(height: 1.4),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Comparar extends StatefulWidget {
  const _Comparar({required this.posicao});
  final Posicao posicao;

  @override
  State<_Comparar> createState() => _CompararState();
}

class _CompararState extends State<_Comparar> {
  late final Future<List<(Versao, String)>> _textos = Biblia.instancia.comparar(
    widget.posicao.livro,
    widget.posicao.capitulo,
    widget.posicao.versiculo!,
  );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return FutureBuilder<List<(Versao, String)>>(
      future: _textos,
      builder: (context, snap) {
        final lista = snap.data;
        if (lista == null) return const LinearProgressIndicator();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (v, texto) in lista)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${v.sigla}  ',
                        style: t.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: t.colorScheme.primary,
                        ),
                      ),
                      ...spansDoTexto(
                        texto,
                        estilo: t.textTheme.bodyMedium!,
                        corJesus: corJesus(context),
                        vermelho: Ajustes.instancia.letrasVermelhas,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Os lugares do versículo num mapa pequeno, com os nomes para tocar.
class _MiniMapa extends StatefulWidget {
  const _MiniMapa({required this.lugares, required this.versao});
  final List<Lugar> lugares;
  final Versao versao;

  @override
  State<_MiniMapa> createState() => _MiniMapaState();
}

class _MiniMapaState extends State<_MiniMapa> {
  late final Future<Geometria> _geo = Mapas.instancia.geometria();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            height: 170,
            child: FutureBuilder<Geometria>(
              future: _geo,
              builder: (context, snap) => snap.data == null
                  ? const SizedBox.shrink()
                  : VistaMapa(
                      geometria: snap.data!,
                      lugares: widget.lugares,
                      destaque: {for (final l in widget.lugares) l.id},
                      interativo: false,
                      margem: 0.3,
                      vizinhanca: 0.8,
                      aoTocarLugar: (l) =>
                          abrirLugar(context, l, widget.versao),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final l in widget.lugares)
              ActionChip(
                avatar: Icon(
                  l.incerto ? Icons.radio_button_unchecked : Icons.place,
                  size: 16,
                ),
                label: Text(l.nome),
                onPressed: () => abrirLugar(context, l, widget.versao),
              ),
          ],
        ),
      ],
    );
  }
}
