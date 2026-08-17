import 'package:flutter/material.dart';

import '../dados/compartilhar.dart';
import '../dados/leitor_voz.dart';
import '../dados/modelos.dart';
import '../dados/repositorio.dart';
import 'cartao_versiculo.dart';
import 'tela_voz.dart';

/// Leitor bíblico: navegação por livro e capítulo, busca no texto, leitura em
/// voz alta e compartilhamento.
///
/// O tamanho da letra e a voz não são enfeites — são o mesmo requisito de
/// acessibilidade visto de dois ângulos. Quem tem dificuldade de ler no celular
/// ora aumenta a fonte, ora prefere ouvir.
class TelaBiblia extends StatefulWidget {
  const TelaBiblia({super.key});

  @override
  State<TelaBiblia> createState() => _TelaBibliaState();
}

class _TelaBibliaState extends State<TelaBiblia> {
  final _repo = const Repositorio();
  final _leitor = LeitorVoz.instancia;

  List<Map<String, Object?>> _versoes = const [];
  List<Map<String, Object?>> _livros = const [];
  int? _idVersao;
  int? _idLivro;
  int _capitulo = 1;
  int _totalCapitulos = 0;

  double _fonte = 17;
  bool _temVoz = false;

  /// Versículos marcados para compartilhar. Vazio = ninguém selecionado.
  final _selecionados = <int>{};

  final _buscaCtrl = TextEditingController();
  String _busca = '';
  Future<List<Versiculo>>? _resultados;

  List<Versiculo> _doCapitulo = const [];

  @override
  void initState() {
    super.initState();
    _carregarBase();
    _leitor.temVozPortuguesa().then((v) {
      if (mounted) setState(() => _temVoz = v);
    });
  }

  @override
  void dispose() {
    _leitor.parar();
    _buscaCtrl.dispose();
    super.dispose();
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

  Future<void> _abrirLivro(int idLivro, {int capitulo = 1}) async {
    await _leitor.parar();
    final total = await _repo.totalCapitulos(idLivro, _idVersao!);
    if (!mounted) return;
    setState(() {
      _idLivro = idLivro;
      _capitulo = capitulo;
      _totalCapitulos = total;
      _selecionados.clear();
      _busca = '';
      _buscaCtrl.clear();
      _resultados = null;
    });
  }

  String? get _sigla {
    final v = _versoes.firstWhere(
      (x) => x['id'] == _idVersao,
      orElse: () => const {},
    );
    return v['sigla'] as String?;
  }

  void _buscar(String termo) {
    setState(() {
      _busca = termo.trim();
      _resultados = _busca.length < 3
          ? null
          : _repo.buscarNaBiblia(_busca, _idVersao!);
    });
  }

  Future<void> _abrirVoz() async {
    await _leitor.parar();
    if (!mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const TelaVoz()));
    final v = await _leitor.temVozPortuguesa();
    if (mounted) setState(() => _temVoz = v);
  }

  Future<void> _alternarLeitura() async {
    if (_leitor.lendo.value) {
      await _leitor.parar();
    } else {
      // Com versículos marcados, começa pelo primeiro deles: quem seleciona
      // uma passagem quer ouvir aquilo, não o capítulo do início.
      final inicio = _selecionados.isEmpty
          ? 0
          : _doCapitulo.indexWhere((v) => _selecionados.contains(v.numero));
      await _leitor.ler(_doCapitulo, inicio: inicio < 0 ? 0 : inicio);
    }
  }

