import 'package:flutter/material.dart';

import '../dados/ajustes.dart';
import '../dados/biblia.dart';
import '../dados/modelos.dart';
import '../dados/referencias.dart';
import '../dados/temas.dart';
import 'cartao_trecho.dart';
import 'navegacao.dart';
import 'tema.dart';
import 'texto_biblico.dart';

/// Índice temático e estudos bíblicos.
class TelaTemas extends StatefulWidget {
  const TelaTemas({super.key, required this.versao, this.abaInicial = 0});
  final Versao versao;
  final int abaInicial;

  @override
  State<TelaTemas> createState() => _TelaTemasState();
}

class _TelaTemasState extends State<TelaTemas> {
  late final Future<List<Tema>> _temas = Temas.instancia.temas();
  late final Future<List<EstudoBiblico>> _estudos = Temas.instancia.estudos();
  String _filtro = '';

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: widget.abaInicial,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Temas e estudos'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Índice temático'),
              Tab(text: 'Estudos bíblicos'),
            ],
          ),
        ),
        body: TabBarView(children: [_indice(context), _listaEstudos(context)]),
      ),
    );
  }

  Widget _indice(BuildContext context) {
    final t = Theme.of(context);
    return FutureBuilder<List<Tema>>(
      future: _temas,
      builder: (context, snap) {
        final temas = snap.data;
        if (temas == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final f = Referencias.semAcento(_filtro.toLowerCase());
        final filtrados = [
          for (final x in temas)
            if (f.isEmpty ||
                Referencias.semAcento(
                  '${x.titulo} ${x.resumo ?? ''} ${x.categoria}'.toLowerCase(),
                ).contains(f))
              x,
        ];
        final categorias = <String, List<Tema>>{};
        for (final x in filtrados) {
          categorias.putIfAbsent(x.categoria, () => []).add(x);
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Procurar tema (ex.: oração, sábado, ansiedade)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (s) => setState(() => _filtro = s.trim()),
            ),
            for (final MapEntry(key: cat, value: lista)
                in categorias.entries) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 18, 4, 4),
                child: Text(
                  cat,
                  style: t.textTheme.titleSmall?.copyWith(
                    color: t.colorScheme.primary,
                  ),
                ),
              ),
              for (final x in lista)
                Card(
                  child: ListTile(
                    title: Text(x.titulo),
                    subtitle: x.resumo == null
                        ? null
                        : Text(
                            x.resumo!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => abrirTema(context, x, widget.versao),
                  ),
                ),
            ],
            if (filtrados.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nenhum tema com essa palavra. Para procurar no texto '
                  'bíblico, use a busca da tela principal.',
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _listaEstudos(BuildContext context) {
    final t = Theme.of(context);
    return FutureBuilder<List<EstudoBiblico>>(
      future: _estudos,
      builder: (context, snap) {
        final estudos = snap.data;
        if (estudos == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            Text(
              'Estudos em forma de perguntas e respostas, com a resposta na '
              'própria Bíblia — para estudar sozinho ou dar um estudo bíblico.',
              style: t.textTheme.bodySmall?.copyWith(color: t.hintColor),
            ),
            const SizedBox(height: 8),
            for (final e in estudos)
              Card(
                child: ListTile(
                  title: Text(e.titulo),
                  subtitle: e.introducao == null ? null : Text(e.introducao!),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          TelaEstudoBiblico(estudo: e, versao: widget.versao),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

Future<void> abrirTema(BuildContext context, Tema tema, Versao versao) =>
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TelaTema(tema: tema, versao: versao),
      ),
    );

/// Um tema: resumo, os versículos com o texto, e os capítulos de Ellen G.
/// White que mais os citam.
class TelaTema extends StatefulWidget {
  const TelaTema({super.key, required this.tema, required this.versao});
  final Tema tema;
  final Versao versao;

  @override
  State<TelaTema> createState() => _TelaTemaState();
}

class _TelaTemaState extends State<TelaTema> {
  late final Future<List<Passagem>> _passagens = Temas.instancia.passagens(
    widget.tema.id,
  );
  late final Future<List<LeituraEgw>> _leituras = Temas.instancia.leituras(
    widget.tema.id,
  );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tema = widget.tema;
    return Scaffold(
      appBar: AppBar(title: Text(tema.titulo)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                tema.categoria,
                style: t.textTheme.labelLarge?.copyWith(
                  color: t.colorScheme.primary,
                ),
              ),
              if (tema.resumo != null) ...[
                const SizedBox(height: 6),
                Text(
                  tema.resumo!,
                  style: t.textTheme.bodyLarge?.copyWith(height: 1.5),
                ),
              ],
              const SizedBox(height: 16),
              FutureBuilder<List<Passagem>>(
                future: _passagens,
                builder: (context, snap) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final p in snap.data ?? const <Passagem>[])
                      CartaoPassagem(passagem: p, versao: widget.versao),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FutureBuilder<List<LeituraEgw>>(
                future: _leituras,
                builder: (context, snap) {
                  final lista = snap.data ?? const <LeituraEgw>[];
                  if (lista.isEmpty) return const SizedBox.shrink();
                  return Card(
                    color: corEgw(context).withValues(alpha: 0.07),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.menu_book_outlined,
                                color: corEgw(context),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Para ler em Ellen G. White',
                                style: t.textTheme.titleSmall?.copyWith(
                                  color: corEgw(context),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Capítulos que citam mais versículos deste tema.',
                            style: t.textTheme.bodySmall,
                          ),
                          for (final l in lista)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: Text(
                                '${l.obra.titulo}, ${tituloCurto(l.capitulo)}',
                              ),
                              subtitle: Text(
                                'cita ${l.versiculos} versículos do tema',
                              ),
                              trailing: const Icon(Icons.open_in_new, size: 18),
                              onTap: () => abrirObra(context, l.obra, l.pagina),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Uma passagem com o texto, tocável para abrir no leitor.
class CartaoPassagem extends StatefulWidget {
  const CartaoPassagem({
    super.key,
    required this.passagem,
    required this.versao,
    this.oculto = false,
  });
  final Passagem passagem;
  final Versao versao;

  /// Esconde o texto até a pessoa tocar (modo de estudo).
  final bool oculto;

  @override
  State<CartaoPassagem> createState() => _CartaoPassagemState();
}

class _CartaoPassagemState extends State<CartaoPassagem> {
  late final Future<List<(int, int, String)>> _texto = Biblia.instancia
      .intervalo(
        widget.versao.id,
        widget.passagem.livro,
        widget.passagem.ini,
        widget.passagem.fim,
        limite: 20,
      );
  late bool _oculto = widget.oculto;

  @override
  Widget build(BuildContext context) {
    final p = widget.passagem;
    final t = Theme.of(context);
    final ref = Referencias.formatar(p.livro, p.ini, p.fim);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => irParaVersiculo(context, p.posicao),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      ref,
                      style: t.textTheme.labelLarge?.copyWith(
                        color: t.colorScheme.primary,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 18, color: t.hintColor),
                ],
              ),
              const SizedBox(height: 4),
              if (_oculto)
                TextButton.icon(
                  onPressed: () => setState(() => _oculto = false),
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('Mostrar a resposta'),
                )
              else
                FutureBuilder<List<(int, int, String)>>(
                  future: _texto,
                  builder: (context, snap) {
                    final linhas = snap.data ?? const [];
                    final base = t.textTheme.bodyMedium!.copyWith(height: 1.5);
                    return Text.rich(
                      TextSpan(
                        children: [
                          for (final (_, v, texto) in linhas) ...[
                            if (linhas.length > 1)
                              TextSpan(
                                text: '$v ',
                                style: base.copyWith(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: t.colorScheme.primary,
                                ),
                              ),
                            ...spansDoTexto(
                              '$texto ',
                              estilo: base,
                              corJesus: corJesus(context),
                              vermelho: Ajustes.instancia.letrasVermelhas,
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Estudo bíblico: perguntas com a resposta escondida até a pessoa tocar.
class TelaEstudoBiblico extends StatefulWidget {
  const TelaEstudoBiblico({
    super.key,
    required this.estudo,
    required this.versao,
  });
  final EstudoBiblico estudo;
  final Versao versao;

  @override
  State<TelaEstudoBiblico> createState() => _TelaEstudoBiblicoState();
}

class _TelaEstudoBiblicoState extends State<TelaEstudoBiblico> {
  late final Future<List<Pergunta>> _perguntas = Temas.instancia.perguntas(
    widget.estudo.id,
  );
  bool _respostasVisiveis = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.estudo.titulo),
        actions: [
          IconButton(
            tooltip: _respostasVisiveis
                ? 'Esconder as respostas'
                : 'Mostrar todas as respostas',
            icon: Icon(
              _respostasVisiveis
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
            onPressed: () =>
                setState(() => _respostasVisiveis = !_respostasVisiveis),
          ),
        ],
      ),
      body: FutureBuilder<List<Pergunta>>(
        future: _perguntas,
        builder: (context, snap) {
          final lista = snap.data;
          if (lista == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: lista.length + 1,
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return widget.estudo.introducao == null
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              widget.estudo.introducao!,
                              style: t.textTheme.bodyLarge,
                            ),
                          );
                  }
                  final q = lista[i - 1];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('$i. ${q.texto}', style: t.textTheme.titleSmall),
                        const SizedBox(height: 4),
                        CartaoPassagem(
                          key: ValueKey('$i:$_respostasVisiveis'),
                          passagem: q.passagem,
                          versao: widget.versao,
                          oculto: !_respostasVisiveis,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
