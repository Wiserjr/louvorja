import 'package:flutter/material.dart';

import '../dados/ajustes.dart';
import '../dados/biblia.dart';
import '../dados/modelos.dart';
import '../dados/referencias.dart';
import '../dados/sinotico.dart';
import '../dados/temas.dart';
import 'cartao_trecho.dart';
import 'navegacao.dart';
import 'tema.dart';
import 'texto_biblico.dart';

const _siglas = {40: 'Mt', 41: 'Mc', 42: 'Lc', 43: 'Jo'};

/// "4:1-11" (sem o nome do livro), juntando os trechos de um evangelho.
String refCurta(List<Passagem> ps) => ps
    .map((p) {
      final completa = Referencias.formatar(p.livro, p.ini, p.fim);
      return completa.substring(Referencias.nome(p.livro).length + 1);
    })
    .join('; ');

/// O guia sinótico: os episódios da vida de Jesus em ordem, com a passagem
/// de cada evangelho lado a lado.
class TelaSinotico extends StatefulWidget {
  const TelaSinotico({super.key, required this.versao});
  final Versao versao;

  @override
  State<TelaSinotico> createState() => _TelaSinoticoState();
}

class _TelaSinoticoState extends State<TelaSinotico> {
  late final Future<List<EventoSinotico>> _eventos = Sinotico.instancia
      .eventos();
  String _filtro = '';
  bool _soParalelos = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Guia sinótico dos evangelhos')),
      body: FutureBuilder<List<EventoSinotico>>(
        future: _eventos,
        builder: (context, snap) {
          final todos = snap.data;
          if (todos == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final f = Referencias.semAcento(_filtro.toLowerCase());
          final lista = [
            for (final e in todos)
              if ((!_soParalelos || e.quantosEvangelhos >= 2) &&
                  (f.isEmpty ||
                      Referencias.semAcento(e.titulo.toLowerCase())
                          .contains(f)))
                e,
          ];
          final linhas = <Widget>[];
          String? periodo;
          for (final e in lista) {
            if (e.periodo != periodo) {
              periodo = e.periodo;
              linhas.add(
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
                  child: Text(
                    periodo,
                    style: t.textTheme.titleSmall?.copyWith(
                      color: t.colorScheme.primary,
                    ),
                  ),
                ),
              );
            }
            linhas.add(_LinhaEvento(evento: e, versao: widget.versao));
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Procurar episódio (ex.: tempestade, Zaqueu)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (s) => setState(() => _filtro = s.trim()),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    FilterChip(
                      label: const Text('Só os narrados em mais de um'),
                      selected: _soParalelos,
                      onSelected: (v) => setState(() => _soParalelos = v),
                    ),
                    const Spacer(),
                    Text(
                      '${lista.length} episódios',
                      style: t.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const _Cabecalho(),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: linhas,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final estilo = t.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.bold,
      color: t.colorScheme.primary,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Row(
        children: [
          Expanded(child: Text('Episódio', style: estilo)),
          for (final l in evangelhos)
            SizedBox(
              width: _larguraColuna(context),
              child: Text(
                _siglas[l]!,
                style: estilo,
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}

double _larguraColuna(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= 700 ? 110 : 58;

class _LinhaEvento extends StatelessWidget {
  const _LinhaEvento({required this.evento, required this.versao});
  final EventoSinotico evento;
  final Versao versao;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final largura = _larguraColuna(context);
    return InkWell(
      onTap: () => abrirEvento(context, evento, versao),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(evento.titulo, style: t.textTheme.bodyMedium),
                  if (evento.leituras.isNotEmpty)
                    Text(
                      evento.leituras
                          .map(
                            (l) =>
                                '${l.obra.sigla} ${tituloCurto(l.capitulo).split(' — ').first}',
                          )
                          .join(' · '),
                      style: t.textTheme.labelSmall?.copyWith(
                        color: corEgw(context),
                      ),
                    ),
                ],
              ),
            ),
            for (final l in evangelhos)
              SizedBox(
                width: largura,
                child: Text(
                  evento.passagens[l] == null
                      ? '—'
                      : refCurta(evento.passagens[l]!),
                  textAlign: TextAlign.center,
                  style: t.textTheme.bodySmall?.copyWith(
                    color: evento.passagens[l] == null
                        ? t.hintColor
                        : t.colorScheme.onSurface,
                    fontSize: largura < 100 ? 10.5 : null,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> abrirEvento(
  BuildContext context,
  EventoSinotico e,
  Versao versao,
) => Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => TelaParalelo(evento: e, versao: versao),
  ),
);

/// Um episódio com o texto de cada evangelho lado a lado (em abas no
/// celular) e os capítulos de Ellen G. White que o narram.
class TelaParalelo extends StatelessWidget {
  const TelaParalelo({super.key, required this.evento, required this.versao});
  final EventoSinotico evento;
  final Versao versao;

  @override
  Widget build(BuildContext context) {
    final livros = [
      for (final l in evangelhos)
        if (evento.passagens[l] != null) l,
    ];
    final largo = MediaQuery.sizeOf(context).width >= 900;
    final leituras = evento.leituras.isEmpty
        ? null
        : _Leituras(leituras: evento.leituras);
    if (largo || livros.length == 1) {
      return Scaffold(
        appBar: AppBar(title: Text(evento.titulo)),
        body: Column(
          children: [
            ?leituras,
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < livros.length; i++) ...[
                    if (i > 0) const VerticalDivider(width: 1),
                    Expanded(
                      child: _ColunaEvangelho(
                        passagens: evento.passagens[livros[i]]!,
                        versao: versao,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }
    return DefaultTabController(
      length: livros.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(evento.titulo),
          bottom: TabBar(
            tabs: [
              for (final l in livros)
                Tab(text: '${_siglas[l]} ${refCurta(evento.passagens[l]!)}'),
            ],
            isScrollable: livros.length > 3,
          ),
        ),
        body: Column(
          children: [
            ?leituras,
            Expanded(
              child: TabBarView(
                children: [
                  for (final l in livros)
                    _ColunaEvangelho(
                      passagens: evento.passagens[l]!,
                      versao: versao,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Leituras extends StatelessWidget {
  const _Leituras({required this.leituras});
  final List<LeituraEgw> leituras;

  @override
  Widget build(BuildContext context) {
    final cor = corEgw(context);
    return Container(
      width: double.infinity,
      color: cor.withValues(alpha: 0.07),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        runSpacing: 4,
        children: [
          Icon(Icons.menu_book_outlined, size: 18, color: cor),
          Text(
            'Narrado em',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: cor),
          ),
          for (final l in leituras)
            ActionChip(
              label: Text('${l.obra.sigla}, ${tituloCurto(l.capitulo)}'),
              onPressed: () => abrirObra(context, l.obra, l.pagina),
            ),
        ],
      ),
    );
  }
}

/// O texto de um evangelho no episódio, versículo a versículo.
class _ColunaEvangelho extends StatefulWidget {
  const _ColunaEvangelho({required this.passagens, required this.versao});
  final List<Passagem> passagens;
  final Versao versao;

  @override
  State<_ColunaEvangelho> createState() => _ColunaEvangelhoState();
}

class _ColunaEvangelhoState extends State<_ColunaEvangelho> {
  late final Future<List<(Passagem, List<(int, int, String)>)>> _textos =
      Future.wait([
        for (final p in widget.passagens)
          Biblia.instancia
              .intervalo(widget.versao.id, p.livro, p.ini, p.fim, limite: 400)
              .then((linhas) => (p, linhas)),
      ]);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final aj = Ajustes.instancia;
    return FutureBuilder(
      future: _textos,
      builder: (context, snap) {
        final blocos = snap.data;
        if (blocos == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final base = t.textTheme.bodyLarge!.copyWith(
          fontSize: aj.tamanhoLetra * 0.9,
          height: 1.6,
        );
        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
          children: [
            for (final (p, linhas) in blocos) ...[
              Text(
                Referencias.formatar(p.livro, p.ini, p.fim),
                style: t.textTheme.titleSmall?.copyWith(
                  color: t.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 6),
              for (final (c, v, texto) in linhas)
                InkWell(
                  onTap: () => irParaVersiculo(context, Posicao(p.livro, c, v)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '$v ',
                            style: base.copyWith(
                              fontSize: base.fontSize! * 0.65,
                              fontWeight: FontWeight.bold,
                              color: t.colorScheme.primary,
                            ),
                          ),
                          ...spansDoTexto(
                            texto,
                            estilo: base,
                            corJesus: corJesus(context),
                            vermelho: aj.letrasVermelhas,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 14),
            ],
          ],
        );
      },
    );
  }
}
