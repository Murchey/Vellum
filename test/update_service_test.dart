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
}
