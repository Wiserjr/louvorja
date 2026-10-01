import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../dados/mapas.dart';

/// Uma rota do mapa, já com os lugares resolvidos.
class RotaVista {
  const RotaVista(this.nome, this.lugares, this.cor);
  final String nome;
  final List<Lugar> lugares;
  final Color cor;
}

/// Cores das rotas, distintas entre si nos dois temas.
const coresRotas = <Color>[
  Color(0xFFC62828),
  Color(0xFF1565C0),
  Color(0xFF2E7D32),
  Color(0xFF6A1B9A),
  Color(0xFFEF6C00),
];

/// Mapa vetorial do mundo bíblico, desenhado no aparelho: sem servidor de
/// mapas e sem internet. Contornos do Natural Earth, lugares do OpenBible.
///
/// Arraste para mover; pinça, roda do mouse ou toque duplo para aproximar.
class VistaMapa extends StatefulWidget {
  const VistaMapa({
    super.key,
    required this.geometria,
    required this.lugares,
    this.rotas = const [],
    this.destaque = const {},
    this.aoTocarLugar,
    this.interativo = true,
    this.margem = 0.25,
    this.vizinhanca = 1.6,
  });

  final Geometria geometria;
  final List<Lugar> lugares;
  final List<RotaVista> rotas;

  /// Lugares em evidência (ponto maior, rótulo sempre visível).
  final Set<int> destaque;
  final ValueChanged<Lugar>? aoTocarLugar;
  final bool interativo;

  /// Folga em volta dos lugares no enquadramento inicial, em fração da área.
  final double margem;

  /// Menor extensão mostrada, em graus, quando os lugares estão muito
  /// próximos (ou é um só).
  final double vizinhanca;

  @override
  State<VistaMapa> createState() => _VistaMapaState();
}

class _VistaMapaState extends State<VistaMapa> {
  /// Centro da vista (lon, lat) e escala em pixels por grau de latitude.
  Offset? _centro;
  double? _escala;
  Size _tamanho = Size.zero;

  Offset _centroInicial = Offset.zero;
  double _escalaInicial = 1;

  // Gesto em andamento.
  Offset _centroGesto = Offset.zero;
  double _escalaGesto = 1;
  Offset _focoGesto = Offset.zero;

  @override
  void didUpdateWidget(VistaMapa antigo) {
    super.didUpdateWidget(antigo);
    if (!identical(antigo.lugares, widget.lugares)) {
      _centro = null;
      _escala = null;
    }
  }

  void _enquadrar(Size tamanho) {
    final pontos = widget.lugares.isEmpty
        ? const [Offset(35.2, 31.8)]
        : [for (final l in widget.lugares) Offset(l.lon, l.lat)];
    var minLon = pontos.map((p) => p.dx).reduce(math.min);
    var maxLon = pontos.map((p) => p.dx).reduce(math.max);
    var minLat = pontos.map((p) => p.dy).reduce(math.min);
    var maxLat = pontos.map((p) => p.dy).reduce(math.max);
    // Um lugar só (ou lugares muito próximos): mostra a vizinhança.
    final minimo = widget.vizinhanca;
    if (maxLon - minLon < minimo) {
      final c = (maxLon + minLon) / 2;
      minLon = c - minimo / 2;
      maxLon = c + minimo / 2;
    }
    if (maxLat - minLat < minimo) {
      final c = (maxLat + minLat) / 2;
      minLat = c - minimo / 2;
      maxLat = c + minimo / 2;
    }
    final dLon = (maxLon - minLon) * (1 + widget.margem * 2);
    final dLat = (maxLat - minLat) * (1 + widget.margem * 2);
    final c = Offset((minLon + maxLon) / 2, (minLat + maxLat) / 2);
    final k = math.min(tamanho.width / (dLon * _cosLat), tamanho.height / dLat);
    _centro = _centroInicial = c;
    _escala = _escalaInicial = k;
  }

  /// Projeção equirretangular com o fator de 33°N (o centro do mundo bíblico):
  /// fixo, para o mapa não se deformar enquanto se arrasta.
  static final _cosLat = math.cos(33 * math.pi / 180);

  Offset _paraTela(double lon, double lat) {
    final c = _centro!, k = _escala!;
    return Offset(
      (lon - c.dx) * k * _cosLat + _tamanho.width / 2,
      (c.dy - lat) * k + _tamanho.height / 2,
    );
  }

