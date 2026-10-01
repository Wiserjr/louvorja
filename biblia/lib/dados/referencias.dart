import 'modelos.dart';

/// Nomes dos livros e o que se precisa para escrever e ler referências.
///
/// A tabela é a mesma de ferramentas/referencias_pt.py (que indexa as obras);
/// aqui só o necessário para a tela: formatar "João 3:16-17" e entender o que
/// a pessoa digita na busca ("jo 3 16", "1co13", "gênesis 1").
class Referencias {
  Referencias._();

  static const nomes = <String>[
    'Gênesis', 'Êxodo', 'Levítico', 'Números', 'Deuteronômio', 'Josué', //
    'Juízes', 'Rute', '1 Samuel', '2 Samuel', '1 Reis', '2 Reis',
    '1 Crônicas', '2 Crônicas', 'Esdras', 'Neemias', 'Ester', 'Jó', 'Salmos',
    'Provérbios', 'Eclesiastes', 'Cantares', 'Isaías', 'Jeremias',
    'Lamentações', 'Ezequiel', 'Daniel', 'Oséias', 'Joel', 'Amós', 'Obadias',
    'Jonas', 'Miquéias', 'Naum', 'Habacuque', 'Sofonias', 'Ageu', 'Zacarias',
    'Malaquias', 'Mateus', 'Marcos', 'Lucas', 'João', 'Atos', 'Romanos',
    '1 Coríntios', '2 Coríntios', 'Gálatas', 'Efésios', 'Filipenses',
    'Colossenses', '1 Tessalonicenses', '2 Tessalonicenses', '1 Timóteo',
    '2 Timóteo', 'Tito', 'Filemom', 'Hebreus', 'Tiago', '1 Pedro', '2 Pedro',
    '1 João', '2 João', '3 João', 'Judas', 'Apocalipse',
  ];

  static const abreviacoes = <String>[
    'Gn', 'Êx', 'Lv', 'Nm', 'Dt', 'Js', 'Jz', 'Rt', '1Sm', '2Sm', '1Rs', //
    '2Rs', '1Cr', '2Cr', 'Ed', 'Ne', 'Et', 'Jó', 'Sl', 'Pv', 'Ec', 'Ct', 'Is',
    'Jr', 'Lm', 'Ez', 'Dn', 'Os', 'Jl', 'Am', 'Ob', 'Jn', 'Mq', 'Na', 'Hc',
    'Sf', 'Ag', 'Zc', 'Ml', 'Mt', 'Mc', 'Lc', 'Jo', 'At', 'Rm', '1Co', '2Co',
    'Gl', 'Ef', 'Fp', 'Cl', '1Ts', '2Ts', '1Tm', '2Tm', 'Tt', 'Fm', 'Hb',
    'Tg', '1Pe', '2Pe', '1Jo', '2Jo', '3Jo', 'Jd', 'Ap',
  ];

  static const capitulos = <int>[
    50, 40, 27, 36, 34, 24, 21, 4, 31, 24, 22, 25, 29, 36, 10, 13, 10, 42, //
    150, 31, 12, 8, 66, 52, 5, 48, 12, 14, 3, 9, 1, 4, 7, 3, 3, 3, 2, 14, 4,
    28, 16, 24, 21, 28, 16, 16, 13, 6, 6, 4, 4, 5, 3, 6, 4, 3, 1, 13, 5, 5,
    3, 5, 1, 1, 1, 22,
  ];

  static String nome(int livro) => nomes[livro - 1];
  static String abreviacao(int livro) => abreviacoes[livro - 1];

  /// (43, 3016, 3017) -> "João 3:16-17"; capítulo inteiro -> "Salmos 23".
  static String formatar(int livro, int ini, int fim, {bool curto = false}) {
    final n = curto ? abreviacao(livro) : nome(livro);
    final c1 = ini ~/ 1000, v1 = ini % 1000;
    final c2 = fim ~/ 1000, v2 = fim % 1000;
    if (v1 == 0 && v2 == 999) {
      return c1 == c2 ? '$n $c1' : '$n $c1-$c2';
    }
    if (ini == fim) return '$n $c1:$v1';
    if (c1 == c2) return '$n $c1:$v1-$v2';
    return '$n $c1:$v1-$c2:$v2';
  }

  static String semAcento(String s) {
    const de = 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ';
    const para = 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC';
    final b = StringBuffer();
    for (final r in s.runes) {
      final c = String.fromCharCode(r);
      final i = de.indexOf(c);
      b.write(i >= 0 ? para[i] : c);
    }
    return b.toString();
  }

  static String _chave(String s) =>
      semAcento(s).toLowerCase().replaceAll(RegExp(r'[\s.]'), '');

  static final Map<String, int> _porNome = () {
    final m = <String, int>{};
    for (var i = 0; i < 66; i++) {
      m[_chave(nomes[i])] = i + 1;
      m[_chave(abreviacoes[i])] = i + 1;
    }
    // Formas comuns que não estão nas listas acima.
    m['salmo'] = 19;
    m['canticos'] = 22;
    m['canticodoscanticos'] = 22;
    m['oseias'] = 28;
    m['miqueias'] = 33;
    m['filemon'] = 57;
    m['apoc'] = 66;
    m['ex'] = 2;
    m['jo'] = 43; // "Jó" vira "jo" sem acento; ver interpretar()
    return m;
  }();

  /// Entende o que a pessoa digitou: "jo 3:16", "Jó 1", "1co 13 4",
  /// "gênesis". Devolve null se não reconhecer um livro.
  static Posicao? interpretar(String entrada) {
    final t = entrada.trim();
    if (t.isEmpty) return null;
    final m = RegExp(
      r'^\s*([1-3]?\s*[^\d\s:.,][^\d:.,]*?)\.?\s*(\d{1,3})?(?:\s*[:.,\s]\s*(\d{1,3}))?\s*$',
    ).firstMatch(t);
    if (m == null) return null;
    final bruto = m.group(1)!.trim();
    int? livro;
    // "Jó" com acento é Jó; "jo" sem acento é João, como na abreviação.
    if (bruto.toLowerCase() == 'jó') {
      livro = 18;
    } else {
      final k = _chave(bruto);
      livro = _porNome[k];
      if (livro == null && k.length >= 3) {
        // Prefixo: "gen", "apocal", "1cor".
        for (var i = 0; i < 66; i++) {
          if (_chave(nomes[i]).startsWith(k)) {
            livro = i + 1;
            break;
          }
        }
      }
    }
    if (livro == null) return null;
    var cap = int.tryParse(m.group(2) ?? '') ?? 1;
    var ver = int.tryParse(m.group(3) ?? '');
    final caps = capitulos[livro - 1];
    if (caps == 1 && m.group(2) != null && m.group(3) == null && cap > 1) {
      // "Judas 3" é o versículo 3.
      ver = cap;
      cap = 1;
    }
    if (cap < 1 || cap > caps) return null;
    return Posicao(livro, cap, ver);
  }
}
