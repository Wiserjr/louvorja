import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pdfrx/pdfrx.dart';

import 'dados/ajustes.dart';
import 'dados/banco.dart';
import 'dados/biblioteca.dart';
import 'dados/estudo.dart';
import 'telas/inicio.dart';
import 'telas/tema.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Banco.configurarPlataforma();
  // O texto dos trechos é lido do PDF antes de qualquer visualizador abrir.
  await pdfrxFlutterInitialize();
  await Ajustes.instancia.carregar();
  runApp(const AppBiblia());
}

class AppBiblia extends StatelessWidget {
  const AppBiblia({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Ajustes.instancia,
      builder: (context, _) => MaterialApp(
        title: 'Bíblia de Estudo',
        debugShowCheckedModeBanner: false,
        theme: temaClaro(),
        darkTheme: temaEscuro(),
        themeMode: Ajustes.instancia.tema,
        home: const _Abertura(),
      ),
    );
  }
}

/// Descompacta os bancos na primeira abertura (alguns segundos) e abre o
/// leitor.
class _Abertura extends StatefulWidget {
  const _Abertura();

  @override
  State<_Abertura> createState() => _AberturaState();
}

class _AberturaState extends State<_Abertura> {
  late final Future<void> _preparo = _preparar();

  Future<void> _preparar() async {
    final info = await PackageInfo.fromPlatform();
    await Banco.instancia.abrir(
      versaoApp: '${info.version}+${info.buildNumber}',
    );
    final obras = await Estudo.instancia.obras();
    await Biblioteca.instancia.carregar(obras.values);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _preparo,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.done && !snap.hasError) {
          return const TelaInicio();
        }
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.menu_book_rounded,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Bíblia de Estudo',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 24),
                  if (snap.hasError)
                    Text(
                      'Não foi possível preparar a Bíblia: ${snap.error}\n'
                      'Feche e abra o app de novo. Não é preciso desinstalar.',
                      textAlign: TextAlign.center,
                    )
                  else ...[
                    const SizedBox(
                      width: 200,
                      child: LinearProgressIndicator(),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Preparando as traduções…',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
