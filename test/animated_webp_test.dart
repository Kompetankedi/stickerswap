import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('encode animated webp test', () {
    final base = img.Image(width: 512, height: 512);
    img.fill(base, color: img.ColorUint8.rgba(255, 0, 0, 255));
    base.frameDuration = 100;

    for (int i = 0; i < 5; i++) {
      final f = img.Image(width: 512, height: 512);
      img.fill(f, color: img.ColorUint8.rgba(0, (i + 1) * 50, 255, 255));
      f.frameDuration = 100;
      base.frames.add(f);
    }

    final bytes = img.encodeWebP(base, lossless: false, quality: 75);
    expect(bytes, isNotEmpty);
    expect(bytes.length, lessThan(500 * 1024));
  });
}
