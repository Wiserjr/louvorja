import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'banco.dart';
import 'modelos.dart';

/// Um lugar bíblico (Bible Geocoding Data, de OpenBible.info).
class Lugar {
  const Lugar({
    required this.id,
    required this.nome,
    required this.tipo,
    required this.lon,
    required this.lat,
    required this.confianca,
    required this.versiculos,
  });

  final int id;
  final String nome;

  /// settlement, region, mountain, river, body of water...
  final String tipo;
  final double lon;
  final double lat;

  /// 0 a 1000: quão certa é a identificação do lugar antigo com o moderno.
  final int confianca;
  final int versiculos;

  bool get incerto => confianca < 300;

  bool get regiao =>
      tipo == 'region' || tipo == 'mountain range' || tipo == 'natural area';

  bool get agua =>
      tipo == 'river' ||
      tipo == 'body of water' ||
      tipo == 'spring' ||
      tipo == 'well';

  String get tipoLegivel => switch (tipo) {
    'settlement' => 'cidade ou povoado',
    'region' => 'região',
    'mountain' => 'monte',
    'mountain range' => 'cordilheira',
    'river' => 'rio',
    'valley' => 'vale',
    'island' => 'ilha',
    'hill' => 'colina',
    'body of water' => 'mar ou lago',
    'campsite' => 'acampamento',
    'spring' => 'fonte',
    'well' => 'poço',
    'natural area' => 'área natural',
    _ => 'lugar',
  };

  factory Lugar.deMapa(Map<String, Object?> m) => Lugar(
    id: m['id'] as int,
    nome: m['nome'] as String,
    tipo: m['tipo'] as String,
    lon: (m['lon'] as num).toDouble(),
    lat: (m['lat'] as num).toDouble(),
    confianca: m['confianca'] as int,
    versiculos: m['versiculos'] as int,
  );
}

class Rota {
  const Rota(this.nome, this.lugares);
  final String nome;
  final List<int> lugares;
}

class MapaTematico {
  const MapaTematico({
    required this.id,
    required this.titulo,
    required this.periodo,
    required this.descricao,
    required this.referencias,
    required this.lugares,
    required this.rotas,
  });

  final String id;
  final String titulo;
  final String? periodo;
  final String? descricao;
  final List<String> referencias;
  final List<int> lugares;
  final List<Rota> rotas;
}

/// Contornos simplificados (Natural Earth): cada parte é uma lista achatada
/// de coordenadas em centésimos de grau, `[lon, lat, lon, lat, ...]`.
class Geometria {
  const Geometria(this.terra, this.lagos, this.rios);
  final List<List<int>> terra;
  final List<List<int>> lagos;
  final List<List<int>> rios;
}

class Mapas {
  Mapas._();
  static final Mapas instancia = Mapas._();

  Database get _db => Banco.instancia.estudo;

  Geometria? _geometria;
  final _lugares = <int, Lugar>{};

  Future<Geometria> geometria() async {
    if (_geometria != null) return _geometria!;
    final rows = await _db.rawQuery('SELECT camada, dados FROM geometria');
    final porNome = {
      for (final r in rows) r['camada'] as String: r['dados'] as String,
    };
    List<List<int>> ler(String nome) => [
      for (final parte in jsonDecode(porNome[nome] ?? '[]') as List)
        (parte as List).cast<int>(),
    ];
    return _geometria = Geometria(ler('terra'), ler('lagos'), ler('rios'));
  }

  Future<List<Lugar>> lugares(Iterable<int> ids) async {
    final faltam = ids.where((i) => !_lugares.containsKey(i)).toList();
    if (faltam.isNotEmpty) {
      final rows = await _db.rawQuery(
        'SELECT * FROM lugar WHERE id IN (${faltam.join(',')})',
      );
      for (final r in rows) {
        final l = Lugar.deMapa(r);
        _lugares[l.id] = l;
      }
    }
    return [
      for (final i in ids)
        if (_lugares[i] != null) _lugares[i]!,
    ];
  }

  /// Lugares citados num versículo.
  Future<List<Lugar>> doVersiculo(int livro, int capitulo, int versiculo) =>
      _porSql(
        'SELECT l.* FROM lugar_ref r JOIN lugar l ON l.id = r.lugar '
        'WHERE r.livro = ? AND r.chave = ? ORDER BY l.versiculos DESC',
        [livro, chave(capitulo, versiculo)],
      );

  /// Lugares citados num capítulo, os mais citados na Bíblia primeiro.
  Future<List<Lugar>> doCapitulo(int livro, int capitulo) => _porSql(
    'SELECT DISTINCT l.* FROM lugar_ref r JOIN lugar l ON l.id = r.lugar '
    'WHERE r.livro = ? AND r.chave BETWEEN ? AND ? ORDER BY l.versiculos DESC',
    [livro, chave(capitulo, 0), chave(capitulo, 999)],
  );

  Future<List<Lugar>> _porSql(String sql, List<Object> args) async {
    final rows = await _db.rawQuery(sql, args);
    return [
      for (final r in rows)
        _lugares.putIfAbsent(r['id'] as int, () => Lugar.deMapa(r)),
    ];
  }

  /// Versículos onde o lugar aparece: (livro, capítulo, versículo).
  Future<List<(int, int, int)>> versiculos(int lugar) async {
    final rows = await _db.rawQuery(
      'SELECT livro, chave FROM lugar_ref WHERE lugar = ? '
      'ORDER BY livro, chave',
      [lugar],
    );
    return [
      for (final r in rows)
        (
          r['livro'] as int,
          (r['chave'] as int) ~/ 1000,
          (r['chave'] as int) % 1000,
        ),
    ];
  }

  /// Busca lugares pelo nome (sem diferença de acentos nem maiúsculas é
  /// feita na tela; aqui, LIKE simples).
  Future<List<Lugar>> buscar(String texto) => _porSql(
    'SELECT * FROM lugar WHERE nome LIKE ? ORDER BY versiculos DESC LIMIT 60',
    ['%$texto%'],
  );

  Future<List<MapaTematico>> tematicos() async {
    final rows = await _db.rawQuery('SELECT * FROM mapa ORDER BY ordem');
    return [
      for (final r in rows)
        MapaTematico(
          id: r['id'] as String,
          titulo: r['titulo'] as String,
          periodo: r['periodo'] as String?,
          descricao: r['descricao'] as String?,
          referencias: (jsonDecode(r['referencias'] as String? ?? '[]') as List)
              .cast<String>(),
          lugares: (jsonDecode(r['lugares'] as String) as List).cast<int>(),
          rotas: [
            for (final x in jsonDecode(r['rotas'] as String) as List)
              Rota(
                (x as Map)['nome'] as String,
                (x['lugares'] as List).cast<int>(),
              ),
          ],
        ),
    ];
  }
}
