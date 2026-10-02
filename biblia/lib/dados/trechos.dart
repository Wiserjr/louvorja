import 'package:pdfrx/pdfrx.dart';

import 'biblioteca.dart';
import 'modelos.dart';

/// Lê do PDF baixado o texto de um trecho de Ellen G. White ou de um pioneiro.
///
/// O índice (ferramentas/indexar_obras.py) guarda, para cada parágrafo, os
/// intervalos `(página, início, fim)` no texto cru que o PDFium extrai da
/// página. O pdfrx usa o mesmo PDFium, montando o texto caractere a caractere
/// do mesmo jeito; então recortar aqui os mesmos intervalos e aplicar a mesma
/// [normalizar] dá exatamente o parágrafo indexado.
///
/// Se o arquivo não é o que foi indexado (o Centro White publicou outra
/// edição), as posições não valem mais. Aí o trecho é reencontrado pela
/// própria citação ("Mateus 4:2-4") nas páginas próximas, e o texto mostrado é
/// o que a cerca até os limites das frases.
class Trechos {
  Trechos._();
  static final Trechos instancia = Trechos._();

  /// Poucos documentos abertos ao mesmo tempo: cada um segura memória nativa.
  final _docs = <int, Future<PdfDocument>>{};
  static const _maxDocs = 3;

  final _cache = <int, String>{};
  static const _maxCache = 300;

  Future<PdfDocument> _documento(Obra obra) async {
    final existente = _docs.remove(obra.id);
    if (existente != null) {
      _docs[obra.id] = existente;
      return existente;
    }
    final arquivo = await Biblioteca.instancia.arquivo(obra);
    final futuro = PdfDocument.openFile(arquivo.path);
    _docs[obra.id] = futuro;
    while (_docs.length > _maxDocs) {
      final velho = _docs.remove(_docs.keys.first);
      velho?.then((d) => d.dispose()).ignore();
    }
    try {
      return await futuro;
    } catch (_) {
      _docs.remove(obra.id);
      rethrow;
    }
  }

  /// Fecha o documento (antes de apagar o arquivo, por exemplo).
  Future<void> fechar(Obra obra) async {
    final d = _docs.remove(obra.id);
    if (d != null) await (await d).dispose();
  }

  Future<String> _textoPagina(PdfDocument doc, int pagina) async {
    if (pagina < 0 || pagina >= doc.pages.length) return '';
    final t = await doc.pages[pagina].loadText();
    return t?.fullText ?? '';
  }

  /// O texto do trecho, ou `null` se a obra não foi baixada.
  Future<String?> texto(Trecho t) async {
    final guardado = _cache.remove(t.id);
    if (guardado != null) return _cache[t.id] = guardado;
    final bib = Biblioteca.instancia;
    if (!bib.disponivel(t.obra)) return null;

    final doc = await _documento(t.obra);
    final paginas = <int, String>{};
    for (final (pag, _, _) in t.segmentos) {
      paginas[pag] ??= await _textoPagina(doc, pag);
    }

    String? resultado;
    if (bib.estado(t.obra) == EstadoObra.pronta) {
      resultado = recortar(paginas, t.segmentos);
      // Confere: o recorte tem de conter a citação que o índice registrou.
      final ancora = t.ancora;
      if (ancora != null &&
          !_semEspacos(resultado).contains(_semEspacos(ancora))) {
        resultado = null;
      }
    }
    if (resultado == null || resultado.isEmpty) {
      resultado = await _procurar(doc, t);
    }
    if (resultado == null) return null;
    _cache[t.id] = resultado;
    while (_cache.length > _maxCache) {
      _cache.remove(_cache.keys.first);
    }
    return resultado;
  }

  /// Plano B: acha a citação nas páginas vizinhas e devolve as frases em volta.
  Future<String?> _procurar(PdfDocument doc, Trecho t) async {
    final ancora = t.ancora;
    if (ancora == null) {
      // Trecho de capítulo ("Este capítulo é baseado em...") ou de comentário:
      // mostra o começo da página indicada.
      final txt = normalizar(await _textoPagina(doc, t.pagina));
      return txt.isEmpty ? null : _limitar(txt, 0, 900);
    }
    final alvo = _semEspacos(ancora);
    for (final delta in const [0, 1, -1, 2, -2, 3, -3, 5, -5]) {
      final pag = t.pagina + delta;
      final txt = normalizar(await _textoPagina(doc, pag));
      if (txt.isEmpty) continue;
      final pos = _posicaoSemEspacos(txt, alvo);
      if (pos < 0) continue;
      return contexto(txt, pos, pos + ancora.length);
    }
    return null;
  }

