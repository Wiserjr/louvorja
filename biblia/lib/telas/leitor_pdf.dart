import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../dados/biblioteca.dart';
import '../dados/modelos.dart';

/// O livro de Ellen G. White (ou do pioneiro) aberto na página do trecho, com
/// a citação destacada quando dá para achá-la.
class TelaPdf extends StatefulWidget {
  const TelaPdf({
    super.key,
    required this.obra,
    required this.pagina,
    this.destaque,
  });

  final Obra obra;

  /// Índice da página no PDF, a partir de 0.
  final int pagina;

  /// Texto a destacar ("Mateus 4:4").
  final String? destaque;

  @override
  State<TelaPdf> createState() => _TelaPdfState();
}

class _TelaPdfState extends State<TelaPdf> {
  final _controle = PdfViewerController();
  PdfTextSearcher? _busca;
  late final Future<String> _caminho = Biblioteca.instancia
      .arquivo(widget.obra)
      .then((f) => f.path);

  @override
  void initState() {
    super.initState();
    final d = widget.destaque;
    if (d != null && d.isNotEmpty) {
      _busca = PdfTextSearcher(_controle)..addListener(_atualizar);
    }
  }

  void _atualizar() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _busca?.removeListener(_atualizar);
    _busca?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final busca = _busca;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.obra.titulo, overflow: TextOverflow.ellipsis),
      ),
      body: FutureBuilder<String>(
        future: _caminho,
        builder: (context, snap) {
          final caminho = snap.data;
          if (caminho == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return PdfViewer.file(
            caminho,
            controller: _controle,
            initialPageNumber: widget.pagina + 1,
            params: PdfViewerParams(
              pagePaintCallbacks: [
                if (busca != null) busca.pageTextMatchPaintCallback,
              ],
              onViewerReady: (document, controller) {
                final d = widget.destaque;
                if (busca != null && d != null) {
                  busca.startTextSearch(d, goToFirstMatch: false);
                }
              },
            ),
          );
        },
      ),
    );
  }
}
