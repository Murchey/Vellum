import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/services/vellum_update_service.dart';

void main() {
  test('detects ABI labels from release asset names', () {
    expect(
      detectAbiFromAssetName('Vellum-V1.0.2-arm64-v8a.apk'),
      'arm64-v8a',
    );
    expect(
      detectAbiFromAssetName('app-armeabi-v7a-release.apk'),
      'armeabi-v7a',
    );
    expect(detectAbiFromAssetName('Vellum-V1.0.2-x86_64.apk'), 'x86_64');
    expect(detectAbiFromAssetName('notes.txt'), isNull);
  });

  test('release apk assets prefer arm64 first', () {
    const release = VellumReleaseInfo(
      currentVersion: '1.0.0',
      latestVersion: '1.0.2',
      notes: '',
      releaseUrl: 'https://example.com',
      assets: {
        'Vellum-V1.0.2-x86_64.apk': 'https://example.com/x86.apk',
        'Vellum-V1.0.2-armeabi-v7a.apk': 'https://example.com/v7.apk',
        'Vellum-V1.0.2-arm64-v8a.apk': 'https://example.com/v8.apk',
      },
    );

    final apks = release.apkAssets;
    expect(apks.map((e) => e.abi).toList(), [
      'arm64-v8a',
      'armeabi-v7a',
      'x86_64',
    ]);
  });

  test('preferred abi moves to the front and is kept alone at the top', () {
    const release = VellumReleaseInfo(
      currentVersion: '1.0.0',
      latestVersion: '1.0.3',
      notes: '',
      releaseUrl: 'https://example.com',
      assets: {
        'Vellum-V1.0.3-arm64-v8a.apk': 'https://example.com/v8.apk',
        'Vellum-V1.0.3-x86_64.apk': 'https://example.com/x86.apk',
        'Vellum-V1.0.3-armeabi-v7a.apk': 'https://example.com/v7.apk',
        'Vellum-V1.0.3-universal.apk': 'https://example.com/all.apk',
      },
    );

    expect(release.apkAssetsFor('x86_64').first.abi, 'x86_64');
    expect(release.apkAssetsFor('armeabi-v7a').first.label, 'armeabi-v7a');
    // Unknown device: the arm64 default stays first.
    expect(release.apkAssetsFor(null).first.abi, 'arm64-v8a');
    expect(release.apkAssetsFor('mips').first.abi, 'arm64-v8a');
    // The universal build sorts last and is labelled 通用.
    expect(release.apkAssets.last.label, '通用');
  });

  test('device abi names normalize onto release labels', () {
    expect(normalizeAbiName('arm64-v8a'), 'arm64-v8a');
    expect(normalizeAbiName('aarch64'), 'arm64-v8a');
    expect(normalizeAbiName('armeabi-v7a'), 'armeabi-v7a');
    expect(normalizeAbiName('armeabi'), 'armeabi-v7a');
    expect(normalizeAbiName('x86_64'), 'x86_64');
    expect(normalizeAbiName('i686'), 'x86');
    expect(normalizeAbiName('mips64'), isNull);
  });

  test('abi descriptions cover every label', () {
    for (final abi in ['arm64-v8a', 'armeabi-v7a', 'x86_64', 'x86']) {
      expect(abiDescription(abi), isNotEmpty);
    }
    expect(abiDescription(null), contains('通用'));
  });
}