  void _compartilharComoImagem(List<Versiculo> escolhidos) {
    if (escolhidos.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CartaoVersiculo(versiculos: escolhidos, sigla: _sigla),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_versoes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return SafeArea(
      child: Column(
        children: [
          _barraSuperior(),
          Expanded(
            child: _resultados != null
                ? _listaBusca()
                : _idLivro == null
                ? _listaLivros()
                : _leitorCapitulo(),
          ),
          if (_selecionados.isNotEmpty) _barraSelecao(),
        ],
      ),
    );
  }

  Widget _barraSuperior() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
    child: Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<int>(
            initialValue: _idVersao,
            isDense: true,
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
              await _leitor.parar();
              setState(() => _idVersao = v);
              if (_busca.length >= 3) _buscar(_busca);
              if (_idLivro != null) {
                await _abrirLivro(_idLivro!, capitulo: _capitulo);
              }
            },
          ),
        ),
        IconButton(
          tooltip: 'Diminuir a letra',
          onPressed: _fonte <= 13 ? null : () => setState(() => _fonte -= 2),
          icon: const Icon(Icons.text_decrease),
        ),
        IconButton(
          tooltip: 'Aumentar a letra',
          onPressed: _fonte >= 31 ? null : () => setState(() => _fonte += 2),
          icon: const Icon(Icons.text_increase),
        ),
      ],
    ),
  );

  Widget _campoBusca() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
    child: TextField(
      controller: _buscaCtrl,
      decoration: InputDecoration(
        hintText: 'Buscar no texto bíblico',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _busca.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  _buscaCtrl.clear();
                  _buscar('');
                },
              ),
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      onChanged: _buscar,
    ),
  );

  Widget _listaLivros() => Column(
    children: [
      _campoBusca(),
      Expanded(
        child: ListView.builder(
          itemCount: _livros.length,
          itemBuilder: (context, i) {
            final l = _livros[i];
            return ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 14,
                child: Text(
                  '${l['numero']}',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              title: Text(l['nome'] as String),
              subtitle: Text(
                (l['testamento'] as int) == 1
                    ? 'Antigo Testamento'
                    : 'Novo Testamento',
              ),
              onTap: () => _abrirLivro(l['id'] as int),
            );
          },
        ),
      ),
    ],
  );

  Widget _listaBusca() => Column(
    children: [
      _campoBusca(),
      Expanded(
        child: FutureBuilder<List<Versiculo>>(
          future: _resultados,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final achados = snap.data ?? const <Versiculo>[];
            if (achados.isEmpty) {
              return Center(child: Text('Nada encontrado para "$_busca".'));
            }
            return ListView.separated(
              itemCount: achados.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final v = achados[i];
                return ListTile(
                  title: Text(
                    v.referencia,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  subtitle: Text(
                    v.texto,
                    style: TextStyle(fontSize: _fonte - 3),
                  ),
                  trailing: IconButton(
                    tooltip: 'Compartilhar',
                    icon: const Icon(Icons.share_outlined),
                    onPressed: () => _compartilharComoImagem([v]),
                  ),
                  onTap: () {
                    final livro = _livros.firstWhere(
                      (l) => l['nome'] == v.livro,
                      orElse: () => const {},
                    );
                    if (livro.isNotEmpty) {
                      _abrirLivro(livro['id'] as int, capitulo: v.capitulo);
                    }
                  },
                );
              },
            );
          },
        ),
      ),
    ],
  );

  Widget _leitorCapitulo() {
    final livro = _livros.firstWhere((l) => l['id'] == _idLivro);
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () async {
                await _leitor.parar();
                setState(() {
                  _idLivro = null;
                  _selecionados.clear();
                });
              },
              icon: const Icon(Icons.arrow_back),
            ),
            Expanded(
              child: Text(
                '${livro['nome']} $_capitulo',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: _leitor.lendo,
              builder: (context, lendo, _) => IconButton(
                tooltip: lendo ? 'Parar a leitura' : 'Ouvir o capítulo',
                // Toque longo abre a escolha de voz: é lá que se resolve o som
                // ruim, e ninguém procuraria isso nos Ajustes gerais.
                onPressed: _temVoz ? _alternarLeitura : _abrirVoz,
                icon: Icon(
                  lendo
                      ? Icons.stop_circle
                      : _temVoz
                      ? Icons.volume_up
                      : Icons.volume_off,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Voz da leitura',
              onPressed: _abrirVoz,
              icon: const Icon(Icons.record_voice_over_outlined),
            ),
            IconButton(
              onPressed: _capitulo > 1 ? () => _mudarCapitulo(-1) : null,
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              onPressed: _capitulo < _totalCapitulos
                  ? () => _mudarCapitulo(1)
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
              _doCapitulo = snap.data!;
              return ValueListenableBuilder<int?>(
                valueListenable: _leitor.versoAtual,
                builder: (context, lendoIndice, _) => ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: _doCapitulo.length,
                  itemBuilder: (context, i) =>
                      _verso(_doCapitulo[i], i == lendoIndice),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _mudarCapitulo(int delta) async {
    await _leitor.parar();
    setState(() {
      _capitulo += delta;
      _selecionados.clear();
    });
  }

  Widget _verso(Versiculo v, bool sendoLido) {
    final marcado = _selecionados.contains(v.numero);
    final cor = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => setState(() {
        if (marcado) {
          _selecionados.remove(v.numero);
        } else {
          _selecionados.add(v.numero);
        }
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
        decoration: BoxDecoration(
          color: sendoLido
              ? cor.primaryContainer
              : marcado
              ? cor.secondaryContainer
              : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: RichText(
          text: TextSpan(
            style: TextStyle(
              fontSize: _fonte,
              height: 1.5,
              color: cor.onSurface,
            ),
            children: [
              TextSpan(
                text: '${v.numero}  ',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: cor.primary,
                  fontSize: _fonte - 3,
                ),
              ),
              TextSpan(text: v.texto),
            ],
          ),
        ),
      ),
    );
  }

  Widget _barraSelecao() {
    final escolhidos = _doCapitulo
        .where((v) => _selecionados.contains(v.numero))
        .toList();
    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Text('${_selecionados.length} selecionado(s)'),
            const Spacer(),
            TextButton.icon(
              onPressed: () => Compartilhar.instancia.texto(
                Compartilhar.textoDaPassagem(escolhidos, sigla: _sigla),
              ),
              icon: const Icon(Icons.text_fields, size: 18),
              label: const Text('Texto'),
            ),
            const SizedBox(width: 4),
            FilledButton.tonalIcon(
              onPressed: () => _compartilharComoImagem(escolhidos),
              icon: const Icon(Icons.image_outlined, size: 18),
              label: const Text('Imagem'),
            ),
            IconButton(
              tooltip: 'Limpar seleção',
              onPressed: () => setState(_selecionados.clear),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }
}
