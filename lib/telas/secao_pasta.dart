import 'package:flutter/material.dart';

import '../dados/midia.dart';

/// A pasta de músicas copiada para o aparelho: escolher, varrer e dizer quanto
/// do catálogo ela cobre.
///
/// Compartilhada pelos Ajustes dos dois apps. No Hinários ela é o caminho de
/// quem já tem os hinos no celular — a pasta do LouvorJA copiada do PC — e não
/// quer baixar de novo nada do que já tem.
class SecaoPastaMusicas extends StatefulWidget {
  const SecaoPastaMusicas({
    super.key,
    this.aoMudarPasta,
    this.itens = 'faixas',
    this.masculino = false,
    this.contarPlayback = false,
  });

  final Future<void> Function()? aoMudarPasta;

  /// Como chamar o que a pasta cobre: "faixas" no Louvor JA, "hinos" no
  /// Hinários. [masculino] concorda o "encontrados/encontradas".
  final String itens;
  final bool masculino;

  /// Também mede os playbacks. No Hinários eles contam: é com eles que a
  /// congregação canta.
  final bool contarPlayback;

  @override
  State<SecaoPastaMusicas> createState() => _SecaoPastaMusicasState();
}

class _SecaoPastaMusicasState extends State<SecaoPastaMusicas> {
  String? _pasta;
  int _indexados = 0;
  bool _indexando = false;
  ({int encontradas, int total})? _cobertura;
  ({int encontradas, int total})? _coberturaPlayback;

  @override
  void initState() {
    super.initState();
    Midia.instancia.raiz.then((v) {
      if (mounted) setState(() => _pasta = v);
    });
    _medirCobertura();
  }

  Future<void> _medirCobertura() async {
    if (await Midia.instancia.raiz == null) return;
    final c = await Midia.instancia.cobertura();
    final pb = widget.contarPlayback
        ? await Midia.instancia.cobertura(playback: true)
        : null;
    if (mounted) {
      setState(() {
        _cobertura = c;
        _coberturaPlayback = pb;
      });
    }
  }

  Future<void> _escolher() async {
    final ok = await Midia.instancia.escolherPasta();
    if (!ok || !mounted) return;

    setState(() {
      _pasta = null;
      _indexando = true;
      _indexados = 0;
    });
    Midia.instancia.raiz.then(
      (v) => mounted ? setState(() => _pasta = v) : null,
    );
    await _varrer();
  }

  /// Refaz a varredura da mesma pasta.
  ///
  /// Necessário depois de copiar mais álbuns: o índice é um retrato do momento
  /// da escolha, não um observador do sistema de arquivos.
  Future<void> _reindexar() async {
    setState(() {
      _indexando = true;
      _indexados = 0;
    });
    await _varrer();
  }

  Future<void> _varrer() async {
    final total = await Midia.instancia.indexar(
      aoProgredir: (n) => mounted ? setState(() => _indexados = n) : null,
    );
    if (mounted) {
      setState(() {
        _indexando = false;
        _indexados = total;
      });
    }
    await _medirCobertura();
    await widget.aoMudarPasta?.call();
  }

  @override
  Widget build(BuildContext context) {
    final c = _cobertura;
    final pb = _coberturaPlayback;
    final achados = widget.masculino ? 'encontrados' : 'encontradas';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: const Text('Pasta das músicas'),
          subtitle: Text(
            _pasta == null
                ? 'Nenhuma pasta escolhida'
                : Uri.decodeFull(_pasta!).split('/').last,
          ),
          trailing: FilledButton.tonal(
            onPressed: _indexando ? null : _escolher,
            child: Text(_pasta == null ? 'Escolher' : 'Trocar'),
          ),
        ),
        if (c != null && !_indexando)
          ListTile(
            leading: Icon(
              c.encontradas == 0
                  ? Icons.error_outline
                  : c.encontradas < c.total
                  ? Icons.info_outline
                  : Icons.check_circle_outline,
            ),
            title: Text(
              '${c.encontradas} de ${c.total} ${widget.itens} $achados '
              'na pasta',
            ),
            // Quando a conta não fecha, o motivo quase sempre é o nível de
            // pasta escolhido ou uma cópia parcial — dizer isso poupa o
            // usuário de adivinhar.
            subtitle: Text(
              [
                if (pb != null)
                  '${pb.encontradas} de ${pb.total} playbacks $achados.',
                c.encontradas == 0
                    ? 'Confira se apontou a pasta que contém "musics" ou '
                          '"musicas", e refaça a varredura.'
                    : c.encontradas < c.total
                    ? 'O resto pode ser baixado, ou copiado depois para a '
                          'mesma pasta. Refaça a varredura após copiar.'
                    : 'A pasta cobre todo o catálogo.',
              ].join(' '),
            ),
            trailing: TextButton(
              onPressed: _indexando ? null : _reindexar,
              child: const Text('Varrer'),
            ),
          ),
        if (_indexando)
          ListTile(
            leading: const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            title: const Text('Indexando a pasta...'),
            subtitle: Text('$_indexados arquivos'),
          )
        else if (_indexados > 0)
          ListTile(
            leading: const Icon(Icons.check_circle_outline),
            title: Text('$_indexados arquivos indexados'),
          ),
      ],
    );
  }
}
