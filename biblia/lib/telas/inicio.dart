import 'package:flutter/material.dart';

import '../dados/ajustes.dart';
import '../dados/biblia.dart';
import '../dados/modelos.dart';
import '../dados/referencias.dart';
import 'ajustes.dart';
import 'atualizacao_app.dart';
import 'biblioteca.dart';
import 'busca.dart';
import 'estudo.dart';
import 'introducao.dart';
import 'leitor.dart';
import 'marcacoes.dart';
import 'seletor.dart';

/// Tela principal: o leitor e, ao tocar num versículo, o painel de estudo.
///
/// Em tela larga (PC, tablet deitado) o painel fica fixo à direita, como numa
/// Bíblia de estudo aberta com as notas ao lado; no celular ele sobe por baixo.
class TelaInicio extends StatefulWidget {
  const TelaInicio({super.key});

  @override
  State<TelaInicio> createState() => _TelaInicioState();
}

class _TelaInicioState extends State<TelaInicio> {
  late Posicao _pos = Ajustes.instancia.ultimaPosicao;
  List<Versao> _versoes = const [];
  Versao? _versao;
  int? _selecionado;

  /// Versículo para onde rolar ao abrir o capítulo.
  int? _rolarPara;

  static const larguraDividida = 900.0;

  @override
  void initState() {
    super.initState();
    _carregarVersoes();
    // Checagem silenciosa: só aparece algo se houver versão nova.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) FluxoAtualizacao.verificar(context);
    });
  }

  Future<void> _carregarVersoes() async {
    final v = await Biblia.instancia.versoes();
    final escolhida = Ajustes.instancia.versao;
    setState(() {
      _versoes = v;
      _versao = v.firstWhere((x) => x.id == escolhida, orElse: () => v.first);
    });
  }

  void _ir(Posicao p, {bool abrirEstudo = false}) {
    setState(() {
      _pos = Posicao(p.livro, p.capitulo);
      _selecionado = p.versiculo;
      _rolarPara = p.versiculo;
    });
    Ajustes.instancia.ultimaPosicao = _pos;
    if (abrirEstudo && p.versiculo != null && !_largo(context)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _abrirEstudoCelular(p.versiculo!);
      });
    }
  }

  Future<void> _capituloVizinho(int delta) async {
    var livro = _pos.livro;
    var cap = _pos.capitulo + delta;
    if (cap < 1) {
      if (livro == 1) return;
      livro--;
      cap = Referencias.capitulos[livro - 1];
    } else if (cap > Referencias.capitulos[livro - 1]) {
      if (livro == 66) return;
      livro++;
      cap = 1;
    }
    _ir(Posicao(livro, cap));
  }

  bool _largo(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= larguraDividida;

  void _selecionar(int versiculo) {
    setState(() => _selecionado = versiculo);
    if (!_largo(context)) _abrirEstudoCelular(versiculo);
  }

  Future<void> _abrirEstudoCelular(int versiculo) async {
    final versao = _versao;
    if (versao == null) return;
    final destino = await showModalBottomSheet<Posicao>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 1,
        builder: (c, rolagem) => PainelEstudo(
          posicao: Posicao(_pos.livro, _pos.capitulo, versiculo),
          versao: versao,
          rolagem: rolagem,
          aoIr: (p) => Navigator.pop(c, p),
        ),
      ),
    );
    if (destino != null) _ir(destino, abrirEstudo: true);
  }

  Future<void> _escolherPassagem() async {
    final p = await Navigator.push<Posicao>(
      context,
      MaterialPageRoute(builder: (_) => TelaSeletor(atual: _pos)),
    );
    if (p != null) _ir(p, abrirEstudo: p.versiculo != null);
  }

  Future<void> _escolherVersao() async {
    final v = await showModalBottomSheet<Versao>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final v in _versoes)
              ListTile(
                leading: SizedBox(
                  width: 72,
                  child: Text(
                    v.sigla,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                title: Text(v.nome),
                selected: v.id == _versao?.id,
                onTap: () => Navigator.pop(c, v),
              ),
          ],
        ),
      ),
    );
    if (v != null) {
      setState(() => _versao = v);
      Ajustes.instancia.versao = v.id;
    }
  }

  Future<void> _abrir(Widget tela) async {
    final p = await Navigator.push<Posicao>(
      context,
      MaterialPageRoute(builder: (_) => tela),
    );
    if (p != null) _ir(p, abrirEstudo: p.versiculo != null);
  }

  @override
  Widget build(BuildContext context) {
    final versao = _versao;
    final largo = _largo(context);
    final titulo = '${Referencias.nome(_pos.livro)} ${_pos.capitulo}';
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: _escolherPassagem,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text(titulo, overflow: TextOverflow.ellipsis)),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        ),
        actions: [
          if (versao != null)
            TextButton(onPressed: _escolherVersao, child: Text(versao.sigla)),
          IconButton(
            tooltip: 'Introdução ao livro',
            icon: const Icon(Icons.info_outline),
            onPressed: () => _abrir(TelaIntroducao(livro: _pos.livro)),
          ),
          IconButton(
            tooltip: 'Buscar',
            icon: const Icon(Icons.search),
            onPressed: versao == null
                ? null
                : () => _abrir(TelaBusca(versao: versao)),
          ),
          PopupMenuButton<String>(
            onSelected: (op) => switch (op) {
              'biblioteca' => _abrir(const TelaBiblioteca()),
              'marcacoes' => _abrir(const TelaMarcacoes()),
              'ajustes' => _abrir(const TelaAjustes()),
              _ => null,
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'biblioteca',
                child: ListTile(
                  leading: Icon(Icons.local_library_outlined),
                  title: Text('Biblioteca Ellen G. White'),
                ),
              ),
              PopupMenuItem(
                value: 'marcacoes',
                child: ListTile(
                  leading: Icon(Icons.bookmark_outline),
                  title: Text('Marcações e anotações'),
                ),
              ),
              PopupMenuItem(
                value: 'ajustes',
                child: ListTile(
                  leading: Icon(Icons.settings_outlined),
                  title: Text('Ajustes'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: versao == null
          ? const Center(child: CircularProgressIndicator())
          : Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Leitor(
                    key: ValueKey(
                      '${_pos.livro}:${_pos.capitulo}:${versao.id}',
                    ),
                    posicao: _pos,
                    versao: versao,
                    selecionado: _selecionado,
                    rolarPara: _rolarPara,
                    aoSelecionar: _selecionar,
                    aoMudarCapitulo: _capituloVizinho,
                    aoIr: (p) => _ir(p, abrirEstudo: true),
                  ),
                ),
                if (largo) ...[
                  const VerticalDivider(width: 1),
                  Expanded(
                    flex: 2,
                    child: _selecionado == null
                        ? const _PainelVazio()
                        : PainelEstudo(
                            key: ValueKey(
                              '${_pos.livro}:${_pos.capitulo}:$_selecionado',
                            ),
                            posicao: Posicao(
                              _pos.livro,
                              _pos.capitulo,
                              _selecionado,
                            ),
                            versao: versao,
                            aoIr: (p) => _ir(p),
                          ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _PainelVazio extends StatelessWidget {
  const _PainelVazio();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app_outlined, size: 48, color: t.hintColor),
            const SizedBox(height: 12),
            Text(
              'Toque num versículo para ver o que Ellen G. White escreveu '
              'sobre ele, as referências cruzadas e as outras traduções.',
              textAlign: TextAlign.center,
              style: t.textTheme.bodyMedium?.copyWith(color: t.hintColor),
            ),
          ],
        ),
      ),
    );
  }
}
