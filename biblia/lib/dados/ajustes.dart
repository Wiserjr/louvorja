import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'modelos.dart';

/// Preferências e o que a pessoa cria: tradução, letra, tema, onde parou,
/// marcações e anotações. Tudo nas preferências do app, fora dos bancos —
/// trocar o banco numa atualização nunca apaga nada disto.
class Ajustes extends ChangeNotifier {
  Ajustes._();
  static final Ajustes instancia = Ajustes._();

  late SharedPreferences _p;

  Future<void> carregar() async {
    _p = await SharedPreferences.getInstance();
  }

  int? get versao => _p.getInt('versao');
  set versao(int? v) {
    if (v == null) {
      _p.remove('versao');
    } else {
      _p.setInt('versao', v);
    }
    notifyListeners();
  }

  double get tamanhoLetra => _p.getDouble('tamanhoLetra') ?? 18;
  set tamanhoLetra(double v) {
    _p.setDouble('tamanhoLetra', v.clamp(13, 34));
    notifyListeners();
  }

  ThemeMode get tema => ThemeMode.values[_p.getInt('tema') ?? 0];
  set tema(ThemeMode v) {
    _p.setInt('tema', v.index);
    notifyListeners();
  }

  /// Palavras de Jesus em vermelho (nas traduções que as marcam).
  bool get letrasVermelhas => _p.getBool('letrasVermelhas') ?? true;
  set letrasVermelhas(bool v) {
    _p.setBool('letrasVermelhas', v);
    notifyListeners();
  }

  /// Mostrar, ao lado de cada versículo, quantos trechos de Ellen G. White o
  /// citam.
  bool get marcadoresEgw => _p.getBool('marcadoresEgw') ?? true;
  set marcadoresEgw(bool v) {
    _p.setBool('marcadoresEgw', v);
    notifyListeners();
  }

  /// Incluir os pioneiros (Urias Smith, J. N. Andrews...) no estudo.
  bool get mostrarPioneiros => _p.getBool('mostrarPioneiros') ?? true;
  set mostrarPioneiros(bool v) {
    _p.setBool('mostrarPioneiros', v);
    notifyListeners();
  }

  Posicao get ultimaPosicao {
    final l = _p.getInt('ultLivro') ?? 43;
    final c = _p.getInt('ultCapitulo') ?? 1;
    return Posicao(l, c);
  }

  set ultimaPosicao(Posicao p) {
    _p.setInt('ultLivro', p.livro);
    _p.setInt('ultCapitulo', p.capitulo);
  }

  // --- marcações (cor por versículo) e anotações ---

  static String _k(int livro, int cap, int ver) => '$livro:$cap:$ver';

  /// Cor da marcação (índice em [coresMarcacao]) ou null.
  ///
  /// Consultada para cada versículo a cada desenho do leitor: as marcações
  /// ficam num mapa, refeito só quando mudam.
  int? marcacao(int livro, int cap, int ver) =>
      (_marcas ??= _lerMarcas())[_k(livro, cap, ver)];

  Map<String, int>? _marcas;

  Map<String, int> _lerMarcas() {
    final mapa = <String, int>{};
    for (final e in _p.getStringList('marcacoes') ?? const <String>[]) {
      final i = e.indexOf('=');
      final cor = i < 0 ? null : int.tryParse(e.substring(i + 1));
      if (cor != null) mapa[e.substring(0, i)] = cor;
    }
    return mapa;
  }

  void marcar(int livro, int cap, int ver, int? cor) {
    final prefixo = '${_k(livro, cap, ver)}=';
    final m = [
      for (final e in _p.getStringList('marcacoes') ?? const <String>[])
        if (!e.startsWith(prefixo)) e,
    ];
    if (cor != null) m.add('$prefixo$cor');
    _p.setStringList('marcacoes', m);
    _marcas = null;
    notifyListeners();
  }

  /// Todas as marcações: ((livro, capítulo, versículo), cor).
  List<((int, int, int), int)> todasMarcacoes() {
    final r = <((int, int, int), int)>[];
    for (final e in _p.getStringList('marcacoes') ?? const <String>[]) {
      final partes = e.split('=');
      final k = partes[0].split(':').map(int.tryParse).toList();
      final cor = int.tryParse(partes.length > 1 ? partes[1] : '');
      if (k.length == 3 && !k.contains(null) && cor != null) {
        r.add(((k[0]!, k[1]!, k[2]!), cor));
      }
    }
    r.sort((a, b) => _comparar(a.$1, b.$1));
    return r;
  }

  String? anotacao(int livro, int cap, int ver) =>
      _p.getString('nota:${_k(livro, cap, ver)}');

  void anotar(int livro, int cap, int ver, String? texto) {
    final k = 'nota:${_k(livro, cap, ver)}';
    if (texto == null || texto.trim().isEmpty) {
      _p.remove(k);
    } else {
      _p.setString(k, texto.trim());
    }
    notifyListeners();
  }

  List<((int, int, int), String)> todasAnotacoes() {
    final r = <((int, int, int), String)>[];
    for (final k in _p.getKeys()) {
      if (!k.startsWith('nota:')) continue;
      final p = k.substring(5).split(':').map(int.tryParse).toList();
      final t = _p.getString(k);
      if (p.length == 3 && !p.contains(null) && t != null) {
        r.add(((p[0]!, p[1]!, p[2]!), t));
      }
    }
    r.sort((a, b) => _comparar(a.$1, b.$1));
    return r;
  }

  static int _comparar((int, int, int) x, (int, int, int) y) => x.$1 != y.$1
      ? x.$1.compareTo(y.$1)
      : x.$2 != y.$2
      ? x.$2.compareTo(y.$2)
      : x.$3.compareTo(y.$3);
}

/// Cores das marcações, translúcidas para o texto continuar legível nos dois
/// temas.
const coresMarcacao = <Color>[
  Color(0x66FFD54F), // amarelo
  Color(0x5581C784), // verde
  Color(0x5564B5F6), // azul
  Color(0x55F48FB1), // rosa
  Color(0x55FFB74D), // laranja
];
