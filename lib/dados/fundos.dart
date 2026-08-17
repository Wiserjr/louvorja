import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;

/// Uma imagem de fundo para cartões de versículo, com o tema que ela evoca.
class Fundo {
  const Fundo({
    required this.arquivo,
    required this.tema,
    required this.descricao,
  });

  final String arquivo;
  final String tema;
  final String descricao;

  String get asset => 'assets/fundos/$arquivo';

  factory Fundo.doMapa(Map<String, dynamic> m) => Fundo(
    arquivo: m['arquivo'] as String,
    tema: m['tema'] as String,
    descricao: m['descricao'] as String,
  );
}

/// Escolhe o fundo de um cartão de versículo pelo assunto do texto.
///
/// As 21 imagens vêm do próprio acervo — são fundos de projeção do LouvorJA,
/// do grupo `generico_*`, que são fotos neutras (os `hasd_*` pertencem a hinos
/// específicos). Foram recortadas em quadrado e etiquetadas à mão por tema.
///
/// A associação é por **palavra-chave no texto do versículo**. É uma
/// aproximação deliberadamente simples: não há classificador semântico aqui, e
/// fingir que há seria pior do que a heurística honesta. Quando nada casa, o
/// fundo é sorteado — e o usuário pode trocar com um toque, que é a garantia
/// real de que o cartão fica do jeito dele.
class Fundos {
  Fundos._();
  static final Fundos instancia = Fundos._();

  static const _manifesto = 'assets/fundos/fundos.json';

  List<Fundo>? _todos;

  /// Palavras que apontam para cada tema. Radicais curtos de propósito:
  /// "amor" alcança "amoroso", "ama", "amados".
  static const _pistas = <String, List<String>>{
    'luz': [
      'luz',
      'lâmpada',
      'lampada',
      'ilumin',
      'brilh',
      'resplandec',
      'clarid',
    ],
    'paz': [
      'paz',
      'descans',
      'tranquil',
      'sossego',
      'quieto',
      'repous',
      'consol',
    ],
    'forca': [
      'forç',
      'forc',
      'poder',
      'fortalec',
      'refúgio',
      'refugio',
      'rocha',
      'escudo',
      'vencer',
      'venci',
      'firme',
      'coragem',
      'águia',
      'aguia',
    ],
    'amor': [
      'amor',
      'ama',
      'amad',
      'misericórdia',
      'misericordia',
      'bondade',
      'coração',
      'coracao',
    ],
    'esperanca': [
      'esperanç',
      'esperanc',
      'espera',
      'promessa',
      'futuro',
      'alegr',
      'gozo',
    ],
    'caminho': [
      'caminh',
      'vereda',
      'passos',
      'guia',
      'condu',
      'and',
      'segu',
      'jornada',
    ],
    'criacao': [
      'céus',
      'ceus',
      'terra',
      'criou',
      'criação',
      'criacao',
      'estrela',
      'mar',
      'montanha',
      'sol',
      'obras',
    ],
    'oracao': ['ora', 'clam', 'súplica', 'suplica', 'invoc', 'busca', 'cham'],
    'louvor': [
      'louv',
      'adora',
      'cant',
      'exalt',
      'glória',
      'gloria',
      'aleluia',
      'celebr',
    ],
    'cuidado': [
      'pastor',
      'ovelha',
      'cuid',
      'sustent',
      'protege',
      'guard',
      'abrig',
    ],
  };

  Future<List<Fundo>> get todos async {
    final cache = _todos;
    if (cache != null) return cache;
    final texto = await rootBundle.loadString(_manifesto);
    final lista = (jsonDecode(texto) as List)
        .cast<Map<String, dynamic>>()
        .map(Fundo.doMapa)
        .toList();
    return _todos = lista;
  }

  /// Fundo sugerido para [texto].
  ///
  /// Conta quantas pistas de cada tema aparecem e fica com o tema mais forte.
  /// Empate ou nenhum acerto: sorteia entre todos.
  Future<Fundo> sugerir(String texto, {int? semente}) async {
    final lista = await todos;
    final t = texto.toLowerCase();

    var melhorTema = '';
    var melhorPontos = 0;
    _pistas.forEach((tema, pistas) {
      final pontos = pistas.where(t.contains).length;
      if (pontos > melhorPontos) {
        melhorPontos = pontos;
        melhorTema = tema;
      }
    });

    final candidatos = melhorPontos > 0
        ? lista.where((f) => f.tema == melhorTema).toList()
        : lista;
    final sorteio = Random(semente ?? texto.hashCode);
    return candidatos[sorteio.nextInt(candidatos.length)];
  }

  /// O próximo fundo da lista, para o usuário trocar com um toque.
  Future<Fundo> proximo(Fundo atual) async {
    final lista = await todos;
    final i = lista.indexWhere((f) => f.arquivo == atual.arquivo);
    return lista[(i + 1) % lista.length];
  }
}