  static String _semEspacos(String s) => s.replaceAll(RegExp(r'\s+'), '');

  /// Posição em [texto] onde começa [alvo] (comparando sem espaços).
  static int _posicaoSemEspacos(String texto, String alvo) {
    final mapa = <int>[];
    final b = StringBuffer();
    for (var i = 0; i < texto.length; i++) {
      final c = texto[i];
      if (c.trim().isEmpty) continue;
      mapa.add(i);
      b.write(c);
    }
    final idx = b.toString().indexOf(alvo);
    return idx < 0 ? -1 : mapa[idx];
  }

  static String _limitar(String s, int ini, int fim) {
    final f = fim.clamp(0, s.length);
    var corte = s.substring(ini.clamp(0, f), f);
    if (f < s.length) corte = '$corte…';
    return corte;
  }
}

/// Recorta os segmentos do texto cru das páginas e normaliza — o mesmo que
/// `texto_dos_segmentos` em ferramentas/texto_pdf.py.
String recortar(Map<int, String> paginas, List<(int, int, int)> segmentos) {
  final partes = <String>[];
  for (final (pag, ini, fim) in segmentos) {
    final cru = paginas[pag] ?? '';
    if (ini < 0 || fim > cru.length || ini > fim) return '';
    partes.add(cru.substring(ini, fim));
  }
  return normalizar(partes.join('\r\n'));
}

/// Pronomes que seguem hífen de verdade ("intitulou-se", "dá-lhe"). Mesma
/// lista de ferramentas/texto_pdf.py.
const _encliticos = {
  'se', 'lhe', 'lhes', 'o', 'a', 'os', 'as', 'me', 'te', 'nos', 'vos', //
  'lo', 'la', 'los', 'las', 'no', 'na', 'nas', 'mo', 'ma', 'ei', 'ão',
  'á', 'ás', 'ia', 'iam', 'emos',
};

final _quebra = RegExp(r'(?:\x02\s*|-\r?\n\s*)([\p{L}\p{N}_]+)', unicode: true);
final _marca = RegExp(r'\[\d{1,4}\]\s?');
final _espacos = RegExp(r'\s+');

/// Texto cru de um trecho -> texto de leitura: junta linhas, desfaz a
/// separação de sílabas, tira as marcas de página original ("[72]").
///
/// Tem de dar o mesmo resultado que `normalizar` em ferramentas/texto_pdf.py;
/// os testes dos dois lados usam os mesmos casos.
String normalizar(String cru) {
  var s = cru.replaceAll('­', '\x02');
  s = s.replaceAllMapped(_quebra, (m) {
    final seguinte = m.group(1)!;
    return (_encliticos.contains(seguinte.toLowerCase()) ? '-' : '') + seguinte;
  });
  s = s.replaceAll('\x02', '');
  s = s.replaceAll(_marca, '');
  s = s.replaceAll(_espacos, ' ');
  return s.trim();
}

/// As frases em volta de `[ini, fim)` em [texto].
///
/// A citação costuma vir logo depois do texto citado ("“Está escrito: Nem só
/// de pão...” Mateus 4:4."), então o começo é o da frase onde abre a última
/// aspa antes da referência — ou, sem aspas, o da frase da própria
/// referência —, no máximo ~700 caracteres antes. O fim é o da frase.
String contexto(String texto, int ini, int fim) {
  final janela = (ini - 700).clamp(0, texto.length);
  final abre = texto.lastIndexOf('“', ini);
  final limite = abre >= janela ? abre : (ini - 3).clamp(0, texto.length);
  var a = janela;
  for (final m in RegExp(r'[.!?…]["”’]?\s+').allMatches(texto, janela)) {
    if (m.end > limite) break;
    a = m.end;
  }
  var b = fim.clamp(0, texto.length);
  final m = RegExp(r'[.!?…]["”’]?(\s|$)').firstMatch(texto.substring(b));
  if (m != null && m.end < 400) b += m.end;
  final prefixo = a > 0 ? '… ' : '';
  final sufixo = b < texto.length ? ' …' : '';
  return '$prefixo${texto.substring(a, b).trim()}$sufixo';
}
