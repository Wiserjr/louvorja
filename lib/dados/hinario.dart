/// Busca e leitura dos hinários, sem tocar em banco nem em tela.
///
/// Fica à parte porque é exatamente o tipo de lógica que erra em silêncio: uma
/// busca que não acha "Ó Adorai" quando se digita "o adorai" não quebra nada,
/// só faz o hino parecer ausente do hinário.
library;

import 'modelos.dart';

const _acentos = {
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ç': 'c',
  'ñ': 'n',
};

final _separadores = RegExp(r'[^a-z0-9]+');

/// Minúsculas, sem acento e sem pontuação, com espaços simples.
///
/// A pontuação sai junto com os acentos porque os títulos a usam de forma
/// irregular — "Ó, Adorai o Senhor" no hinário de 1996 e "Ó Adorai o Senhor" no
/// atual. Quem digita "o adorai" espera achar os dois.
String normalizar(String texto) {
  final b = StringBuffer();
  for (final c in texto.toLowerCase().split('')) {
    b.write(_acentos[c] ?? c);
  }
  return b.toString().replaceAll(_separadores, ' ').trim();
}

/// Hinos de [hinos] que atendem a [termo], na ordem em que devem aparecer.
///
/// - **Só dígitos**: número do hino. Casa pelo começo, para a lista ir
///   estreitando enquanto se digita — "4" já mostra o 4 e os 40, e "43" deixa o
///   43 no topo, seguido de 430 a 439. O número exato vem sempre primeiro.
/// - **Texto**: cada palavra precisa aparecer no título, em qualquer ordem. Os
///   títulos que começam pelo que foi digitado sobem para o topo.
///
/// Dentro de cada grupo vale a ordem do hinário.
List<Musica> filtrarHinos(List<Musica> hinos, String termo) {
  final t = normalizar(termo);
  if (t.isEmpty) return hinos;

  int numero(Musica m) => m.faixa ?? 0;
  int porNumero(Musica a, Musica b) => numero(a).compareTo(numero(b));

  if (RegExp(r'^\d+$').hasMatch(t)) {
    final alvo = int.parse(t);
    final exatos = <Musica>[];
    final prefixo = <Musica>[];
    for (final m in hinos) {
      final n = m.faixa;
      if (n == null || n <= 0) continue;
      if (n == alvo) {
        exatos.add(m);
      } else if ('$n'.startsWith(t)) {
        prefixo.add(m);
      }
    }
    return [...exatos, ...prefixo..sort(porNumero)];
  }

  final palavras = t.split(' ');
  final comeca = <Musica>[];
  final contem = <Musica>[];
  for (final m in hinos) {
    final nome = normalizar(m.nome);
    if (!palavras.every(nome.contains)) continue;
    (nome.startsWith(t) ? comeca : contem).add(m);
  }
  return [...comeca..sort(porNumero), ...contem..sort(porNumero)];
}

/// Agrupa as linhas de letra de uma música em estrofes, para leitura corrida.
///
/// [textos] são os textos de **todas** as linhas da tabela `letras`, na ordem —
/// inclusive as que não são exibidas na projeção. É delas que vem a divisão: o
/// acervo separa as estrofes com um slide de texto vazio, e sem essas linhas o
/// hino viraria um bloco único.
///
/// Os slides de hino têm duas linhas cada, então uma estrofe de oito versos são
/// quatro slides seguidos entre dois vazios.
List<List<String>> estrofes(Iterable<String> textos) {
  final todas = <List<String>>[];
  var atual = <String>[];
  for (final texto in textos) {
    final linhas = texto
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (linhas.isEmpty) {
      if (atual.isNotEmpty) todas.add(atual);
      atual = <String>[];
    } else {
      atual.addAll(linhas);
    }
  }
  if (atual.isNotEmpty) todas.add(atual);
  return todas;
}

/// Nome curto de um hinário, para caber no seletor.
///
/// O catálogo chama o atual de "Hinário Adventista" e o anterior de "Hinário
/// Adventista 1996"; o ano, quando há, é o que distingue um do outro.
String rotuloDoHinario(String nome) {
  final ano = RegExp(r'\b(19|20)\d{2}\b').firstMatch(nome)?.group(0);
  return ano == null ? 'Hinário Novo' : 'Hinário $ano';
}
