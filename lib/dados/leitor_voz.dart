import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'modelos.dart';

/// Uma voz instalada no aparelho.
class Voz {
  const Voz({required this.nome, required this.locale, this.motor});

  final String nome;
  final String locale;
  final String? motor;

  /// Vozes `network` são sintetizadas no servidor do Google: bem mais naturais,
  /// porém dependentes de internet. As `local` rodam no aparelho, funcionam sem
  /// conexão e soam mais sintéticas.
  ///
  /// É um trade-off, não um ranking — por isso a interface mostra qual é qual em
  /// vez de eleger uma "melhor".
  bool get deRede => nome.toLowerCase().contains('network');

  bool get doAparelho => nome.toLowerCase().contains('local');

  /// pt-BR antes de pt-PT: o acervo é brasileiro.
  bool get ehBrasil => locale.toLowerCase().startsWith('pt-br');

  String get rotulo => deRede
      ? 'rede'
      : doAparelho
      ? 'offline'
      : '';

  Map<String, String> get mapa => {'name': nome, 'locale': locale};

  @override
  String toString() => nome;
}

/// Lê passagens em voz alta pela síntese do aparelho.
///
/// A qualidade da síntese no Android depende quase inteiramente de **qual motor
/// e qual voz** estão em uso — o motor da fabricante costuma soar metálico,
/// enquanto o Google TTS com voz de rede é bem natural. A primeira versão deste
/// leitor não dava escolha e usava o padrão do sistema; era essa a causa do som
/// ruim, não a síntese em si.
///
/// Duas outras correções vieram junto: o número do versículo deixou de ser
/// falado por padrão (dizer "um ponto" antes de cada frase quebra a leitura), e
/// os versículos são emendados em blocos, para as frases fluírem em vez de
/// pararem a cada ponto final.
class LeitorVoz {
  LeitorVoz._();
  static final LeitorVoz instancia = LeitorVoz._();

  static const _chaveMotor = 'tts_motor';
  static const _chaveVoz = 'tts_voz';
  static const _chaveLocale = 'tts_locale';
  static const _chaveVelocidade = 'tts_velocidade';
  static const _chaveNumeros = 'tts_numeros';

  final _tts = FlutterTts();
  bool _iniciado = false;

  /// Índice do versículo sendo lido, para a tela destacar.
  final versoAtual = ValueNotifier<int?>(null);
  final lendo = ValueNotifier<bool>(false);

  double velocidade = 0.45;
  bool dizerNumeros = false;
  String? motorEscolhido;
  Voz? vozEscolhida;

  Future<void> _preparar() async {
    if (_iniciado) return;
    final prefs = await SharedPreferences.getInstance();

    velocidade = prefs.getDouble(_chaveVelocidade) ?? 0.45;
    dizerNumeros = prefs.getBool(_chaveNumeros) ?? false;
    motorEscolhido = prefs.getString(_chaveMotor);
    final nomeVoz = prefs.getString(_chaveVoz);
    final locale = prefs.getString(_chaveLocale);

    if (motorEscolhido != null) {
      try {
        await _tts.setEngine(motorEscolhido!);
      } on Exception {
        motorEscolhido = null;
      }
    }
    await _tts.setLanguage(locale ?? 'pt-BR');
    if (nomeVoz != null && locale != null) {
      vozEscolhida = Voz(nome: nomeVoz, locale: locale);
      try {
        await _tts.setVoice(vozEscolhida!.mapa);
      } on Exception {
        vozEscolhida = null;
      }
    }
    await _tts.setSpeechRate(velocidade);
    await _tts.setVolume(1);
    await _tts.setPitch(1);
    // Sem isto, `speak` retorna na hora e a leitura vira uma avalanche de
    // trechos falados por cima uns dos outros.
    await _tts.awaitSpeakCompletion(true);
    _iniciado = true;
  }

  /// Recomeça do zero na próxima leitura — usado quando o usuário troca de voz.
  void _reiniciar() => _iniciado = false;

  // ------------------------------------------------------------- disponíveis

  Future<List<String>> motores() async {
    try {
      final lista = await _tts.getEngines as List<dynamic>?;
      return lista?.map((e) => e.toString()).toList() ?? const [];
    } on Exception {
      return const [];
    }
  }

