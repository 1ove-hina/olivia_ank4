import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:olivia_ank4/app/theme.dart';

/// 无极调色器（镂空色环样式）。
///
/// - **色环**：拖动改变色相(Hue)；环本身是满饱和度/满明度的连续色相渐变，圆心镂空；
/// - **滑条**：分别调节 饱和度(Saturation) 与 明度(Value)；
/// - 三个分量均连续，故为「无极」。
///
/// 拖动实时回调 [onChanged]（即时预览），松手回调 [onChangeEnd]（持久化）。
class ColorWheelPicker extends StatefulWidget {
  final Color value;
  final double size;
  final ValueChanged<Color> onChanged;
  final ValueChanged<Color>? onChangeEnd;

  const ColorWheelPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.size = 180,
  });

  @override
  State<ColorWheelPicker> createState() => _ColorWheelPickerState();
}

class _ColorWheelPickerState extends State<ColorWheelPicker> {
  late double _h; // 色相 0–360
  late double _s; // 饱和度 0–1
  late double _v; // 明度 0–1

  /// 色环粗细（随尺寸自适应，限制在合理区间）
  double get _ringWidth => (widget.size * 0.16).clamp(14.0, 34.0);

  /// 环中线半径：指示点沿此半径绕行
  double get _midRadius => widget.size / 2 - _ringWidth / 2;

  @override
  void initState() {
    super.initState();
    _syncFrom(widget.value);
  }

  @override
  void didUpdateWidget(covariant ColorWheelPicker old) {
    super.didUpdateWidget(old);
    // 外部（如「恢复默认」）改了值，且与当前内部状态不一致 → 同步
    if (!_same(old.value, widget.value) && !_same(_current, widget.value)) {
      setState(() => _syncFrom(widget.value));
    }
  }

  void _syncFrom(Color c) {
    final hsv = HSVColor.fromColor(c);
    _h = hsv.hue;
    _s = hsv.saturation;
    _v = hsv.value == 0 ? 1 : hsv.value; // 纯黑时给明度一个可用起点
  }

  Color get _current => HSVColor.fromAHSV(1, _h, _s, _v).toColor();

  bool _same(Color a, Color b) => a.toARGB32() == b.toARGB32();

  /// 色环只按角度取色相（圆心镂空，距离不参与计算）
  void _pickHue(Offset local) {
    final center = Offset(widget.size / 2, widget.size / 2);
    var deg =
        math.atan2(local.dy - center.dy, local.dx - center.dx) * 180 / math.pi;
    if (deg < 0) deg += 360;
    setState(() => _h = deg);
    widget.onChanged(_current);
  }

  @override
  Widget build(BuildContext context) {
    final rad = _h * math.pi / 180;
    final thumbCenter = Offset(
      widget.size / 2 + math.cos(rad) * _midRadius,
      widget.size / 2 + math.sin(rad) * _midRadius,
    );
    final thumbD = _ringWidth.clamp(14.0, 32.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // —— 镂空色环 ——
        Center(
          child: GestureDetector(
            onPanDown: (d) => _pickHue(d.localPosition),
            onPanUpdate: (d) => _pickHue(d.localPosition),
            onPanEnd: (_) => widget.onChangeEnd?.call(_current),
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _RingPainter(ringWidth: _ringWidth),
                    ),
                  ),
                  Positioned(
                    left: thumbCenter.dx - thumbD / 2,
                    top: thumbCenter.dy - thumbD / 2,
                    child: IgnorePointer(
                      child: Container(
                        width: thumbD,
                        height: thumbD,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.transparent, // 镂空，露出环上颜色
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: const [
                            BoxShadow(color: Colors.black54, blurRadius: 3),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // —— 饱和度 / 明度 ——
        _slider('饱和度', _s, (v) {
          setState(() => _s = v);
          widget.onChanged(_current);
        }, (v) {
          setState(() => _s = v);
          widget.onChangeEnd?.call(_current);
        }),
        _slider('明度', _v, (v) {
          setState(() => _v = v);
          widget.onChanged(_current);
        }, (v) {
          setState(() => _v = v);
          widget.onChangeEnd?.call(_current);
        }),
        const SizedBox(height: 4),
        // —— 实时预览 + 十六进制值 ——
        Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: _current,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.divider),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              colorToHex(_current),
              style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
            ),
            const Spacer(),
            Text('拖拽色环取色',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
      ],
    );
  }

  Widget _slider(
    String label,
    double v,
    ValueChanged<double> onChanged,
    ValueChanged<double> onChangeEnd,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(label,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 6,
              activeTrackColor: _current,
              thumbColor: Colors.white,
              inactiveTrackColor: AppColors.divider,
            ),
            child: Slider(
              value: v,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ),
      ],
    );
  }
}

/// 绘制镂空色环：圆环描边 + 扫掠渐变，给出连续色相。
class _RingPainter extends CustomPainter {
  final double ringWidth;
  const _RingPainter({required this.ringWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final ringRadius = size.width / 2 - ringWidth / 2;
    final rect = Rect.fromCircle(center: center, radius: size.width / 2);

    final hueColors = <Color>[
      for (int i = 0; i <= 360; i += 30)
        HSVColor.fromAHSV(1, (i % 360).toDouble(), 1, 1).toColor(),
    ];
    canvas.drawCircle(
      center,
      ringRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringWidth
        ..shader = SweepGradient(
          colors: hueColors,
          startAngle: 0,
          endAngle: 2 * math.pi,
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.ringWidth != ringWidth;
}
