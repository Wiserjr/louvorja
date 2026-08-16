/// Modelos do domínio, espelhando o banco enxuto gerado a partir do LouvorJA.
///
/// Os caminhos de mídia (`audio`, `imagem`, `capa`) são **relativos** à pasta
/// que o usuário escolher no aparelho — nunca absolutos. É isso que permite o
/// mesmo banco funcionar em qualquer celular, com a mídia onde couber.
library;

import 'dart:typed_data';

/// Uma categoria do acervo: CDs Oficiais/Ano, Adoradores, Doxologia, os dois
/// hinários... `tipo` vale 'hymnal' para os hinários, 'collection' para as
/// coletâneas e é nulo para Doxologia e Infantis.
class Categoria {
  const Categoria({
    required this.id,
    required this.nome,
    required this.slug,
    this.tipo,
    this.ordem = 0,
  });

  final int id;
  final String nome;
  final String slug;
  final String? tipo;
  final int ordem;

  bool get eHinario => tipo == 'hymnal';

  factory Categoria.doMapa(Map<String, Object?> m) => Categoria(
    id: m['id']! as int,
    nome: m['nome']! as String,
    slug: m['slug']! as String,
    tipo: m['tipo'] as String?,
    ordem: (m['ordem'] as int?) ?? 0,
  );
}

class Album {
  const Album({
    required this.id,
    required this.nome,
    this.cor,
    this.capa,
    this.ordem,
    this.totalMusicas = 0,
    this.subtitulo,
  });

  final int id;
  final String nome;
  final String? cor;
  final String? capa;
  final int? ordem;
  final int totalMusicas;

  /// Texto que o programa original exibe abaixo do nome. Nos CDs oficiais é o
  /// ano do álbum.
  final String? subtitulo;

  /// Capa embutida no APK (73 arquivos WebP, ~292 KB no total).
  String get assetCapa => 'assets/capas/$id.webp';

  factory Album.doMapa(Map<String, Object?> m) => Album(
    id: m['id']! as int,
    nome: m['nome']! as String,
    cor: m['cor'] as String?,
    capa: m['capa'] as String?,
    ordem: m['ordem'] as int?,
    totalMusicas: (m['total_musicas'] as int?) ?? 0,
    subtitulo: m['subtitulo'] as String?,
  );
}

class Musica {
  const Musica({
    required this.id,
    required this.nome,
    this.audio,
    this.audioPlayback,
    this.imagem,
    this.audioBytes,
    this.temLetra = false,
    this.faixa,
    this.duracaoMs,
    this.idAlbum,
    this.albumNome,
  });

  final int id;
  final String nome;

  /// Caminho relativo do MP3, ex.: `musicas/1992 - Brilha Jesus/Brilha Jesus.mp3`
  final String? audio;

  /// Faixa instrumental (playback), quando existe.
  final String? audioPlayback;
  final String? imagem;
  final int? audioBytes;
  final bool temLetra;
  final int? faixa;

  /// Duração informada pelo catálogo (o esquema 26.9 passou a trazê-la), em
  /// milissegundos. Permite mostrar o tempo antes mesmo de o áudio existir.
  final int? duracaoMs;

  /// Álbum de origem. Preenchido na busca global, onde a faixa aparece fora do
  /// contexto do seu álbum e precisa dizer de onde veio.
  final int? idAlbum;
  final String? albumNome;

  factory Musica.doMapa(Map<String, Object?> m) => Musica(
    id: m['id']! as int,
    nome: m['nome']! as String,
    audio: m['audio'] as String?,
    audioPlayback: m['audio_pb'] as String?,
    imagem: m['imagem'] as String?,
    audioBytes: m['audio_bytes'] as int?,
    temLetra: (m['tem_letra'] as int? ?? 0) == 1,
    faixa: m['faixa'] as int?,
    duracaoMs: m['duracao_ms'] as int?,
    idAlbum: m['id_album'] as int?,
    albumNome: m['album_nome'] as String?,
  );
}

