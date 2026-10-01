import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../dados/ajustes.dart';
import '../dados/biblia.dart';
import '../dados/modelos.dart';
import '../dados/referencias.dart';

String textoParaCompartilhar(Posicao p, String texto, Versao versao) =>
    '“${textoPuro(texto).trim()}”\n'
    '${Referencias.nome(p.livro)} ${p.capitulo}:${p.versiculo} (${versao.sigla})';

/// Menu de um versículo: copiar, compartilhar, marcar com cor, anotar.
Future<void> mostrarAcoesVersiculo(
  BuildContext context,
  Posicao p,
  String texto,
  Versao versao,
) async {
  final ref = '${Referencias.nome(p.livro)} ${p.capitulo}:${p.versiculo}';
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(ref, style: Theme.of(c).textTheme.titleMedium),
          ),
          BarraMarcacao(posicao: p),
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('Copiar'),
            onTap: () {
              Clipboard.setData(
                ClipboardData(text: textoParaCompartilhar(p, texto, versao)),
              );
              Navigator.pop(c);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Versículo copiado.')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.share_outlined),
            title: const Text('Compartilhar'),
            onTap: () {
              Navigator.pop(c);
              SharePlus.instance.share(
                ShareParams(text: textoParaCompartilhar(p, texto, versao)),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_note),
            title: const Text('Anotar'),
            onTap: () {
              Navigator.pop(c);
              editarAnotacao(context, p);
            },
          ),
        ],
      ),
    ),
  );
}

/// As cores de marcação, e "sem cor".
class BarraMarcacao extends StatelessWidget {
  const BarraMarcacao({super.key, required this.posicao});
  final Posicao posicao;

  @override
  Widget build(BuildContext context) {
    final aj = Ajustes.instancia;
    final p = posicao;
    return ListenableBuilder(
      listenable: aj,
      builder: (context, _) {
        final atual = aj.marcacao(p.livro, p.capitulo, p.versiculo!);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              for (var i = 0; i < coresMarcacao.length; i++)
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => aj.marcar(
                      p.livro,
                      p.capitulo,
                      p.versiculo!,
                      atual == i ? null : i,
                    ),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: coresMarcacao[i].withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                        border: atual == i
                            ? Border.all(
                                width: 2.5,
                                color: Theme.of(context).colorScheme.onSurface,
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
              if (atual != null)
                IconButton(
                  tooltip: 'Tirar marcação',
                  icon: const Icon(Icons.format_color_reset_outlined),
                  onPressed: () =>
                      aj.marcar(p.livro, p.capitulo, p.versiculo!, null),
                ),
            ],
          ),
        );
      },
    );
  }
}

Future<void> editarAnotacao(BuildContext context, Posicao p) async {
  final aj = Ajustes.instancia;
  final ctrl = TextEditingController(
    text: aj.anotacao(p.livro, p.capitulo, p.versiculo!) ?? '',
  );
  final salvar = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(
        'Anotação — ${Referencias.nome(p.livro)} ${p.capitulo}:${p.versiculo}',
      ),
      content: SizedBox(
        width: 480,
        child: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 8,
          minLines: 3,
          decoration: const InputDecoration(
            hintText: 'Escreva o que este versículo diz a você…',
            border: OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Salvar'),
        ),
      ],
    ),
  );
  if (salvar == true) aj.anotar(p.livro, p.capitulo, p.versiculo!, ctrl.text);
  ctrl.dispose();
}
