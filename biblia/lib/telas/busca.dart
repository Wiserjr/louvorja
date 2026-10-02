import 'dart:async';

import 'package:flutter/material.dart';

import '../dados/biblia.dart';
import '../dados/modelos.dart';
import '../dados/referencias.dart';

/// Busca: vai direto a uma referência ("jo 3:16", "Salmo 23") ou procura
/// palavras no texto da tradução em uso.
class TelaBusca extends StatefulWidget {
  const TelaBusca({super.key, required this.versao});
  final Versao versao;

  @override
  State<TelaBusca> createState() => _TelaBuscaState();
}

class _TelaBuscaState extends State<TelaBusca> {
  final _ctrl = TextEditingController();
  Timer? _espera;
  String _consulta = '';
  int? _testamento;
  Future<List<(int, int, int, String)>>? _resultados;

  @override
  void dispose() {
    _espera?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _mudou(String texto) {
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() {
        _consulta = texto.trim();
        _resultados = _consulta.length < 3
            ? null
            : Biblia.instancia.buscar(
                widget.versao.id,
                _consulta,
                testamento: _testamento,
              );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final ref = Referencias.interpretar(_consulta);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Referência ou palavras (${widget.versao.sigla})',
            border: InputBorder.none,
          ),
          onChanged: _mudou,
          onSubmitted: (texto) {
            final r = Referencias.interpretar(texto);
            if (r != null) Navigator.pop(context, r);
          },
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                for (final (v, rotulo) in const [
                  (null, 'Bíblia toda'),
                  (1, 'Antigo'),
                  (2, 'Novo'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(rotulo),
                      selected: _testamento == v,
                      onSelected: (_) {
                        _testamento = v;
                        _mudou(_ctrl.text);
                      },
                    ),
                  ),
              ],
            ),
          ),
          if (ref != null)
            ListTile(
              leading: const Icon(Icons.arrow_forward),
              title: Text(
                'Ir para ${Referencias.nome(ref.livro)} ${ref.capitulo}'
                '${ref.versiculo != null ? ':${ref.versiculo}' : ''}',
              ),
              onTap: () => Navigator.pop(context, ref),
            ),
          const Divider(height: 1),
          Expanded(
            child: _resultados == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Digite uma referência (ex.: "jo 3:16", "Salmo 23") '
                        'ou palavras do texto (ex.: "amor próximo").',
                        textAlign: TextAlign.center,
                        style: t.textTheme.bodyMedium?.copyWith(
                          color: t.hintColor,
                        ),
                      ),
                    ),
                  )
                : FutureBuilder<List<(int, int, int, String)>>(
                    future: _resultados,
                    builder: (context, snap) {
                      final lista = snap.data;
                      if (lista == null) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (lista.isEmpty) {
                        return const Center(child: Text('Nada encontrado.'));
                      }
                      final palavras = _consulta
                          .split(RegExp(r'\s+'))
                          .where((p) => p.length > 1)
                          .toList();
                      return ListView.separated(
                        itemCount: lista.length + 1,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          if (i == lista.length) {
                            return Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                lista.length >= 300
                                    ? 'Mostrando os 300 primeiros. Refine a '
                                          'busca com mais palavras.'
                                    : '${lista.length} versículo(s).',
                                style: t.textTheme.bodySmall,
                              ),
                            );
                          }
                          final (l, c, v, texto) = lista[i];
                          return ListTile(
                            title: Text(
                              '${Referencias.nome(l)} $c:$v',
                              style: t.textTheme.labelLarge?.copyWith(
                                color: t.colorScheme.primary,
                              ),
                            ),
                            subtitle: Text.rich(
                              TextSpan(
                                children: destacar(
                                  textoPuro(texto),
                                  palavras,
                                  TextStyle(
                                    backgroundColor:
                                        t.colorScheme.tertiaryContainer,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            onTap: () =>
                                Navigator.pop(context, Posicao(l, c, v)),
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

/// Spans com as [palavras] destacadas (sem diferença de maiúsculas e acentos).
List<TextSpan> destacar(String texto, List<String> palavras, TextStyle estilo) {
  if (palavras.isEmpty) return [TextSpan(text: texto)];
  final base = Referencias.semAcento(texto).toLowerCase();
  final marcas = List<bool>.filled(texto.length, false);
  for (final p in palavras) {
    final alvo = Referencias.semAcento(p).toLowerCase();
    var i = base.indexOf(alvo);
    while (i >= 0) {
      for (var k = i; k < i + alvo.length && k < marcas.length; k++) {
        marcas[k] = true;
      }
      i = base.indexOf(alvo, i + alvo.length);
    }
  }
  final spans = <TextSpan>[];
  var ini = 0;
  for (var i = 1; i <= texto.length; i++) {
    if (i == texto.length || marcas[i] != marcas[ini]) {
      spans.add(
        TextSpan(
          text: texto.substring(ini, i),
          style: marcas[ini] ? estilo : null,
        ),
      );
      ini = i;
    }
  }
  return spans;
}
