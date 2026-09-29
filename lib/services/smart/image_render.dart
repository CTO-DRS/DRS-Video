import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'intel_v4.dart';

/// Immutable, sendable parameter pack describing an image edit. Shared
/// between the UI and render isolates (guarantees WYSIWYG: the preview and
/// the saved copy run the exact same pipeline).
class EditParams {
  const EditParams({
    this.quarterTurns = 0,
    this.flipH = false,
    this.flipV = false,
    this.grayscale = false,
    this.invert = false,
    this.brightness = 0,
    this.contrast = 1.0,
    this.gamma = 1.0,
  });

  /// 0..3 (90° clockwise steps)
  final int quarterTurns;
  final bool flipH;
  final bool flipV;
  final bool grayscale;
  final bool invert;

  /// -255..255 (added per channel before contrast/gamma)
  final int brightness;
  /// 0..2 (1 = unchanged)
  final double contrast;
  /// 0.1..3 (1 = unchanged)
  final double gamma;

  bool get hasEdits =>
      quarterTurns != 0 ||
      flipH ||
      flipV ||
      grayscale ||
      invert ||
      brightness != 0 ||
      contrast != 1.0 ||
      gamma != 1.0;
}

/// Pure render pipeline (runs inside an isolate in the app; directly
/// testable in unit tests):
///  1. decode (jpeg/png/webp/gif/bmp/tga via the `image` package)
///  2. optional downscale to [maxEdge] on the long side
///  3. rotate → flip (geometric)
///  4. LUT pass: brightness → contrast → gamma → invert (intel_v4 math)
///  5. grayscale via BT.601 luma (channel mixing — cannot be a per-channel
///     LUT, hence a separate pass)
///  6. encode PNG (lossless, [pngLevelOne] = fastest) or JPEG q92
Uint8List renderImage(Uint8List srcBytes, EditParams params,
    {int? maxEdge, bool pngLevelOne = true}) {
  var image = img.decodeImage(srcBytes);
  if (image == null) throw const FormatException('decode failed');
  if (maxEdge != null &&
      (image.width > maxEdge || image.height > maxEdge)) {
    final wide = image.width >= image.height;
    image = img.copyResize(image,
        width: wide ? maxEdge : null, height: wide ? null : maxEdge);
  }
  if (params.quarterTurns != 0) {
    image = img.copyRotate(image, angle: params.quarterTurns * 90);
  }
  if (params.flipH) image = img.flipHorizontal(image);
  if (params.flipV) image = img.flipVertical(image);

  final lut = ImageAdjustments.lut(ImageAdjustments(
    brightness: params.brightness,
    contrast: params.contrast,
    gamma: params.gamma,
    invert: params.invert,
  ));
  for (final pixel in image) {
    var r = lut[pixel.r.toInt()];
    var g = lut[pixel.g.toInt()];
    var b = lut[pixel.b.toInt()];
    if (params.grayscale) {
      final y = ImageAdjustments.luma(r, g, b).round().clamp(0, 255);
      r = g = b = y;
    }
    pixel.r = r;
    pixel.g = g;
    pixel.b = b;
  }
  final encoded = pngLevelOne
      ? img.encodePng(image, level: 1)
      : img.encodeJpg(image, quality: 92);
  return Uint8List.fromList(encoded);
}