/// Uma linha da letra posicionada no tempo.
///
/// `ms` é o instante **absoluto** em que o slide entra, já convertido de
/// `'00:01:23'` para inteiro na geração do banco — o player não faz parse de
/// texto durante a reprodução.
class Slide {
  const Slide({
    required this.id,
    required this.ordem,
    required this.texto,
    required this.ms,
    required this.msPlayback,
    this.textoAux,
    this.imagem,
  });

  final int id;
  final int ordem;
  final String texto;
  final String? textoAux;
  final String? imagem;
  final int ms;

  /// Alguns arranjos instrumentais têm tempos próprios; quando não têm,
  /// a geração do banco já repetiu o valor de [ms] aqui.
  final int msPlayback;

  List<String> get linhas => texto.split(RegExp(r'\r?\n'));

  factory Slide.doMapa(Map<String, Object?> m) => Slide(
    id: m['id']! as int,
    ordem: m['ordem']! as int,
    texto: m['texto']! as String,
    textoAux: m['texto_aux'] as String?,
    imagem: m['imagem'] as String?,
    ms: m['ms']! as int,
    msPlayback: m['ms_pb']! as int,
  );
}

class Versiculo {
  const Versiculo({
    required this.livro,
    required this.capitulo,
    required this.numero,
    required this.texto,
  });

  final String livro;
  final int capitulo;
  final int numero;
  final String texto;

  String get referencia => '$livro $capitulo:$numero';

  factory Versiculo.doMapa(Map<String, Object?> m) => Versiculo(
    livro: m['livro']! as String,
    capitulo: m['capitulo']! as int,
    numero: m['versiculo']! as int,
    texto: m['texto']! as String,
  );
}

/// Canal de vídeos das coletâneas on-line.
///
/// As miniaturas vêm embutidas no catálogo como bytes — o programa original já
/// as guardava em base64 —, então a navegação funciona sem rede. Só a
/// reprodução do vídeo em si exige conexão.
class Canal {
  const Canal({
    required this.id,
    required this.nome,
    this.url,
    this.thumb,
    this.totalPlaylists = 0,
  });

  final int id;
  final String nome;
  final String? url;
  final Uint8List? thumb;
  final int totalPlaylists;

  factory Canal.doMapa(Map<String, Object?> m) => Canal(
    id: m['id']! as int,
    nome: m['nome']! as String,
    url: m['url'] as String?,
    thumb: m['thumb'] as Uint8List?,
    totalPlaylists: (m['total'] as int?) ?? 0,
  );
}

class PlaylistOnline {
  const PlaylistOnline({
    required this.id,
    required this.nome,
    this.thumb,
    this.totalVideos = 0,
    this.canalNome,
  });

  final int id;
  final String nome;
  final Uint8List? thumb;
  final int totalVideos;
  final String? canalNome;

  factory PlaylistOnline.doMapa(Map<String, Object?> m) => PlaylistOnline(
    id: m['id']! as int,
    nome: m['nome']! as String,
    thumb: m['thumb'] as Uint8List?,
    totalVideos: (m['total'] as int?) ?? 0,
    canalNome: m['canal_nome'] as String?,
  );
}

class VideoOnline {
  const VideoOnline({
    required this.id,
    required this.videoId,
    required this.nome,
    this.ordem = 0,
    this.thumb,
  });

  final int id;

  /// Identificador do YouTube, o que o player precisa.
  final String videoId;
  final String nome;
  final int ordem;
  final Uint8List? thumb;

  factory VideoOnline.doMapa(Map<String, Object?> m) => VideoOnline(
    id: m['id']! as int,
    videoId: m['video_id']! as String,
    nome: m['nome']! as String,
    ordem: (m['ordem'] as int?) ?? 0,
    thumb: m['thumb'] as Uint8List?,
  );
}
