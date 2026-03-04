import 'dart:io';
import 'package:vania/vania.dart';
import 'package:uuid/uuid.dart';

/// Run with: dart run lib/database/seeds/seed.dart
void main() async {
  await MigrationConnection().setup();
  await Seeder().run();
  await MigrationConnection().closeConnection();
  exit(0);
}

class Seeder {
  Future<void> run() async {
    await _seedBlingPackages();
    await _seedAds();
    print('Seeding complete.');
  }

  Future<void> _seedBlingPackages() async {
    // Check if already seeded
    final existing = await connection!.select('SELECT COUNT(*) as count FROM bling_packages', []);
    if (((existing.first['count'] as num?)?.toInt() ?? 0) > 0) {
      print('Bling packages already seeded, skipping.');
      return;
    }

    final packages = [
      {
        'id': const Uuid().v4(),
        'name': 'Starter',
        'bling_amount': 100,
        'price_cents': 99, // $0.99
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      {
        'id': const Uuid().v4(),
        'name': 'Basic',
        'bling_amount': 500,
        'price_cents': 399, // $3.99
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      {
        'id': const Uuid().v4(),
        'name': 'Popular',
        'bling_amount': 1200,
        'price_cents': 799, // $7.99
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      {
        'id': const Uuid().v4(),
        'name': 'Premium',
        'bling_amount': 3000,
        'price_cents': 1499, // $14.99
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      {
        'id': const Uuid().v4(),
        'name': 'Elite',
        'bling_amount': 10000,
        'price_cents': 3999, // $39.99
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
    ];

    for (final pkg in packages) {
      await connection!.statement(
        'INSERT INTO bling_packages (id, name, bling_amount, price_cents, is_active, created_at, updated_at) VALUES (\$1,\$2,\$3,\$4,\$5,\$6,\$7)',
        [
          pkg['id'],
          pkg['name'],
          pkg['bling_amount'],
          pkg['price_cents'],
          pkg['is_active'],
          pkg['created_at'],
          pkg['updated_at'],
        ],
      );
    }
    print('Bling packages seeded: ${packages.length} packages.');
  }

  Future<void> _seedAds() async {
    final existing = await connection!.select('SELECT COUNT(*) as count FROM ads', []);
    if (((existing.first['count'] as num?)?.toInt() ?? 0) > 0) {
      print('Ads already seeded, skipping.');
      return;
    }

    final ads = [
      {
        'id': const Uuid().v4(),
        'title': 'Get Verified on Bling!',
        'body': 'Stand out with a verified badge. Apply now.',
        'image_url': 'https://via.placeholder.com/400x200?text=Bling+Verified',
        'target_url': '',
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      {
        'id': const Uuid().v4(),
        'title': 'Buy Bling — Climb the Ranks',
        'body': 'Purchase Bling to level up and get featured on leaderboards.',
        'image_url': 'https://via.placeholder.com/400x200?text=Buy+Bling',
        'target_url': '',
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      {
        'id': const Uuid().v4(),
        'title': 'Join the Weekly Challenge',
        'body': 'Win 5,000 Bling by participating in this week\'s challenge!',
        'image_url': 'https://via.placeholder.com/400x200?text=Challenge',
        'target_url': '',
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
    ];

    for (final ad in ads) {
      await connection!.statement(
        'INSERT INTO ads (id, title, body, image_url, target_url, is_active, created_at, updated_at) VALUES (\$1,\$2,\$3,\$4,\$5,\$6,\$7,\$8)',
        [
          ad['id'],
          ad['title'],
          ad['body'],
          ad['image_url'],
          ad['target_url'],
          ad['is_active'],
          ad['created_at'],
          ad['updated_at'],
        ],
      );
    }
    print('Ads seeded: ${ads.length} ads.');
  }
}
