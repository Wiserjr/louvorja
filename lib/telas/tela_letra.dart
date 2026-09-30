import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../dados/compartilhar.dart';
import '../dados/hinario.dart';
import '../dados/modelos.dart';
import '../dados/repositorio.dart';

/// A letra inteira, em estrofes, para ler ou cantar sem áudio.
///
/// É a opção "Letra" do site: nada de projeção, fundo ou tempo — só o texto,
/// num tamanho que dê para acompanhar de longe.
class TelaLetra extends StatefulWidget {
  const TelaLetra({super.key, required this.musica, this.origem});

  final Musica musica;

  /// Linha abaixo do título: "Hino 43 · Hinário Adventista", ou o álbum.
  final String? origem;

  @override
  State<TelaLetra> createState() => _TelaLetraState();
}

class _TelaLetraState extends State<TelaLetra> {
  static const _chaveFonte = 'fonte_letra';
  static const _fonteMin = 15.0;
  static const _fonteMax = 35.0;

  late final Future<List<List<String>>> _estrofes;

  /// Começa maior que o texto comum: a letra costuma ser lida com o celular na
  /// mão e o olho no púlpito, não como quem lê uma mensagem.
  double _fonte = 21;

  @override
  void initState() {
    super.initState();
    _estrofes = const Repositorio()
        .textosDaLetra(widget.musica.id)
        .then(estrofes);
    _lerFonte();
  }

  /// O tamanho escolhido vale para todas as letras: quem precisou aumentar numa
  /// vai precisar na seguinte.
  Future<void> _lerFonte() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getDouble(_chaveFonte);
      if (v != null && mounted) setState(() => _fonte = v);
    } catch (_) {
      // Sem preferência gravada, fica o padrão.
    }
  }

  Future<void> _mudarFonte(double delta) async {
    setState(() => _fonte = (_fonte + delta).clamp(_fonteMin, _fonteMax));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_chaveFonte, _fonte);
    } catch (_) {
      // A mudança vale nesta tela mesmo sem persistir.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.musica.nome),
        bottom: widget.origem == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(18),
                child: Text(
                  widget.origem!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
        actions: [
          IconButton(
            tooltip: 'Diminuir a letra',
            onPressed: _fonte <= _fonteMin ? null : () => _mudarFonte(-2),
            icon: const Icon(Icons.text_decrease),
          ),
          IconButton(
            tooltip: 'Aumentar a letra',
            onPressed: _fonte >= _fonteMax ? null : () => _mudarFonte(2),
            icon: const Icon(Icons.text_increase),
          ),
          FutureBuilder<List<List<String>>>(
            future: _estrofes,
            builder: (context, snap) {
              final e = snap.data ?? const [];
              if (e.isEmpty) return const SizedBox.shrink();
              return IconButton(
                tooltip: 'Compartilhar a letra',
                onPressed: () => Compartilhar.instancia.texto(
                  Compartilhar.textoDasEstrofes(
                    widget.musica.nome,
                    e,
                    origem: widget.origem,
                  ),
                ),
                icon: const Icon(Icons.share_outlined),
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<List<List<String>>>(
        future: _estrofes,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Erro ao ler a letra:\n${snap.error}'));
          }
          final todas = snap.data!;
          if (todas.isEmpty) {
            return const Center(
              child: Text('Esta música não tem letra cadastrada.'),
            );
          }
          final estilo = Theme.of(context).textTheme.bodyLarge
              ?.copyWith(fontSize: _fonte, height: 1.4);
          // Selecionável para quem quer copiar um trecho só — o botão de
          // compartilhar manda a letra inteira.
          return SelectionArea(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              itemCount: todas.length,
              separatorBuilder: (_, _) => SizedBox(height: _fonte * 1.1),
              itemBuilder: (context, i) =>
                  Text(todas[i].join('\n'), style: estilo),
            ),
          );
        },
      ),
    );
  }
}
