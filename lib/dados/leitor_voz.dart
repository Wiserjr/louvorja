import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'modelos.dart';

/// Lê passagens em voz alta, pela síntese do próprio Android.
///
/// A alternativa seria uma Bíblia em áudio gravada, mas nenhuma existe no
/// acervo e as disponíveis no mercado são licenciadas. A síntese resolve o
/// problema real — quem tem dificuldade de ler no celular — e resolve para as
/// **dez traduções**, não só para a que alguém gravou.
///
/// A leitura é feita versículo a versículo, e não com o capítulo inteiro numa
/// tirada só: é o que permite acompanhar na tela qual está sendo lido, retomar
/// de onde parou e parar sem esperar o fim.
class LeitorVoz {
  LeitorVoz._();
  static final LeitorVoz instancia = LeitorVoz._();

  final _tts = FlutterTts();
  bool _iniciado = false;

  /// Índice do versículo sendo lido, para a tela destacar.
  final versoAtual = ValueNotifier<int?>(null);
  final lendo = ValueNotifier<bool>(false);

  /// 0,5 é o "normal" do motor Android; abaixo disso fica arrastado.
  double velocidade = 0.5;

  Future<void> _preparar() async {
    if (_iniciado) return;
    await _tts.setLanguage('pt-BR');
    await _tts.setSpeechRate(velocidade);
    await _tts.setVolume(1);
    await _tts.setPitch(1);
    // Sem isto, `speak` retorna imediatamente e a leitura vira uma avalanche de
    // versículos falados por cima uns dos outros.
    await _tts.awaitSpeakCompletion(true);
    _iniciado = true;
  }

  /// Há voz em português instalada?
  ///
  /// Vale checar antes de oferecer o recurso: em aparelhos sem o pacote de voz,
  /// `speak` falha em silêncio e o usuário fica sem entender por que nada toca.
  Future<bool> temVozPortuguesa() async {
    try {
      final linguas = await _tts.getLanguages as List<dynamic>?;
      if (linguas == null) return false;
      return linguas.any((l) => l.toString().toLowerCase().startsWith('pt'));
    } on Exception {
      return false;
    }
  }

  Future<void> definirVelocidade(double v) async {
    velocidade = v.clamp(0.25, 1.0);
    if (_iniciado) await _tts.setSpeechRate(velocidade);
  }

  /// Lê a lista a partir de [inicio]. Retorna quando termina ou é interrompida.
  Future<void> ler(List<Versiculo> versos, {int inicio = 0}) async {
    await _preparar();
    lendo.value = true;
    for (var i = inicio; i < versos.length; i++) {
      if (!lendo.value) break;
      versoAtual.value = i;
      // O número do versículo é dito antes do texto, como numa leitura pública.
      await _tts.speak('${versos[i].numero}. ${versos[i].texto}');
    }
    if (lendo.value) {
      versoAtual.value = null;
      lendo.value = false;
    }
  }

  Future<void> parar() async {
    lendo.value = false;
    versoAtual.value = null;
    await _tts.stop();
  }
}
