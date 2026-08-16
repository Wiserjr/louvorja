import '../dados/modelos.dart';

/// Decide qual slide da letra deve estar na tela em cada instante da música.
///
/// Os slides chegam já filtrados (`exibe_slide = 1`) e ordenados, e cada um traz
/// o instante **absoluto** em que entra. Um exemplo real do acervo:
///
///     slides[0].ms =  8000  "O nosso sol / Veio iluminar"
///     slides[1].ms = 17000  "O caminho que / vamos andar"
///     slides[2].ms = 25000  "Quero sempre viver / Com essa Grande Luz"
///
/// O primeiro verso só entra aos 8 segundos porque existe uma introdução
/// instrumental antes dele.
class Sincronizador {
  Sincronizador(this.slides, {this.usarTemposPlayback = false});

  /// Slides exibíveis, em ordem crescente de tempo.
  final List<Slide> slides;

  /// Faixas instrumentais podem ter tempos próprios; quando não têm, a geração
  /// do banco já copiou os tempos normais para `msPlayback`.
  final bool usarTemposPlayback;

  int msDe(Slide s) => usarTemposPlayback ? s.msPlayback : s.ms;

  bool get vazio => slides.isEmpty;

  /// Índice do slide que deve estar visível em [posicao], ou `null` para
  /// "nenhum slide na tela".
  ///
  /// O comportamento segue o do LouvorJA desktop na projeção:
  ///
  /// - **Durante a introdução instrumental**, nada na tela. O acervo deixa isso
  ///   explícito: nenhum slide exibível tem `ms = 0`, então o intervalo antes do
  ///   primeiro verso é intencional, não ausência de dado.
  /// - **Entre um verso e o seguinte**, o verso atual permanece. Não é preciso
  ///   arbitrar um tempo para limpar a tela: quando o acervo quer a projeção
  ///   limpa, ele traz um slide de texto vazio com horário próprio — são 2.567
  ///   deles. Esse caso não precisa de tratamento especial aqui; o slide é
  ///   devolvido normalmente e a tela fica em branco porque o texto é vazio.
  /// - **Depois do último verso**, ele permanece até a música acabar, pela mesma
  ///   razão: se fosse para limpar, haveria um slide vazio no fim.
  ///
  /// A varredura é de trás para frente porque o slide procurado é quase sempre
  /// um dos últimos avaliados numa reprodução em andamento. A lista raramente
  /// passa de 40 itens e isso roda algumas vezes por segundo, então busca
  /// binária resolveria o mesmo sem ganho perceptível — e leria pior.
  int? indiceEm(Duration posicao) {
    final ms = posicao.inMilliseconds;
    for (var i = slides.length - 1; i >= 0; i--) {
      if (msDe(slides[i]) <= ms) return i;
    }
    return null;
  }

  /// Conveniência para a UI: o slide em si, já resolvido.
  Slide? slideEm(Duration posicao) {
    final i = indiceEm(posicao);
    return (i == null || i < 0 || i >= slides.length) ? null : slides[i];
  }

  /// Instante em que o slide [indice] sai de cena — usado para animar a
  /// transição e para a barra de progresso do verso atual.
  Duration? fimDoSlide(int indice) => indice + 1 < slides.length
      ? Duration(milliseconds: msDe(slides[indice + 1]))
      : null;

  /// Índice do slide seguinte, para o modo de projeção que mostra "o que vem".
  int? proximoIndice(Duration posicao) {
    final atual = indiceEm(posicao);
    final prox = (atual == null) ? 0 : atual + 1;
    return prox < slides.length ? prox : null;
  }
}
