import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:spent/core/services/haptics.dart';
import 'package:spent/core/theme/app_theme.dart';
import 'package:spent/core/theme/palette.dart';
import 'package:spent/core/theme/tokens.dart';

/// Rounds [v] up to a "nice" axis maximum: 1, 2, 2.5, 5 × 10^n.
double niceCeil(double v) {
  if (v <= 0) return 1;
  final exp = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
  final f = v / exp;
  final nice = f <= 1
      ? 1.0
      : f <= 2
      ? 2.0
      : f <= 2.5
      ? 2.5
      : f <= 5
      ? 5.0
      : 10.0;
  return nice * exp;
}

TextPainter _text(String s, TextStyle style) => TextPainter(
  text: TextSpan(text: s, style: style),
  textDirection: TextDirection.ltr,
)..layout();

/// Draws a tooltip bubble above [anchor], kept inside [bounds].
void _tooltip(
  Canvas canvas,
  Rect bounds,
  Offset anchor,
  List<(String, TextStyle)> lines,
  Color bg,
) {
  final painters = [for (final (s, st) in lines) _text(s, st)];
  final w = painters.fold<double>(0, (m, p) => math.max(m, p.width)) + 20;
  final h = painters.fold<double>(0, (s, p) => s + p.height) + 14 + (painters.length - 1) * 2;
  var left = anchor.dx - w / 2;
  left = left.clamp(bounds.left, math.max(bounds.left, bounds.right - w));
  var top = anchor.dy - h - 10;
  if (top < bounds.top - 6) top = bounds.top - 6;
  final rect = RRect.fromRectAndRadius(Rect.fromLTWH(left, top, w, h), const Radius.circular(10));
  canvas.drawRRect(rect, Paint()..color = bg);
  var y = top + 7;
  for (final p in painters) {
    p.paint(canvas, Offset(left + 10, y));
    y += p.height + 2;
  }
}

/// Grid, axis labels and baseline shared by the time charts.
class _Axes {
  _Axes({
    required this.size,
    required this.max,
    required this.formatTick,
    required this.style,
    required this.palette,
  });

  final Size size;
  final double max;
  final String Function(double) formatTick;
  final TextStyle style;
  final AppPalette palette;

  static const bottomBand = 22.0;
  static const topPad = 8.0;
  late final double left =
      math.max(_text(formatTick(max), style).width, _text(formatTick(max / 2), style).width) + 10;
  double get right => size.width;
  double get top => topPad;
  double get bottom => size.height - bottomBand;
  double get width => right - left;
  double get height => bottom - top;

  double y(double v) => bottom - (v / max) * height;

  void paint(Canvas canvas) {
    final grid = Paint()
      ..color = palette.hairline
      ..strokeWidth = 1;
    for (final v in [max / 2, max]) {
      final yy = y(v).roundToDouble() + 0.5;
      canvas.drawLine(Offset(left, yy), Offset(right, yy), grid);
      final t = _text(formatTick(v), style);
      t.paint(canvas, Offset(left - 8 - t.width, yy - t.height / 2));
    }
    canvas.drawLine(
      Offset(left, bottom + 0.5),
      Offset(right, bottom + 0.5),
      Paint()
        ..color = palette.ink3.withValues(alpha: 0.45)
        ..strokeWidth = 1,
    );
  }

  void xLabel(Canvas canvas, double x, String label, {bool strong = false}) {
    final t = _text(
      label,
      strong ? style.copyWith(color: palette.ink, fontWeight: FontWeight.w800) : style,
    );
    final lx = (x - t.width / 2).clamp(left - 4, right - t.width);
    t.paint(canvas, Offset(lx, bottom + 6));
  }
}

// ── Bar chart ──────────────────────────────────────────────────────────────

/// One series of bars over time with an average line and tap/drag tooltips.
class TimeBarChart extends StatefulWidget {
  const TimeBarChart({
    super.key,
    required this.values,
    required this.xLabels,
    required this.tooltipTitle,
    required this.formatValue,
    required this.formatTick,
    this.lastIndex,
    this.highlight,
    this.height = 190,
    this.color,
    this.showAverage = true,
  });

  final List<int> values;

  /// A label per bar; empty strings are skipped.
  final List<String> xLabels;
  final String Function(int index) tooltipTitle;
  final String Function(int value) formatValue;
  final String Function(double value) formatTick;

  /// Bars after this index haven't happened yet and aren't drawn.
  final int? lastIndex;

