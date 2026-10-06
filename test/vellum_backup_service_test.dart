import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/services/backup_crypto.dart';
import 'package:vellum/services/vellum_backup_service.dart';

void main() {
  test('cloud config detects Tencent COS and normalizes prefix', () {
    const config = VellumCloudConfig(
      secretId: 'id',
      secretKey: 'key',
      bucketUrl: 'https://demo-1250000000.cos.ap-guangzhou.myqcloud.com/',
      prefix: '/reader/backups/',
    );
    expect(config.isConfigured, isTrue);
    expect(config.vendorLabel, '腾讯云 COS');
    expect(config.normalizedPrefix, 'reader/backups');
  });

  test('cloud config detects Aliyun OSS', () {
    const config = VellumCloudConfig(
      secretId: 'id',
      secretKey: 'key',
      bucketUrl: 'https://vellum.oss-cn-hangzhou.aliyuncs.com',
    );
    expect(config.isConfigured, isTrue);
    expect(config.vendorLabel, '阿里云 OSS');
  });

  test('encrypted archive bytes round trip and wrong password fails', () {
    final plain = Uint8List.fromList([1, 2, 3, 4, 5]);
    final encrypted = BackupCrypto.encrypt(plain, 'correct horse');
    expect(BackupCrypto.isEncrypted(encrypted), isTrue);
    expect(BackupCrypto.decrypt(encrypted, 'correct horse'), plain);
    expect(
      () => BackupCrypto.decrypt(encrypted, 'wrong'),
      throwsA(isA<ArgumentError>()),
    );
  });
}
