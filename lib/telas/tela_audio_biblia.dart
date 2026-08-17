import 'package:flutter/material.dart';

import '../dados/biblia_audio.dart';

/// Configuração da Bíblia em áudio gravada (Bible Brain).
///
/// A chave é do usuário, não do app: a Bible Brain é gratuita para uso não
/// comercial mas exige registro por desenvolvedor. Pedir a chave aqui é o que
/// mantém o uso legítimo — a alternativa seria extrair gravações de outros
/// aplicativos, o que os termos deles vedam.
class TelaAudioBiblia extends StatefulWidget {
  const TelaAudioBiblia({super.key});

  @override
  State<TelaAudioBiblia> createState() => _TelaAudioBibliaState();
}

class _TelaAudioBibliaState extends State<TelaAudioBiblia> {
  final _api = BibleBrain.instancia;
  final _chaveCtrl = TextEditingController();

  List<BibliaAudio> _versoes = const [];
  BibliaAudio? _escolhida;
  String? _mensagem;
  bool _ok = false;
  bool _buscando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _chaveCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    final k = await _api.chave;
    final v = await _api.versaoEscolhida;
    if (!mounted) return;
    setState(() {
      _chaveCtrl.text = k ?? '';
      _escolhida = v;
    });
    if (k != null) _buscar();
  }

  Future<void> _buscar() async {
    setState(() {
      _buscando = true;
      _mensagem = null;
    });
    await _api.definirChave(_chaveCtrl.text);
    final r = await _api.listarVersoes();
    if (!mounted) return;
    setState(() {
      _buscando = false;
      _ok = r.ok;
      _mensagem = r.mensagem;
      _versoes = r.versoes;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Bíblia em áudio')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Gravações narradas por pessoas, da Bible Brain (Faith Comes By '
            'Hearing). É gratuita para uso não comercial, mas exige uma chave '
            'de desenvolvedor — peça a sua e cole abaixo.',
            style: tema.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          SelectableText(
            BibleBrain.paginaDaChave,
            style: tema.textTheme.bodySmall?.copyWith(
              color: tema.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _chaveCtrl,
            decoration: const InputDecoration(
              labelText: 'Chave da API',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            autocorrect: false,
            enableSuggestions: false,
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: _buscando ? null : _buscar,
            icon: _buscando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_sync_outlined),
            label: const Text('Verificar e listar versões'),
          ),
          if (_mensagem != null) ...[
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _ok ? Icons.check_circle_outline : Icons.error_outline,
                  size: 20,
                  color: _ok
                      ? tema.colorScheme.primary
                      : tema.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(_mensagem!)),
              ],
            ),
          ],
          if (_versoes.isNotEmpty) ...[
            const SizedBox(height: 22),
            Text(
              'VERSÕES EM ÁUDIO',
              style: tema.textTheme.labelSmall?.copyWith(
                color: tema.colorScheme.primary,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 4),
            for (final v in _versoes)
              RadioListTile<String>(
                value: v.filesetId,
                // ignore: deprecated_member_use
                groupValue: _escolhida?.filesetId,
                title: Text(v.nome),
                subtitle: Text(v.descricao),
                // ignore: deprecated_member_use
                onChanged: (_) async {
                  await _api.escolherVersao(v);
                  if (mounted) setState(() => _escolhida = v);
                },
              ),
            if (_escolhida != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextButton.icon(
                  onPressed: () async {
                    await _api.escolherVersao(null);
                    if (mounted) setState(() => _escolhida = null);
                  },
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Não usar áudio gravado'),
                ),
              ),
          ],
          const SizedBox(height: 24),
          Text(
            'Com uma versão escolhida, o botão de ouvir na Bíblia toca a '
            'gravação. Sem chave, ou num capítulo que a versão não cobre — '
            'uma edição só do Novo Testamento, por exemplo —, o app volta '
            'sozinho para a leitura por voz sintetizada.',
            style: tema.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
