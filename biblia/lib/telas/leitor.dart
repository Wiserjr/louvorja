import 'package:flutter/material.dart';

import '../dados/ajustes.dart';
import '../dados/biblia.dart';
import '../dados/estudo.dart';
import '../dados/modelos.dart';
import '../dados/referencias.dart';
import 'acoes_versiculo.dart';
import 'cartao_trecho.dart';
import 'tema.dart';
import 'texto_biblico.dart';

/// Um capítulo da Bíblia.
///
/// Ao lado de cada versículo, discretos: quantos trechos de Ellen G. White e
/// dos pioneiros o citam, e se ele cita o Antigo Testamento (ou é citado no
/// Novo) ou tem passagem paralela. No topo, os capítulos de Ellen G. White que
/// narram esta passagem.
class Leitor extends StatefulWidget {
  const Leitor({
    super.key,
    required this.posicao,
    required this.versao,
    required this.selecionado,
    required this.rolarPara,
    required this.aoSelecionar,
    required this.aoMudarCapitulo,
    required this.aoIr,
  });

  final Posicao posicao;
  final Versao versao;
  final int? selecionado;
  final int? rolarPara;
  final ValueChanged<int> aoSelecionar;
  final ValueChanged<int> aoMudarCapitulo;
  final ValueChanged<Posicao> aoIr;

  @override
  State<Leitor> createState() => _LeitorState();
}

class _DadosCapitulo {
  _DadosCapitulo(
    this.versiculos,
    this.contagem,
    this.citacoes,
    this.narrativas,
    this.notas,
  );
  final List<Versiculo> versiculos;
  final Map<int, int> contagem;
  final Map<int, int> citacoes;
  final List<Trecho> narrativas;
  final Set<int> notas;
}

class _LeitorState extends State<Leitor> {
  late final Future<_DadosCapitulo> _dados = _carregar();
  final _chaves = <int, GlobalKey>{};
  final _rolagem = ScrollController();