  /// Index drawn with a bold x label (e.g. today).
  final int? highlight;
  final double height;
  final Color? color;
  final bool showAverage;

  @override
  State<TimeBarChart> createState() => _TimeBarChartState();
}

class _TimeBarChartState extends State<TimeBarChart> with SingleTickerProviderStateMixin {
  late final AnimationController _grow = AnimationController(vsync: this, duration: Motion.chart)
    ..forward();
  int? _selected;

  @override
  void didUpdateWidget(TimeBarChart old) {
    super.didUpdateWidget(old);
    if (old.values.length != widget.values.length || !_sameShape(old.values, widget.values)) {
      _selected = null;
      _grow.forward(from: 0);
    }
  }

  bool _sameShape(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _grow.dispose();
    super.dispose();
  }

  void _select(Offset local, Size size, _Axes axes) {
    if (widget.values.isEmpty) return;
    final slot = axes.width / widget.values.length;
    final i = ((local.dx - axes.left) / slot).floor().clamp(0, widget.values.length - 1);
    if (widget.lastIndex != null && i > widget.lastIndex!) return;
    if (i != _selected) Haptics.selection();
    setState(() => _selected = i);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final style = context.text.labelSmall!.copyWith(
      color: p.ink3,
      letterSpacing: 0,
      fontSize: 10.5,
    );
    final last = widget.lastIndex ?? widget.values.length - 1;
    final visible = widget.values.take(last + 1).toList();
    final maxV = visible.isEmpty ? 0 : visible.reduce(math.max);
    final max = niceCeil(maxV.toDouble());
    final avg = visible.isEmpty ? 0.0 : visible.reduce((a, b) => a + b) / visible.length;
    if (Motion.reduced(context)) _grow.value = 1;
    return Semantics(
      label:
          'Bar chart. Highest ${widget.formatValue(maxV)}, average ${widget.formatValue(avg.round())}.',
      child: LayoutBuilder(
        builder: (context, c) {
          final size = Size(c.maxWidth, widget.height);
          final axes = _Axes(
            size: size,
            max: max,
            formatTick: widget.formatTick,
            style: style,
            palette: p,
          );
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) {
              final slot = axes.width / math.max(1, widget.values.length);
              final i = ((d.localPosition.dx - axes.left) / slot).floor();
              if (i == _selected) {
                setState(() => _selected = null);
              } else {
                _select(d.localPosition, size, axes);
              }
            },
            onHorizontalDragStart: (d) => _select(d.localPosition, size, axes),
            onHorizontalDragUpdate: (d) => _select(d.localPosition, size, axes),
            child: AnimatedBuilder(
              animation: _grow,
              builder: (context, _) => CustomPaint(
                size: size,
                painter: _BarPainter(
                  values: widget.values,
                  last: last,
                  axes: axes,
                  t: Motion.emphasized.transform(_grow.value),
                  color: widget.color ?? p.accent,
                  selected: _selected,
                  avg: widget.showAverage && visible.length > 1 ? avg : null,
                  labels: widget.xLabels,
                  highlight: widget.highlight,
                  tooltip: _selected == null
                      ? null
                      : [
                          (
                            widget.tooltipTitle(_selected!),
                            context.text.labelSmall!.copyWith(
                              color: p.isDark ? p.ink2 : p.surface3,
                              letterSpacing: 0,
                            ),
                          ),
                          (
                            widget.formatValue(widget.values[_selected!]),
                            context.text.titleSmall!
                                .copyWith(
                                  color: p.isDark ? p.ink : p.surface,
                                  fontWeight: FontWeight.w800,
                                )
                                .tabular,
                          ),
                        ],
                  avgLabel: 'avg',
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.values,
    required this.last,
    required this.axes,
    required this.t,
    required this.color,
    required this.selected,
    required this.avg,
    required this.labels,
    required this.highlight,
    required this.tooltip,
    required this.avgLabel,
  });

  final List<int> values;
  final int last;
  final _Axes axes;
  final double t;
  final Color color;
  final int? selected;
  final double? avg;
  final List<String> labels;
  final int? highlight;
  final List<(String, TextStyle)>? tooltip;
  final String avgLabel;

  @override
  void paint(Canvas canvas, Size size) {
    final p = axes.palette;
    axes.paint(canvas);
    if (values.isEmpty) return;
    final slot = axes.width / values.length;
    final barW = (slot * 0.62).clamp(2.0, 24.0);
    final radius = math.min(4.0, barW / 2);
    final paint = Paint();
    for (var i = 0; i < values.length; i++) {
      final cx = axes.left + slot * (i + 0.5);
      if (i < labels.length && labels[i].isNotEmpty) {
        axes.xLabel(canvas, cx, labels[i], strong: i == highlight);
      }
      if (i > last || values[i] <= 0) continue;
      final h = (values[i] / axes.max) * axes.height * t;
      if (h <= 0.5) continue;
      paint.color = selected == null || selected == i ? color : color.withValues(alpha: 0.32);
      final rect = Rect.fromLTRB(cx - barW / 2, axes.bottom - h, cx + barW / 2, axes.bottom);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          rect,
          topLeft: Radius.circular(radius),
          topRight: Radius.circular(radius),
        ),
        paint,
      );
    }
    if (avg != null && avg! > 0) {
      final y = axes.y(avg!).roundToDouble() + 0.5;
      canvas.drawLine(
        Offset(axes.left, y),
        Offset(axes.right, y),
        Paint()
          ..color = p.ink2.withValues(alpha: 0.7 * t)
          ..strokeWidth = 1,
      );
      final label = _text(
        avgLabel,
        axes.style.copyWith(color: p.ink2, fontWeight: FontWeight.w700),
      );
      final bg = Rect.fromLTWH(
        axes.right - label.width - 8,
        y - label.height / 2 - 1,
        label.width + 8,
        label.height + 2,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(bg, const Radius.circular(4)),
        Paint()..color = p.surface,
      );
      label.paint(canvas, Offset(bg.left + 4, bg.top + 1));
    }
    if (selected != null && tooltip != null && selected! < values.length) {
      final cx = axes.left + slot * (selected! + 0.5);
      final h = (values[selected!] / axes.max) * axes.height * t;
      _tooltip(
        canvas,
        Offset.zero & size,
        Offset(cx, axes.bottom - h),
        tooltip!,
        p.isDark ? p.surface3 : p.ink,
      );
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) => true;
}

// ── Pace (cumulative) chart ────────────────────────────────────────────────

/// Running totals of this period vs the previous one, on one axis.
class PaceChart extends StatefulWidget {
  const PaceChart({
    super.key,
    required this.current,
    required this.previous,
    required this.currentUntil,
    required this.xLabels,
    required this.tooltipTitle,
    required this.formatValue,
    required this.formatTick,
    required this.currentName,
    required this.previousName,
    this.height = 190,
  });

  final List<int> current;
  final List<int> previous;

  /// Last index of [current] that has happened.
  final int currentUntil;
  final List<String> xLabels;
  final String Function(int index) tooltipTitle;
  final String Function(int value) formatValue;
  final String Function(double value) formatTick;
  final String currentName;
  final String previousName;
  final double height;

  @override
  State<PaceChart> createState() => _PaceChartState();
}

class _PaceChartState extends State<PaceChart> with SingleTickerProviderStateMixin {
  late final AnimationController _draw = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();
  int? _cursor;

  @override
  void didUpdateWidget(PaceChart old) {
    super.didUpdateWidget(old);
    if (old.current.length != widget.current.length ||
        old.currentUntil != widget.currentUntil ||
        (old.current.isNotEmpty &&
            widget.current.isNotEmpty &&
            old.current.last != widget.current.last)) {
      _cursor = null;
      _draw.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _draw.dispose();
    super.dispose();
  }

  int get _n => math.max(widget.current.length, widget.previous.length);

  void _move(Offset local, _Axes axes) {
    if (_n < 2) return;
    final step = axes.width / (_n - 1);
    final i = ((local.dx - axes.left) / step).round().clamp(0, _n - 1);
    if (i != _cursor) Haptics.selection();
    setState(() => _cursor = i);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final style = context.text.labelSmall!.copyWith(
      color: p.ink3,
      letterSpacing: 0,
      fontSize: 10.5,
    );
    final cur = widget.current.take(widget.currentUntil + 1).toList();
    final maxV = [...cur, ...widget.previous].fold<int>(0, math.max);
    final max = niceCeil(maxV.toDouble());
    if (Motion.reduced(context)) _draw.value = 1;
    final legend = Row(
      children: [
        _LegendKey(color: p.accent, label: widget.currentName),
        const Gap(Insets.lg),
        _LegendKey(color: p.ink3, label: widget.previousName),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        legend,
        const Gap(Insets.md),
        LayoutBuilder(
          builder: (context, c) {
            final size = Size(c.maxWidth, widget.height);
            final axes = _Axes(
              size: size,
              max: max,
              formatTick: widget.formatTick,
              style: style,
              palette: p,
            );
            final cursor = _cursor;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _move(d.localPosition, axes),
              onHorizontalDragStart: (d) => _move(d.localPosition, axes),
              onHorizontalDragUpdate: (d) => _move(d.localPosition, axes),
              child: AnimatedBuilder(
                animation: _draw,
                builder: (context, _) => CustomPaint(
                  size: size,
                  painter: _PacePainter(
                    current: cur,
                    previous: widget.previous,
                    n: _n,
                    axes: axes,
                    t: Curves.easeInOutCubic.transform(_draw.value),
                    color: p.accent,
                    compare: p.ink3,
                    labels: widget.xLabels,
                    cursor: cursor,
                    tooltip: cursor == null
                        ? null
                        : [
                            (
                              widget.tooltipTitle(cursor),
                              context.text.labelSmall!.copyWith(
                                color: p.isDark ? p.ink2 : p.surface3,
                                letterSpacing: 0,
                              ),
                            ),
                            if (cursor < cur.length)
                              (
                                '${widget.currentName}  ${widget.formatValue(cur[cursor])}',
                                context.text.labelMedium!
                                    .copyWith(
                                      color: p.isDark ? p.ink : p.surface,
                                      fontWeight: FontWeight.w800,
                                    )
                                    .tabular,
                              ),
                            if (cursor < widget.previous.length)
                              (
                                '${widget.previousName}  ${widget.formatValue(widget.previous[cursor])}',
                                context.text.labelMedium!
                                    .copyWith(color: p.isDark ? p.ink2 : p.surface3)
                                    .tabular,
                              ),
                          ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _LegendKey extends StatelessWidget {
  const _LegendKey({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 14,
        height: 3,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
      ),
      const Gap(6),
      Text(label, style: context.text.labelMedium?.copyWith(color: context.palette.ink2)),
    ],
  );
}

class _PacePainter extends CustomPainter {
  _PacePainter({
    required this.current,
    required this.previous,
    required this.n,
    required this.axes,
    required this.t,
    required this.color,
    required this.compare,
    required this.labels,
    required this.cursor,
    required this.tooltip,
  });

  final List<int> current;
  final List<int> previous;
  final int n;
  final _Axes axes;
  final double t;
  final Color color;
  final Color compare;
  final List<String> labels;
  final int? cursor;
  final List<(String, TextStyle)>? tooltip;

  double _x(int i) => n <= 1 ? axes.left : axes.left + axes.width * i / (n - 1);

  Path _line(List<int> values) {
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final pt = Offset(_x(i), axes.y(values[i].toDouble()));
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final p = axes.palette;
    axes.paint(canvas);
    for (var i = 0; i < n && i < labels.length; i++) {
      if (labels[i].isNotEmpty) axes.xLabel(canvas, _x(i), labels[i]);
    }
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, axes.left + axes.width * t + 6, size.height));
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (previous.length > 1) canvas.drawPath(_line(previous), stroke..color = compare);
    if (current.isNotEmpty) {
      final line = _line(current);
      final area = Path.from(line)
        ..lineTo(_x(current.length - 1), axes.bottom)
        ..lineTo(_x(0), axes.bottom)
        ..close();
      canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.10));
      if (current.length > 1) canvas.drawPath(line, stroke..color = color);
      // End dot with a ring in the surface color.
      final end = Offset(_x(current.length - 1), axes.y(current.last.toDouble()));
      canvas.drawCircle(end, 6, Paint()..color = p.surface);
      canvas.drawCircle(end, 4, Paint()..color = color);
    }
    canvas.restore();

    if (cursor != null) {
      final x = _x(cursor!);
      canvas.drawLine(
        Offset(x, axes.top),
        Offset(x, axes.bottom),
        Paint()
          ..color = p.ink2.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
      var anchorY = axes.bottom;
      if (cursor! < previous.length) {
        final pt = Offset(x, axes.y(previous[cursor!].toDouble()));
        canvas.drawCircle(pt, 6, Paint()..color = p.surface);
        canvas.drawCircle(pt, 4, Paint()..color = compare);
        anchorY = math.min(anchorY, pt.dy);
      }
      if (cursor! < current.length) {
        final pt = Offset(x, axes.y(current[cursor!].toDouble()));
        canvas.drawCircle(pt, 6, Paint()..color = p.surface);
        canvas.drawCircle(pt, 4, Paint()..color = color);
        anchorY = math.min(anchorY, pt.dy);
      }
      if (tooltip != null) {
        _tooltip(
          canvas,
          Offset.zero & size,
          Offset(x, anchorY),
          tooltip!,
          p.isDark ? p.surface3 : p.ink,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_PacePainter old) => true;
}

// ── Donut ──────────────────────────────────────────────────────────────────

class DonutSlice {
  const DonutSlice(this.value, this.color);

  final int value;
  final Color color;
}

/// Part-to-whole ring (≤ 6 slices) with a 2px surface gap between segments.
class DonutChart extends StatefulWidget {
  const DonutChart({
    super.key,
    required this.slices,
    required this.center,
    this.selected,
    this.onSelect,
    this.size = 200,
    this.thickness = 22,
  });

  final List<DonutSlice> slices;
  final Widget center;
  final int? selected;
  final ValueChanged<int?>? onSelect;
  final double size;
  final double thickness;

  @override
  State<DonutChart> createState() => _DonutChartState();
}

class _DonutChartState extends State<DonutChart> with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(vsync: this, duration: Motion.chart)
    ..forward();

  @override
  void didUpdateWidget(DonutChart old) {
    super.didUpdateWidget(old);
    final changed =
        old.slices.length != widget.slices.length ||
        old.slices.fold<int>(0, (s, e) => s + e.value) !=
            widget.slices.fold<int>(0, (s, e) => s + e.value);
    if (changed) _sweep.forward(from: 0);
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  void _tap(Offset local) {
    final c = Offset(widget.size / 2, widget.size / 2);
    final d = local - c;
    final r = widget.size / 2;
    if (d.distance < r - widget.thickness - 14 || d.distance > r + 6) {
      widget.onSelect?.call(null);
      return;
    }
    var angle = math.atan2(d.dy, d.dx) + math.pi / 2;
    if (angle < 0) angle += math.pi * 2;
    final total = widget.slices.fold<int>(0, (s, e) => s + e.value);
    if (total <= 0) return;
    var acc = 0.0;
    for (var i = 0; i < widget.slices.length; i++) {
      acc += widget.slices[i].value / total * math.pi * 2;
      if (angle <= acc) {
        Haptics.selection();
        widget.onSelect?.call(widget.selected == i ? null : i);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (Motion.reduced(context)) _sweep.value = 1;
    return GestureDetector(
      onTapUp: (d) => _tap(d.localPosition),
      child: AnimatedBuilder(
        animation: _sweep,
        builder: (context, child) => CustomPaint(
          size: Size.square(widget.size),
          painter: _DonutPainter(
            slices: widget.slices,
            t: Motion.emphasized.transform(_sweep.value),
            thickness: widget.thickness,
            selected: widget.selected,
            gapColor: p.surface,
            empty: p.surface2,
          ),
          child: SizedBox.square(
            dimension: widget.size,
            child: Center(child: child),
          ),
        ),
        child: widget.center,
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.slices,
    required this.t,
    required this.thickness,
    required this.selected,
    required this.gapColor,
    required this.empty,
  });

  final List<DonutSlice> slices;
  final double t;
  final double thickness;
  final int? selected;
  final Color gapColor;
  final Color empty;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - thickness / 2 - 4;
    final total = slices.fold<int>(0, (s, e) => s + e.value);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt;
    if (total <= 0) {
      canvas.drawCircle(
        c,
        r,
        paint
          ..color = empty
          ..strokeWidth = thickness,
      );
      return;
    }
    // A 2px gap at the ring's middle radius.
    final gap = slices.length > 1 ? 2 / r : 0.0;
    var start = -math.pi / 2;
    for (var i = 0; i < slices.length; i++) {
      final sweep = slices[i].value / total * math.pi * 2 * t;
      final isSel = selected == i;
      final dim = selected != null && !isSel;
      paint
        ..color = dim ? slices[i].color.withValues(alpha: 0.28) : slices[i].color
        ..strokeWidth = isSel ? thickness + 8 : thickness;
      final draw = math.max(0.0, sweep - gap);
      if (draw > 0) {
        canvas.drawArc(Rect.fromCircle(center: c, radius: r), start + gap / 2, draw, false, paint);
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => true;
}
