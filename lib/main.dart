import 'package:flutter/material.dart';

import 'dados/midia.dart';
import 'telas/tela_albuns.dart';
import 'telas/tela_biblia.dart';
import 'telas/tela_online.dart';
import 'telas/tela_ajustes.dart';

void main() => runApp(const AppLouvorJA());

class AppLouvorJA extends StatelessWidget {
  const AppLouvorJA({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Louvor JA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1B5E9C),
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF1B5E9C),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const Inicio(),
    );
  }
}

class Inicio extends StatefulWidget {
  const Inicio({super.key});

  @override
  State<Inicio> createState() => _InicioState();
}

class _InicioState extends State<Inicio> {
  int _aba = 0;
  bool? _midiaOk;

  @override
  void initState() {
    super.initState();
    _verificarMidia();
  }

  Future<void> _verificarMidia() async {
    final ok = await Midia.instancia.configurada;
    if (mounted) setState(() => _midiaOk = ok);
  }

  @override
  Widget build(BuildContext context) {
    final telas = [
      const TelaAlbuns(),
      const TelaOnline(),
      const TelaBiblia(),
      TelaAjustes(aoMudarPasta: _verificarMidia),
    ];

    return Scaffold(
      // O banner fica acima das telas, que trazem seu próprio SafeArea. Sem este
      // SafeArea externo ele sobe até debaixo da barra de status e o texto
      // colide com o relógio do sistema.
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // O app é útil mesmo sem mídia: letras e Bíblia funcionam sozinhas.
            // O aviso convida a apontar a pasta sem bloquear o uso.
            if (_midiaOk == false)
              // Uma linha basta: o aviso não é um erro, é um convite. Ocupando
              // quatro linhas, competia com o conteúdo em toda navegação.
              Material(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: InkWell(
                  onTap: () => setState(() => _aba = 3),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.folder_off_outlined, size: 18),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Sem pasta de músicas — toque para configurar',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.chevron_right, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
            Expanded(child: telas[_aba]),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _aba,
        onDestinationSelected: (i) => setState(() => _aba = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.album_outlined),
            selectedIcon: Icon(Icons.album),
            label: 'Álbuns',
          ),
          NavigationDestination(
            icon: Icon(Icons.smart_display_outlined),
            selectedIcon: Icon(Icons.smart_display),
            label: 'On-line',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: 'Bíblia',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Ajustes',
          ),
        ],
      ),
    );
  }
}
