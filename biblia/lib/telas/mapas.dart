import 'package:flutter/material.dart';

import '../dados/biblia.dart';
import '../dados/mapas.dart';
import '../dados/modelos.dart';
import '../dados/referencias.dart';
import 'mapa_vista.dart';
import 'navegacao.dart';

/// Os mapas temáticos e a busca de lugares.
class TelaMapas extends StatefulWidget {
  const TelaMapas({super.key, required this.versao});
  final Versao versao;

  @override
  State<TelaMapas> createState() => _TelaMapasState();
}

class _TelaMapasState extends State<TelaMapas> {
  late final Future<List<MapaTematico>> _mapas = Mapas.instancia.tematicos();
  final _busca = TextEditingController();
  Future<List<Lugar>>? _achados;

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Mapas')),
      body: FutureBuilder<List<MapaTematico>>(
        future: _mapas,
        builder: (context, snap) {
          final mapas = snap.data;
          if (mapas == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            children: [
              TextField(
                controller: _busca,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Procurar um lugar (ex.: Betel, Éfeso, Jordão)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (s) => setState(() {
                  _achados = s.trim().length < 2
                      ? null
                      : Mapas.instancia.buscar(s.trim());
                }),
              ),
              if (_achados != null)
                FutureBuilder<List<Lugar>>(
                  future: _achados,
                  builder: (context, snap) {
                    final lista = snap.data ?? const <Lugar>[];
                    if (lista.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Nenhum lugar com esse nome.'),
                      );
                    }
                    return Column(
                      children: [
                        for (final l in lista.take(15))
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.place_outlined),
                            title: Text(l.nome),
                            subtitle: Text(
                              '${l.tipoLegivel} · ${l.versiculos} '
                              'versículo(s)',
                            ),
                            onTap: () => abrirLugar(context, l, widget.versao),
                          ),
                      ],
                    );
                  },
                ),
              const SizedBox(height: 8),
              for (final m in mapas)
                Card(
                  child: ListTile(
                    leading: Icon(
                      Icons.map_outlined,
                      color: t.colorScheme.primary,
                    ),
                    title: Text(m.titulo),
                    subtitle: m.periodo == null ? null : Text(m.periodo!),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            TelaMapa(mapa: m, versao: widget.versao),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'Localizações: Bible Geocoding Data, OpenBible.info (CC BY '
                  '4.0). Contornos: Natural Earth. Lugares marcados com '
                  'círculo vazado têm identificação incerta.',
                  style: t.textTheme.bodySmall?.copyWith(color: t.hintColor),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

Future<void> abrirLugar(BuildContext context, Lugar l, Versao versao) =>
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TelaLugar(lugar: l, versao: versao),
      ),
    );

/// Um mapa temático: o mapa em cima, a explicação e os lugares embaixo (ou
/// ao lado, em tela larga).
class TelaMapa extends StatefulWidget {
  const TelaMapa({super.key, required this.mapa, required this.versao});
  final MapaTematico mapa;
  final Versao versao;

  @override
  State<TelaMapa> createState() => _TelaMapaState();
}

class _TelaMapaState extends State<TelaMapa> {
  late final Future<(Geometria, List<Lugar>, List<RotaVista>)> _dados =
      _carregar();

  Future<(Geometria, List<Lugar>, List<RotaVista>)> _carregar() async {
    final m = widget.mapa;
    final g = await Mapas.instancia.geometria();
    final lugares = await Mapas.instancia.lugares(m.lugares);
    final rotas = <RotaVista>[];
    for (var i = 0; i < m.rotas.length; i++) {
      rotas.add(
        RotaVista(
          m.rotas[i].nome,
          await Mapas.instancia.lugares(m.rotas[i].lugares),
          coresRotas[i % coresRotas.length],
        ),
      );
    }
    return (g, lugares, rotas);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.mapa;
    return Scaffold(
      appBar: AppBar(title: Text(m.titulo)),
      body: FutureBuilder(
        future: _dados,
        builder: (context, snap) {
          final d = snap.data;
          if (d == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final (g, lugares, rotas) = d;
          final vista = VistaMapa(
            geometria: g,
            lugares: lugares,
            rotas: rotas,
            destaque: {for (final r in rotas) ...r.lugares.map((l) => l.id)},
            aoTocarLugar: (l) => abrirLugar(context, l, widget.versao),
          );
          final info = _Informacoes(
            mapa: m,
            lugares: lugares,
            rotas: rotas,
            versao: widget.versao,
          );
          return LayoutBuilder(
            builder: (context, r) => r.maxWidth >= 900
                ? Row(
                    children: [
                      Expanded(flex: 3, child: vista),
                      const VerticalDivider(width: 1),
                      Expanded(flex: 2, child: info),
                    ],
                  )
                : Column(
                    children: [
                      SizedBox(height: r.maxHeight * 0.55, child: vista),
                      const Divider(height: 1),
                      Expanded(child: info),
                    ],
                  ),
          );
        },
      ),
    );
  }
}

class _Informacoes extends StatelessWidget {
  const _Informacoes({
    required this.mapa,
    required this.lugares,
    required this.rotas,
    required this.versao,
  });
  final MapaTematico mapa;
  final List<Lugar> lugares;
  final List<RotaVista> rotas;
  final Versao versao;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final ordenados = [...lugares]..sort((a, b) => a.nome.compareTo(b.nome));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (mapa.periodo != null)
          Text(
            mapa.periodo!,
            style: t.textTheme.labelLarge?.copyWith(
              color: t.colorScheme.primary,
            ),
          ),
        if (mapa.descricao != null) ...[
          const SizedBox(height: 6),
          Text(
            mapa.descricao!,
            style: t.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
        ],
        if (rotas.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final r in rotas)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Container(width: 22, height: 4, color: r.cor),
                  const SizedBox(width: 8),
                  Expanded(child: Text(r.nome, style: t.textTheme.bodySmall)),
                ],
              ),
            ),
        ],
        if (mapa.referencias.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Leia', style: t.textTheme.titleSmall),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final ref in mapa.referencias)
                ActionChip(
                  label: Text(ref),
                  onPressed: () {
                    final p = Referencias.interpretar(ref);
                    if (p != null) irParaVersiculo(context, p);
                  },
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Text('Lugares', style: t.textTheme.titleSmall),
        for (final l in ordenados)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              l.incerto ? Icons.radio_button_unchecked : Icons.place,
              size: 20,
            ),
            title: Text(l.nome),
            subtitle: Text(
              '${l.tipoLegivel}${l.incerto ? ' · localização incerta' : ''}',
            ),
            onTap: () => abrirLugar(context, l, versao),
          ),
      ],
    );
  }
}

