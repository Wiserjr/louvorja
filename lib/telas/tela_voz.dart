import 'package:flutter/material.dart';

import '../dados/leitor_voz.dart';

/// Escolha do motor e da voz da leitura em voz alta.
///
/// A tela existe porque a qualidade da síntese no Android depende quase
/// inteiramente dessa escolha, e o padrão do sistema costuma ser o pior dos
/// instalados. Com o botão de experimentar ao lado, a comparação leva segundos.
class TelaVoz extends StatefulWidget {
  const TelaVoz({super.key});

  @override
  State<TelaVoz> createState() => _TelaVozState();
}

class _TelaVozState extends State<TelaVoz> {
  final _leitor = LeitorVoz.instancia;

  List<String> _motores = const [];
  List<Voz> _vozes = const [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final motores = await _leitor.motores();
    final vozes = await _leitor.vozesPortuguesas();
    if (!mounted) return;
    setState(() {
      _motores = motores;
      _vozes = vozes;
      _carregando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voz da leitura'),
        actions: [
          IconButton(
            tooltip: 'Experimentar',
            onPressed: _leitor.experimentar,
            icon: const Icon(Icons.play_circle_outline),
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'A naturalidade depende da voz escolhida. As de "rede" são '
                    'sintetizadas pelo Google e soam bem melhor, mas exigem '
                    'internet; as "offline" funcionam sem conexão. '
                    'Experimente e fique com a que preferir.',
                  ),
                ),

                if (_motores.length > 1) ...[
                  const _Titulo('Motor'),
                  for (final m in _motores)
                    RadioListTile<String>(
                      value: m,
                      // ignore: deprecated_member_use
                      groupValue: _leitor.motorEscolhido,
                      title: Text(_nomeAmigavel(m)),
                      subtitle: Text(m, style: tema.textTheme.labelSmall),
                      // ignore: deprecated_member_use
                      onChanged: (v) async {
                        if (v == null) return;
                        await _leitor.escolherMotor(v);
                        await _carregar();
                        await _leitor.experimentar();
                      },
                    ),
                ],

                if (_vozes.isNotEmpty) ...[
                  const _Titulo('Voz em português'),
                  for (final v in _vozes)
                    RadioListTile<String>(
                      value: v.nome,
                      // ignore: deprecated_member_use
                      groupValue: _leitor.vozEscolhida?.nome,
                      title: Row(
                        children: [
                          Expanded(child: Text(v.nome)),
                          if (v.rotulo.isNotEmpty)
                            Chip(
                              label: Text(v.rotulo),
                              labelStyle: tema.textTheme.labelSmall,
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                            ),
                        ],
                      ),
                      subtitle: Text(
                        v.deRede
                            ? '${v.locale} · mais natural, precisa de internet'
                            : v.doAparelho
                            ? '${v.locale} · funciona sem internet'
                            : v.locale,
                        style: tema.textTheme.labelSmall,
                      ),
                      // ignore: deprecated_member_use
                      onChanged: (nome) async {
                        if (nome == null) return;
                        await _leitor.escolherVoz(v);
                        setState(() {});
                        await _leitor.experimentar();
                      },
                    ),
                ],

                const _Titulo('Leitura'),
                ListTile(
                  title: const Text('Velocidade'),
                  subtitle: Slider(
                    value: _leitor.velocidade,
                    min: 0.2,
                    max: 1,
                    divisions: 8,
                    label: _leitor.velocidade.toStringAsFixed(2),
                    onChanged: (v) async {
                      await _leitor.definirVelocidade(v);
                      setState(() {});
                    },
                  ),
                ),
                SwitchListTile(
                  value: _leitor.dizerNumeros,
                  title: const Text('Falar o número do versículo'),
                  subtitle: const Text(
                    'Desligado soa mais natural; ligado ajuda a acompanhar '
                    'numa leitura coletiva.',
                  ),
                  onChanged: (v) async {
                    await _leitor.definirNumeros(v);
                    setState(() {});
                  },
                ),
                const SizedBox(height: 12),
                Center(
                  child: FilledButton.tonalIcon(
                    onPressed: _leitor.experimentar,
                    icon: const Icon(Icons.volume_up),
                    label: const Text('Experimentar a voz'),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  /// Os identificadores de motor são nomes de pacote; o da fabricante costuma
  /// ser o padrão e o pior, então vale dizer qual é qual.
  static String _nomeAmigavel(String pacote) {
    if (pacote.contains('google')) return 'Google Text-to-Speech';
    if (pacote.contains('samsung')) return 'Samsung TTS';
    if (pacote.contains('espeak')) return 'eSpeak';
    if (pacote.contains('acapela')) return 'Acapela';
    return pacote.split('.').last;
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
    child: Text(
      texto.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        letterSpacing: 1.1,
      ),
    ),
  );
}
