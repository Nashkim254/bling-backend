import 'package:vania/vania.dart';

class AddSlotAndLayerToAvatarAccessories extends Migration {
  @override
  Future<void> up() async {
    super.up();

    await connection!.statement(
      '''
      ALTER TABLE avatar_accessories
      ADD COLUMN IF NOT EXISTS slot VARCHAR(40) NOT NULL DEFAULT 'accessory_main'
      ''',
      [],
    );
    await connection!.statement(
      '''
      ALTER TABLE avatar_accessories
      ADD COLUMN IF NOT EXISTS layer_order INTEGER NOT NULL DEFAULT 160
      ''',
      [],
    );

    await connection!.statement(
      '''
      UPDATE avatar_accessories
      SET
        slot = CASE
          WHEN COALESCE(TRIM(category), '') = 'outfit' THEN 'outfit'
          ELSE 'accessory_main'
        END,
        layer_order = CASE
          WHEN COALESCE(TRIM(category), '') = 'outfit' THEN 100
          ELSE 160
        END
      WHERE
        COALESCE(TRIM(slot), '') = ''
        OR slot = 'accessory_main'
        OR layer_order = 160
      ''',
      [],
    );
  }

  @override
  Future<void> down() async {
    super.down();
    await connection!.statement(
      '''
      ALTER TABLE avatar_accessories
      DROP COLUMN IF EXISTS slot,
      DROP COLUMN IF EXISTS layer_order
      ''',
      [],
    );
  }
}