/// Um lugar: onde fica e todos os versículos que o citam.
class TelaLugar extends StatefulWidget {
  const TelaLugar({super.key, required this.lugar, required this.versao});
  final Lugar lugar;
  final Versao versao;

  @override
  State<TelaLugar> createState() => _TelaLugarState();
}

class _TelaLugarState extends State<TelaLugar> {
  late final Future<Geometria> _geo = Mapas.instancia.geometria();
  late final Future<List<(int, int, int)>> _versos = Mapas.instancia.versiculos(
    widget.lugar.id,
  );

  @override
  Widget build(BuildContext context) {
    final l = widget.lugar;
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.nome)),
      body: Column(
        children: [
          SizedBox(
            height: 260,
            child: FutureBuilder<Geometria>(
              future: _geo,
              builder: (context, snap) => snap.data == null
                  ? const SizedBox.shrink()
                  : VistaMapa(
                      geometria: snap.data!,
                      lugares: [l],
                      destaque: {l.id},
                      margem: 2,
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${l.tipoLegivel[0].toUpperCase()}${l.tipoLegivel.substring(1)}'
                    ' · citado em ${l.versiculos} versículo(s)',
                    style: t.textTheme.bodyMedium,
                  ),
                ),
                if (l.incerto)
                  Tooltip(
                    message:
                        'Os estudiosos não têm certeza de onde ficava este '
                        'lugar; o ponto é a identificação mais provável.',
                    child: Chip(
                      label: const Text('localização incerta'),
                      visualDensity: VisualDensity.compact,
                      labelStyle: t.textTheme.labelSmall,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<List<(int, int, int)>>(
              future: _versos,
              builder: (context, snap) {
                final lista = snap.data;
                if (lista == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                return ListView.builder(
                  itemCount: lista.length,
                  itemBuilder: (context, i) {
                    final (lv, c, v) = lista[i];
                    return _ItemVersiculo(
                      posicao: Posicao(lv, c, v),
                      versao: widget.versao,
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

/// Referência com o texto do versículo, carregado sob demanda.
class _ItemVersiculo extends StatefulWidget {
  const _ItemVersiculo({required this.posicao, required this.versao});
  final Posicao posicao;
  final Versao versao;

  @override
  State<_ItemVersiculo> createState() => _ItemVersiculoState();
}

class _ItemVersiculoState extends State<_ItemVersiculo> {
  late final Future<List<(int, int, String)>> _texto = Biblia.instancia
      .intervalo(
        widget.versao.id,
        widget.posicao.livro,
        chave(widget.posicao.capitulo, widget.posicao.versiculo!),
        chave(widget.posicao.capitulo, widget.posicao.versiculo!),
      );

  @override
  Widget build(BuildContext context) {
    final p = widget.posicao;
    final t = Theme.of(context);
    return ListTile(
      title: Text(
        '${Referencias.nome(p.livro)} ${p.capitulo}:${p.versiculo}',
        style: t.textTheme.labelLarge?.copyWith(color: t.colorScheme.primary),
      ),
      subtitle: FutureBuilder<List<(int, int, String)>>(
        future: _texto,
        builder: (context, snap) => Text(
          snap.data?.isNotEmpty == true ? textoPuro(snap.data!.first.$3) : '',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      onTap: () => irParaVersiculo(context, p),
    );
  }
}
