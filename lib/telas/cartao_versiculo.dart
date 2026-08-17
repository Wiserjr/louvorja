import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../dados/compartilhar.dart';
import '../dados/fundos.dart';
import '../dados/modelos.dart';

/// Monta e compartilha um cartão com o versículo sobre uma imagem.
///
/// O cartão é um widget de verdade, capturado por `RepaintBoundary` — não um
/// desenho em canvas. Assim o que sai no PNG é exatamente o que a pessoa viu na
/// tela, incluindo quebras de linha e ajuste de fonte.
class CartaoVersiculo extends StatefulWidget {
  const CartaoVersiculo({super.key, required this.versiculos, this.sigla});

  final List<Versiculo> versiculos;
  final String? sigla;

  @override
  State<CartaoVersiculo> createState() => _CartaoVersiculoState();
}

class _CartaoVersiculoState extends State<CartaoVersiculo> {
  final _chave = GlobalKey();
  Fundo? _fundo;
  bool _gerando = false;

  String get _texto => widget.versiculos.map((v) => v.texto.trim()).join(' ');

  String get _referencia {
    final v = widget.versiculos;
    if (v.length == 1) return v.first.referencia;
    return '${v.first.livro} ${v.first.capitulo}:'
        '${v.first.numero}-${v.last.numero}';
  }

  @override
  void initState() {
    super.initState();
    Fundos.instancia.sugerir(_texto).then((f) {
      if (mounted) setState(() => _fundo = f);
    });
  }

  Future<void> _trocarFundo() async {
    final atual = _fundo;
    if (atual == null) return;
    final prox = await Fundos.instancia.proximo(atual);
    if (mounted) setState(() => _fundo = prox);
  }

  /// Captura o cartão em 1080×1080.
  ///
  /// `pixelRatio` é calculado a partir da largura real na tela para o PNG sair
  /// sempre no mesmo tamanho, independentemente da densidade do aparelho.
  Future<Uint8List?> _renderizar() async {
    final contexto = _chave.currentContext;
    if (contexto == null) return null;
    final limite = contexto.findRenderObject() as RenderRepaintBoundary?;
    if (limite == null) return null;

    final escala = 1080 / limite.size.width;
    final imagem = await limite.toImage(pixelRatio: escala);
    final dados = await imagem.toByteData(format: ui.ImageByteFormat.png);
    return dados?.buffer.asUint8List();
  }

  Future<void> _compartilharImagem() async {
    setState(() => _gerando = true);
    try {
      final bytes = await _renderizar();
      if (bytes != null) {
        await Compartilhar.instancia.imagem(
          bytes,
          nome: 'versiculo',
          texto: Compartilhar.textoDaPassagem(
            widget.versiculos,
            sigla: widget.sigla,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _gerando = false);
    }
  }

  Future<void> _compartilharTexto() => Compartilhar.instancia.texto(
    Compartilhar.textoDaPassagem(widget.versiculos, sigla: widget.sigla),
  );

  @override
  Widget build(BuildContext context) {
    final fundo = _fundo;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Compartilhar versículo'),
        actions: [
          IconButton(
            tooltip: 'Trocar imagem',
            onPressed: fundo == null ? null : _trocarFundo,
            icon: const Icon(Icons.image_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: RepaintBoundary(
                key: _chave,
                child: AspectRatio(
                  aspectRatio: 1,
                  child: fundo == null
                      ? const ColoredBox(color: Colors.black12)
                      : _cartao(fundo),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (fundo != null)
            Center(
              child: Text(
                'Imagem: ${fundo.descricao} · toque no ícone para trocar',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _gerando ? null : _compartilharImagem,
            icon: _gerando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.image),
            label: const Text('Compartilhar como imagem'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _compartilharTexto,
            icon: const Icon(Icons.text_fields),
            label: const Text('Compartilhar como texto'),
          ),
        ],
      ),
    );
  }

  Widget _cartao(Fundo fundo) {
    // Texto longo precisa encolher, ou estoura o quadrado. Os limites vêm da
    // prática: um versículo curto respira em 30, um parágrafo do Salmo 119 só
    // cabe em 15.
    final tamanho = _texto.length > 320
        ? 15.0
        : _texto.length > 180
        ? 18.0
        : _texto.length > 90
        ? 23.0
        : 28.0;

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(fundo.asset, fit: BoxFit.cover),
        // Véu escuro: sem ele, texto claro sobre foto clara fica ilegível — e
        // as 21 imagens variam demais para confiar na sorte.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.30),
                Colors.black.withValues(alpha: 0.68),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(26, 26, 26, 22),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Center(
                  child: Text(
                    _texto,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: tamanho,
                      height: 1.42,
                      fontWeight: FontWeight.w500,
                      shadows: const [
                        Shadow(blurRadius: 8, color: Colors.black54),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                [
                  _referencia,
                  if (widget.sigla != null) widget.sigla!,
                ].join('  ·  '),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFFFC107),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Louvor JA',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  letterSpacing: 1.6,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