  Offset _paraGeo(Offset p) {
    final c = _centro!, k = _escala!;
    return Offset(
      c.dx + (p.dx - _tamanho.width / 2) / (k * _cosLat),
      c.dy - (p.dy - _tamanho.height / 2) / k,
    );
  }

  void _zoom(double fator, Offset foco) {
    final antes = _paraGeo(foco);
    final k = (_escala! * fator).clamp(_escalaInicial / 8, 4000.0);
    setState(() {
      _escala = k;
      // Mantém o ponto sob o dedo/cursor no mesmo lugar.
      final depois = _paraGeo(foco);
      _centro = _centro! + (antes - depois);
    });
  }

  Lugar? _lugarEm(Offset p) {
    Lugar? melhor;
    var dist = 22.0;
    for (final l in widget.lugares) {
      final d = (_paraTela(l.lon, l.lat) - p).distance;
      if (d < dist) {
        dist = d;
        melhor = l;
      }
    }
    return melhor;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final escuro = t.brightness == Brightness.dark;
    final cores = _CoresMapa(
      mar: escuro ? const Color(0xFF1B2A3A) : const Color(0xFFCFE3EE),
      terra: escuro ? const Color(0xFF2E2C27) : const Color(0xFFF1EBDD),
      costa: escuro ? const Color(0xFF5C574C) : const Color(0xFFB9AE95),
      rio: escuro ? const Color(0xFF4F7FA6) : const Color(0xFF6FA3C8),
      texto: escuro ? const Color(0xFFECE6DA) : const Color(0xFF2B2A28),
      halo: escuro ? const Color(0xFF2E2C27) : const Color(0xFFFFFBF2),
      ponto: escuro ? const Color(0xFFD7CCC8) : const Color(0xFF4E4A44),
      destaque: t.colorScheme.primary,
      regiao: escuro ? const Color(0xFFBCAAA4) : const Color(0xFF8D6E63),
    );
    return LayoutBuilder(
      builder: (context, restricoes) {
        final tamanho = Size(restricoes.maxWidth, restricoes.maxHeight);
        if (_centro == null || _tamanho != tamanho) {
          final primeira = _centro == null;
          _tamanho = tamanho;
          if (primeira) _enquadrar(tamanho);
        }
        Widget mapa = CustomPaint(
          size: tamanho,
          painter: _PintorMapa(
            geometria: widget.geometria,
            lugares: widget.lugares,
            rotas: widget.rotas,
            destaque: widget.destaque,
            paraTela: _paraTela,
            centro: _centro!,
            escala: _escala!,
            cosLat: _cosLat,
            tamanho: tamanho,
            cores: cores,
          ),
        );
        if (!widget.interativo) {
          return GestureDetector(
            onTapUp: widget.aoTocarLugar == null
                ? null
                : (d) {
                    final l = _lugarEm(d.localPosition);
                    if (l != null) widget.aoTocarLugar!(l);
                  },
            child: ClipRect(child: mapa),
          );
        }
        return Listener(
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) {
              _zoom(e.scrollDelta.dy < 0 ? 1.2 : 1 / 1.2, e.localPosition);
            }
          },
          child: GestureDetector(
            onScaleStart: (d) {
              _centroGesto = _centro!;
              _escalaGesto = _escala!;
              _focoGesto = d.localFocalPoint;
            },
            onScaleUpdate: (d) {
              setState(() {
                final k = (_escalaGesto * d.scale).clamp(
                  _escalaInicial / 8,
                  4000.0,
                );
                _escala = k;
                // Arrastar move o centro no sentido contrário ao dedo.
                final delta = d.localFocalPoint - _focoGesto;
                _centro = Offset(
                  _centroGesto.dx - delta.dx / (k * _cosLat),
                  _centroGesto.dy + delta.dy / k,
                );
              });
            },
            onDoubleTapDown: (d) => _focoGesto = d.localPosition,
            onDoubleTap: () => _zoom(2, _focoGesto),
            onTapUp: (d) {
              final l = _lugarEm(d.localPosition);
              if (l != null) widget.aoTocarLugar?.call(l);
            },
            child: Stack(
              children: [
                ClipRect(child: mapa),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _BotaoMapa(
                        icone: Icons.add,
                        dica: 'Aproximar',
                        aoTocar: () => _zoom(
                          1.6,
                          Offset(tamanho.width / 2, tamanho.height / 2),
                        ),
                      ),
                      const SizedBox(height: 6),
                      _BotaoMapa(
                        icone: Icons.remove,
                        dica: 'Afastar',
                        aoTocar: () => _zoom(
                          1 / 1.6,
                          Offset(tamanho.width / 2, tamanho.height / 2),
                        ),
                      ),
                      const SizedBox(height: 6),
                      _BotaoMapa(
                        icone: Icons.center_focus_strong,
                        dica: 'Enquadrar',
                        aoTocar: () => setState(() {
                          _centro = _centroInicial;
                          _escala = _escalaInicial;
                        }),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BotaoMapa extends StatelessWidget {
  const _BotaoMapa({
    required this.icone,
    required this.dica,
    required this.aoTocar,
  });
  final IconData icone;
  final String dica;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Material(
      color: t.colorScheme.surface.withValues(alpha: 0.9),
      shape: const CircleBorder(),
      elevation: 1,
      child: IconButton(
        tooltip: dica,
        visualDensity: VisualDensity.compact,
        icon: Icon(icone, size: 20),
        onPressed: aoTocar,
      ),
    );
  }
}

class _CoresMapa {
  const _CoresMapa({
    required this.mar,
    required this.terra,
    required this.costa,
    required this.rio,
    required this.texto,
    required this.halo,
    required this.ponto,
    required this.destaque,
    required this.regiao,
  });
  final Color mar, terra, costa, rio, texto, halo, ponto, destaque, regiao;
}

/// Os caminhos das camadas, em graus, montados uma vez por geometria.
final _cacheCaminhos = Expando<List<Path>>();

List<Path> _caminhos(Geometria g) {
  final pronto = _cacheCaminhos[g];
  if (pronto != null) return pronto;
  Path montar(List<List<int>> partes, {required bool fechar}) {
    final p = Path();
    for (final parte in partes) {
      if (parte.length < 4) continue;
      // y negativo: latitude cresce para cima, a tela para baixo.
      p.moveTo(parte[0] / 100, -parte[1] / 100);
      for (var i = 2; i + 1 < parte.length; i += 2) {
        p.lineTo(parte[i] / 100, -parte[i + 1] / 100);
      }
      if (fechar) p.close();
    }
    return p;
  }

  return _cacheCaminhos[g] = [
    montar(g.terra, fechar: true),
    montar(g.lagos, fechar: true),
    montar(g.rios, fechar: false),
  ];
}

class _PintorMapa extends CustomPainter {
  _PintorMapa({
    required this.geometria,
    required this.lugares,
    required this.rotas,
    required this.destaque,
    required this.paraTela,
    required this.centro,
    required this.escala,
    required this.cosLat,
    required this.tamanho,
    required this.cores,
  });

  final Geometria geometria;
  final List<Lugar> lugares;
  final List<RotaVista> rotas;
  final Set<int> destaque;
  final Offset Function(double lon, double lat) paraTela;
  final Offset centro;
  final double escala;
  final double cosLat;
  final Size tamanho;
  final _CoresMapa cores;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = cores.mar);

    // Camadas físicas: desenhadas em graus com a transformação no canvas.
    final [terra, lagos, rios] = _caminhos(geometria);
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(escala * cosLat, escala);
    canvas.translate(-centro.dx, centro.dy);
    final px = 1 / escala; // um pixel em graus (aprox.)
    canvas.drawPath(terra, Paint()..color = cores.terra);
    canvas.drawPath(
      terra,
      Paint()
        ..color = cores.costa
        ..style = PaintingStyle.stroke
        ..strokeWidth = px * 0.8,
    );
    canvas.drawPath(lagos, Paint()..color = cores.mar);
    canvas.drawPath(
      rios,
      Paint()
        ..color = cores.rio
        ..style = PaintingStyle.stroke
        ..strokeWidth = px * 1.4
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();

    _desenharRotas(canvas);
    _desenharLugares(canvas, size);
  }

  void _desenharRotas(Canvas canvas) {
    for (final r in rotas) {
      if (r.lugares.length < 2) continue;
      final pts = [for (final l in r.lugares) paraTela(l.lon, l.lat)];
      final caminho = Path()..moveTo(pts[0].dx, pts[0].dy);
      for (final p in pts.skip(1)) {
        caminho.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        caminho,
        Paint()
          ..color = cores.halo.withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.drawPath(
        caminho,
        Paint()
          ..color = r.cor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeJoin = StrokeJoin.round,
      );
      // Seta no meio de cada trecho, indicando o sentido.
      for (var i = 0; i + 1 < pts.length; i++) {
        final a = pts[i], b = pts[i + 1];
        final d = b - a;
        if (d.distance < 28) continue;
        final meio = a + d / 2;
        final ang = math.atan2(d.dy, d.dx);
        const tam = 7.0;
        final seta = Path()
          ..moveTo(meio.dx + math.cos(ang) * tam, meio.dy + math.sin(ang) * tam)
          ..lineTo(
            meio.dx + math.cos(ang + 2.5) * tam,
            meio.dy + math.sin(ang + 2.5) * tam,
          )
          ..lineTo(
            meio.dx + math.cos(ang - 2.5) * tam,
            meio.dy + math.sin(ang - 2.5) * tam,
          )
          ..close();
        canvas.drawPath(seta, Paint()..color = r.cor);
      }
    }
  }

  void _desenharLugares(Canvas canvas, Size size) {
    // Ordem de prioridade dos rótulos: destaque, depois os mais citados.
    final ordem = [...lugares]
      ..sort((a, b) {
        final da = destaque.contains(a.id) ? 0 : 1;
        final db = destaque.contains(b.id) ? 0 : 1;
        if (da != db) return da.compareTo(db);
        return b.versiculos.compareTo(a.versiculos);
      });
    final ocupados = <Rect>[];
    final tela = Offset.zero & size;

    // Pontos primeiro (todos), rótulos depois (sem sobreposição).
    for (final l in ordem.reversed) {
      if (l.regiao) continue;
      final p = paraTela(l.lon, l.lat);
      if (!tela.inflate(10).contains(p)) continue;
      final emDestaque = destaque.contains(l.id);
      final raio = emDestaque ? 5.5 : 3.5;
      final cor = emDestaque ? cores.destaque : cores.ponto;
      canvas.drawCircle(p, raio + 1.5, Paint()..color = cores.halo);
      if (l.incerto) {
        canvas.drawCircle(
          p,
          raio,
          Paint()
            ..color = cor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8,
        );
      } else {
        canvas.drawCircle(p, raio, Paint()..color = cor);
      }
      ocupados.add(Rect.fromCircle(center: p, radius: raio + 1));
    }

    for (final l in ordem) {
      final p = paraTela(l.lon, l.lat);
      if (!tela.contains(p)) continue;
      final emDestaque = destaque.contains(l.id);
      final estilo = TextStyle(
        fontSize: l.regiao ? 12 : (emDestaque ? 13 : 11.5),
        fontWeight: emDestaque ? FontWeight.w700 : FontWeight.w500,
        fontStyle: l.regiao || l.agua ? FontStyle.italic : FontStyle.normal,
        letterSpacing: l.regiao ? 1.2 : 0,
        color: l.regiao
            ? cores.regiao
            : l.agua
            ? cores.rio
            : (emDestaque ? cores.destaque : cores.texto),
      );
      final texto = l.regiao ? l.nome.toUpperCase() : l.nome;
      final tp = TextPainter(
        text: TextSpan(text: texto, style: estilo),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: 220);
      // Tenta à direita, à esquerda, acima e abaixo do ponto.
      final candidatos = l.regiao
          ? [p - Offset(tp.width / 2, tp.height / 2)]
          : [
              p + Offset(9, -tp.height / 2),
              p - Offset(tp.width + 9, tp.height / 2),
              p - Offset(tp.width / 2, tp.height + 8),
              p + Offset(-tp.width / 2, 8),
            ];
      for (final c in candidatos) {
        final caixa = (c & tp.size).inflate(1);
        if (!tela.contains(caixa.topLeft) ||
            !tela.contains(caixa.bottomRight)) {
          continue;
        }
        if (ocupados.any((o) => o.overlaps(caixa))) continue;
        _halo(canvas, tp, c, estilo, texto);
        tp.paint(canvas, c);
        ocupados.add(caixa);
        break;
      }
    }
  }

  void _halo(
    Canvas canvas,
    TextPainter tp,
    Offset pos,
    TextStyle estilo,
    String texto,
  ) {
    final contorno = TextPainter(
      text: TextSpan(
        text: texto,
        style: estilo.copyWith(
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = cores.halo,
          color: null,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: 220);
    contorno.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(_PintorMapa antigo) =>
      antigo.centro != centro ||
      antigo.escala != escala ||
      antigo.tamanho != tamanho ||
      !identical(antigo.lugares, lugares) ||
      !identical(antigo.rotas, rotas) ||
      antigo.cores.mar != cores.mar;
}
