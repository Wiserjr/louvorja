import 'package:flutter/material.dart';

import '../dados/modelos.dart';
import '../dados/repositorio.dart';

class TelaBiblia extends StatefulWidget {
  const TelaBiblia({super.key});

  @override
  State<TelaBiblia> createState() => _TelaBibliaState();
}

class _TelaBibliaState extends State<TelaBiblia> {
  final _repo = const Repositorio();

  List<Map<String, Object?>> _versoes = const [];
  List<Map<String, Object?>> _livros = const [];
  int? _idVersao;
  int? _idLivro;
  int _capitulo = 1;
  int _totalCapitulos = 0;

  @override
  void initState() {
    super.initState();
    _carregarBase();
  }

  Future<void> _carregarBase() async {
    final versoes = await _repo.versoesBiblia();
    final livros = await _repo.livrosBiblia();
    if (!mounted) return;
    setState(() {
      _versoes = versoes;
      _livros = livros;
      _idVersao = versoes.isNotEmpty ? versoes.first['id'] as int : null;
    });
  }

  Future<void> _abrirLivro(int idLivro) async {
    final total = await _repo.totalCapitulos(idLivro, _idVersao!);
    if (!mounted) return;
    setState(() {
      _idLivro = idLivro;
      _capitulo = 1;
      _totalCapitulos = total;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_versoes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _idVersao,
                    decoration: const InputDecoration(
                      labelText: 'Versão',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final v in _versoes)
                        DropdownMenuItem(
                          value: v['id'] as int,
                          child: Text(
                            '${v['sigla']} — ${v['nome']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) async {
                      setState(() => _idVersao = v);
                      if (_idLivro != null) await _abrirLivro(_idLivro!);
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _idLivro == null ? _listaLivros() : _leitor()),
        ],
      ),
    );
  }

  Widget _listaLivros() {
    return ListView.builder(
      itemCount: _livros.length,
      itemBuilder: (context, i) {
        final l = _livros[i];
        final antigo = (l['testamento'] as int) == 1;
        return ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 14,
            child: Text('${l['numero']}', style: const TextStyle(fontSize: 11)),
          ),
          title: Text(l['nome'] as String),
          subtitle: Text(antigo ? 'Antigo Testamento' : 'Novo Testamento'),
          onTap: () => _abrirLivro(l['id'] as int),
        );
      },
    );
  }

  Widget _leitor() {
    final livro = _livros.firstWhere((l) => l['id'] == _idLivro);
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => setState(() => _idLivro = null),
              icon: const Icon(Icons.arrow_back),
            ),
            Expanded(
              child: Text(
                '${livro['nome']} $_capitulo',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              onPressed: _capitulo > 1
                  ? () => setState(() => _capitulo--)
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              onPressed: _capitulo < _totalCapitulos
                  ? () => setState(() => _capitulo++)
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Expanded(
          child: FutureBuilder<List<Versiculo>>(
            future: _repo.capitulo(_idLivro!, _capitulo, _idVersao!),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final versiculos = snap.data!;
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: versiculos.length,
                itemBuilder: (context, i) {
                  final v = versiculos[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: RichText(
                      text: TextSpan(
                        style: Theme.of(context).textTheme.bodyLarge,
                        children: [
                          TextSpan(
                            text: '${v.numero}  ',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          TextSpan(text: v.texto),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
