import 'package:coil/src/services/admin_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdminConfig Welcome Message', () {
    test('defaults to enabled with standard welcome message', () {
      const cfg = AdminConfig();
      expect(cfg.welcomeMessageEnabled, isTrue);
      expect(cfg.welcomeMessage, isEmpty);
    });

    test('fromMap falls back to announcement if it contains welcome', () {
      final map = {
        'announcement': 'Welcome to Iter! Connect, explore, and share with your community.',
      };
      final cfg = AdminConfig.fromMap(map);
      expect(cfg.welcomeMessageEnabled, isTrue);
      expect(cfg.welcomeMessage, contains('Welcome to Iter!'));
      expect(cfg.announcement, contains('Welcome to Iter!'));
    });

    test('fromMap uses metadata welcomeMessage when present', () {
      final map = {
        'announcement': 'General maintenance tonight',
        'metadata': {
          'welcomeMessage': 'Hello new explorer!',
          'welcomeMessageEnabled': false,
        },
      };
      final cfg = AdminConfig.fromMap(map);
      expect(cfg.welcomeMessageEnabled, isFalse);
      expect(cfg.welcomeMessage, 'Hello new explorer!');
      expect(cfg.announcement, 'General maintenance tonight');
    });

    test('toMap writes welcomeMessage and welcomeMessageEnabled to root and metadata', () {
      const cfg = AdminConfig(
        welcomeMessage: 'Welcome to our platform!',
        welcomeMessageEnabled: true,
      );
      final map = cfg.toMap();
      expect(map['welcomeMessage'], 'Welcome to our platform!');
      expect(map['welcomeMessageEnabled'], isTrue);
      expect(map['metadata'], isA<Map>());
      expect((map['metadata'] as Map)['welcomeMessage'], 'Welcome to our platform!');
      expect((map['metadata'] as Map)['welcomeMessageEnabled'], isTrue);
    });

    test('copyWith updates welcomeMessage and welcomeMessageEnabled', () {
      const cfg = AdminConfig();
      final updated = cfg.copyWith(
        welcomeMessage: 'Custom welcome',
        welcomeMessageEnabled: false,
      );
      expect(updated.welcomeMessage, 'Custom welcome');
      expect(updated.welcomeMessageEnabled, isFalse);
    });
  });
}