  Future<_DadosCapitulo> _carregar() async {
    final p = widget.posicao;
    final r = await Future.wait([
      Biblia.instancia.capitulo(widget.versao.id, p.livro, p.capitulo),
      Estudo.instancia.contagem(p.livro, p.capitulo),
      Estudo.instancia.citacoesDoCapitulo(p.livro, p.capitulo),
      Estudo.instancia.narrativas(p.livro, p.capitulo),
      Estudo.instancia.versiculosComNota(p.livro, p.capitulo),
    ]);
    final dados = _DadosCapitulo(
      r[0] as List<Versiculo>,
      r[1] as Map<int, int>,
      r[2] as Map<int, int>,
      r[3] as List<Trecho>,
      r[4] as Set<int>,
    );
    final alvo = widget.rolarPara;
    if (alvo != null && alvo > 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _chaves[alvo]?.currentContext;
        if (ctx != null && ctx.mounted) {
          Scrollable.ensureVisible(ctx, alignment: 0.2);
        }
      });
    }
    return dados;
  }

  @override
  void dispose() {
    _rolagem.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Ajustes.instancia,
      builder: (context, _) => FutureBuilder<_DadosCapitulo>(
        future: _dados,
        builder: (context, snap) {
          final d = snap.data;
          if (d == null) {
            return snap.hasError
                ? Center(child: Text('Erro ao abrir o capítulo: ${snap.error}'))
                : const Center(child: CircularProgressIndicator());
          }
          return GestureDetector(
            // Deslizar para os lados troca de capítulo.
            onHorizontalDragEnd: (e) {
              final v = e.primaryVelocity ?? 0;
              if (v.abs() < 600) return;
              widget.aoMudarCapitulo(v < 0 ? 1 : -1);
            },
            child: _conteudo(context, d),
          );
        },
      ),
    );
  }

  Widget _conteudo(BuildContext context, _DadosCapitulo d) {
    final t = Theme.of(context);
    final aj = Ajustes.instancia;
    final p = widget.posicao;
    return SingleChildScrollView(
      controller: _rolagem,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${Referencias.nome(p.livro)} ${p.capitulo}',
                textAlign: TextAlign.center,
                style: t.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.versao.nome,
                textAlign: TextAlign.center,
                style: t.textTheme.bodySmall?.copyWith(color: t.hintColor),
              ),
              if (d.narrativas.isNotEmpty) ...[
                const SizedBox(height: 12),
                _Narrativas(trechos: d.narrativas),
              ],
              const SizedBox(height: 12),
              for (final v in d.versiculos)
                KeyedSubtree(
                  key: _chaves.putIfAbsent(v.numero, GlobalKey.new),
                  child: _LinhaVersiculo(
                    posicao: p,
                    versiculo: v,
                    versao: widget.versao,
                    selecionado: v.numero == widget.selecionado,
                    egw: aj.marcadoresEgw ? (d.contagem[v.numero] ?? 0) : 0,
                    citacao: d.citacoes[v.numero],
                    temNota: d.notas.contains(v.numero),
                    aoTocar: () => widget.aoSelecionar(v.numero),
                  ),
                ),
              const SizedBox(height: 24),
              Row(
                children: [
                  if (p.livro > 1 || p.capitulo > 1)
                    OutlinedButton.icon(
                      onPressed: () => widget.aoMudarCapitulo(-1),
                      icon: const Icon(Icons.chevron_left),
                      label: const Text('Anterior'),
                    ),
                  const Spacer(),
                  if (p.livro < 66 ||
                      p.capitulo < Referencias.capitulos[p.livro - 1])
                    FilledButton.tonalIcon(
                      onPressed: () => widget.aoMudarCapitulo(1),
                      icon: const Icon(Icons.chevron_right),
                      label: const Text('Próximo'),
                      iconAlignment: IconAlignment.end,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Narrado em: O Desejado de Todas as Nações — cap. 12, A tentação".
class _Narrativas extends StatelessWidget {
  const _Narrativas({required this.trechos});
  final List<Trecho> trechos;

  @override
  Widget build(BuildContext context) {
    final cor = corEgw(context);
    final t = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_stories_outlined, size: 18, color: cor),
                const SizedBox(width: 6),
                Text(
                  'Esta passagem é narrada em',
                  style: t.textTheme.labelLarge?.copyWith(color: cor),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tr in trechos.take(8))
                  ActionChip(
                    label: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${tr.obra.sigla}  ',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: cor,
                            ),
                          ),
                          TextSpan(text: tr.capitulo ?? tr.obra.titulo),
                        ],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: () => abrirTrechoCompleto(context, tr),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LinhaVersiculo extends StatelessWidget {
  const _LinhaVersiculo({
    required this.posicao,
    required this.versiculo,
    required this.versao,
    required this.selecionado,
    required this.egw,
    required this.citacao,
    required this.temNota,
    required this.aoTocar,
  });

  final Posicao posicao;
  final Versiculo versiculo;
  final Versao versao;
  final bool selecionado;
  final int egw;
  final int? citacao;
  final bool temNota;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final aj = Ajustes.instancia;
    final tam = aj.tamanhoLetra;
    final base = t.textTheme.bodyLarge!.copyWith(fontSize: tam, height: 1.6);
    final cor = aj.marcacao(posicao.livro, posicao.capitulo, versiculo.numero);
    final anotado =
        aj.anotacao(posicao.livro, posicao.capitulo, versiculo.numero) != null;

    final indicadores = <InlineSpan>[];
    void indicador(IconData icone, Color c, String? texto, String dica) {
      indicadores.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Tooltip(
            message: dica,
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icone, size: tam * 0.7, color: c),
                  if (texto != null)
                    Text(
                      texto,
                      style: TextStyle(
                        fontSize: tam * 0.6,
                        color: c,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (egw > 0) {
      indicador(
        Icons.menu_book_outlined,
        corEgw(context),
        '$egw',
        '$egw trecho(s) de Ellen G. White e pioneiros',
      );
    }
    if (citacao != null) {
      indicador(
        citacao == 3 ? Icons.compare_arrows : Icons.format_quote,
        t.colorScheme.tertiary,
        null,
        citacao == 3
            ? 'Tem passagem paralela'
            : posicao.livro >= 40
            ? 'Cita o Antigo Testamento'
            : 'Citado no Novo Testamento',
      );
    }
    if (temNota) {
      indicador(
        Icons.sticky_note_2_outlined,
        t.colorScheme.primary,
        null,
        'Nota de estudo',
      );
    }
    if (anotado) {
      indicador(Icons.edit_note, t.colorScheme.secondary, null, 'Sua anotação');
    }

    return InkWell(
      onTap: aoTocar,
      onLongPress: () => mostrarAcoesVersiculo(
        context,
        Posicao(posicao.livro, posicao.capitulo, versiculo.numero),
        versiculo.texto,
        versao,
      ),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        decoration: BoxDecoration(
          color: cor != null ? coresMarcacao[cor % coresMarcacao.length] : null,
          borderRadius: BorderRadius.circular(6),
          border: selecionado
              ? Border.all(color: t.colorScheme.primary, width: 1.5)
              : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        margin: const EdgeInsets.symmetric(vertical: 1),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '${versiculo.numero} ',
                style: base.copyWith(
                  fontSize: tam * 0.65,
                  fontWeight: FontWeight.bold,
                  color: t.colorScheme.primary,
                  fontFeatures: const [FontFeature.superscripts()],
                ),
              ),
              ...spansDoTexto(
                versiculo.texto,
                estilo: base,
                corJesus: corJesus(context),
                vermelho: aj.letrasVermelhas,
              ),
              ...indicadores,
            ],
          ),
        ),
      ),
    );
  }
}