  /// Vozes em português instaladas, as de melhor qualidade primeiro.
  Future<List<Voz>> vozesPortuguesas() async {
    try {
      final lista = await _tts.getVoices as List<dynamic>?;
      if (lista == null) return const [];
      final vozes = <Voz>[];
      for (final v in lista) {
        if (v is! Map) continue;
        final locale = (v['locale'] ?? '').toString();
        if (!locale.toLowerCase().startsWith('pt')) continue;
        vozes.add(Voz(nome: (v['name'] ?? '').toString(), locale: locale));
      }
      // Brasil antes de Portugal, e dentro de cada grupo as de rede primeiro,
      // que são as mais naturais.
      vozes.sort((a, b) {
        if (a.ehBrasil != b.ehBrasil) return a.ehBrasil ? -1 : 1;
        if (a.deRede != b.deRede) return a.deRede ? -1 : 1;
        return a.nome.compareTo(b.nome);
      });
      return vozes;
    } on Exception {
      return const [];
    }
  }

  Future<bool> temVozPortuguesa() async =>
      (await vozesPortuguesas()).isNotEmpty;

  // --------------------------------------------------------------- ajustes

  Future<void> escolherMotor(String motor) async {
    await parar();
    motorEscolhido = motor;
    (await SharedPreferences.getInstance()).setString(_chaveMotor, motor);
    // Trocar de motor invalida a voz: os nomes não são compartilhados entre
    // motores diferentes.
    vozEscolhida = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_chaveVoz);
    await prefs.remove(_chaveLocale);
    _reiniciar();
  }

  Future<void> escolherVoz(Voz voz) async {
    await parar();
    vozEscolhida = voz;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chaveVoz, voz.nome);
    await prefs.setString(_chaveLocale, voz.locale);
    _reiniciar();
  }

  Future<void> definirVelocidade(double v) async {
    velocidade = v.clamp(0.2, 1.0);
    (await SharedPreferences.getInstance()).setDouble(
      _chaveVelocidade,
      velocidade,
    );
    if (_iniciado) await _tts.setSpeechRate(velocidade);
  }

  Future<void> definirNumeros(bool valor) async {
    dizerNumeros = valor;
    (await SharedPreferences.getInstance()).setBool(_chaveNumeros, valor);
  }

  /// Fala uma frase curta para o usuário comparar vozes.
  Future<void> experimentar() async {
    await parar();
    await _preparar();
    await _tts.speak(
      'O Senhor é o meu pastor; nada me faltará. '
      'Assim soa esta voz na leitura da Bíblia.',
    );
  }

  // --------------------------------------------------------------- leitura

  /// Junta versículos em blocos para a fala não parar a cada ponto final.
  ///
  /// Sem isso o motor encerra a locução em cada versículo e insere um silêncio
  /// de respiração — o que, num capítulo de trinta versos, soa entrecortado.
  /// Os blocos ficam em torno de 350 caracteres: grandes o bastante para fluir,
  /// pequenos o bastante para o destaque na tela continuar acompanhando.
  static List<({int inicio, String texto})> _blocos(
    List<Versiculo> versos, {
    required bool comNumeros,
    int inicio = 0,
  }) {
    final blocos = <({int inicio, String texto})>[];
    final buffer = StringBuffer();
    var primeiro = inicio;

    for (var i = inicio; i < versos.length; i++) {
      if (buffer.isNotEmpty) buffer.write(' ');
      if (comNumeros) buffer.write('${versos[i].numero}. ');
      buffer.write(versos[i].texto.trim());

      if (buffer.length >= 350 || i == versos.length - 1) {
        blocos.add((inicio: primeiro, texto: buffer.toString()));
        buffer.clear();
        primeiro = i + 1;
      }
    }
    return blocos;
  }

  Future<void> ler(List<Versiculo> versos, {int inicio = 0}) async {
    await _preparar();
    lendo.value = true;
    for (final bloco in _blocos(
      versos,
      comNumeros: dizerNumeros,
      inicio: inicio,
    )) {
      if (!lendo.value) break;
      versoAtual.value = bloco.inicio;
      await _tts.speak(bloco.texto);
    }
    if (lendo.value) {
      versoAtual.value = null;
      lendo.value = false;
    }
  }

  Future<void> parar() async {
    lendo.value = false;
    versoAtual.value = null;
    try {
      await _tts.stop();
    } on Exception {
      // motor pode nem ter iniciado
    }
  }
}
