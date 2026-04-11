import 'package:vania/vania.dart';

class AddTransformFieldsToAvatarAccessories extends Migration {
  @override
  Future<void> up() async {
    super.up();

    await connection!.statement(
      '''
      ALTER TABLE avatar_accessories
      ADD COLUMN IF NOT EXISTS scale NUMERIC(8, 4) NOT NULL DEFAULT 1.0,
      ADD COLUMN IF NOT EXISTS offset_x NUMERIC(8, 4) NOT NULL DEFAULT 0,
      ADD COLUMN IF NOT EXISTS offset_y NUMERIC(8, 4) NOT NULL DEFAULT 0,
      ADD COLUMN IF NOT EXISTS rotation NUMERIC(8, 4) NOT NULL DEFAULT 0
      ''',
      [],
    );

    await connection!.statement(
      '''
      UPDATE avatar_accessories
      SET
        scale = CASE
          WHEN slot IN ('outfit', 'torso', 'shirt') THEN 0.90
          WHEN slot IN ('waist', 'pants', 'legs', 'legwear') THEN 0.80
          WHEN slot IN ('shoe', 'shoes', 'foot', 'feet', 'ankle') THEN 0.56
          WHEN slot IN ('watch', 'left_wrist', 'right_wrist', 'wrist', 'bracelet') THEN 0.24
          WHEN slot IN ('hand', 'hands', 'prop', 'left_hand', 'right_hand') THEN 0.34
          WHEN slot IN ('glasses', 'eyes', 'eye', 'mask', 'face') THEN 0.36
          WHEN slot IN ('hair', 'hat', 'head', 'head_top') THEN 0.54
          WHEN slot IN ('neck', 'chain', 'necklace') THEN 0.28
          ELSE 0.78
        END,
        offset_x = CASE
          WHEN slot IN ('watch', 'right_wrist', 'wrist', 'bracelet', 'hand', 'prop', 'right_hand') THEN 0.17
          WHEN slot IN ('left_wrist', 'left_hand') THEN -0.17
          ELSE 0
        END,
        offset_y = CASE
          WHEN slot IN ('hair', 'hat', 'head', 'head_top') THEN -0.10
          WHEN slot IN ('glasses', 'eyes', 'eye', 'mask', 'face') THEN -0.05
          WHEN slot IN ('outfit', 'torso', 'shirt') THEN -0.02
          WHEN slot IN ('waist', 'pants', 'legs', 'legwear') THEN 0.12
          WHEN slot IN ('shoe', 'shoes', 'foot', 'feet', 'ankle') THEN 0.24
          WHEN slot IN ('watch', 'left_wrist', 'right_wrist', 'wrist', 'bracelet', 'hand', 'prop', 'left_hand', 'right_hand') THEN 0.08
          ELSE 0
        END
      WHERE
        scale = 1.0
        AND offset_x = 0
        AND offset_y = 0
        AND rotation = 0
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
      DROP COLUMN IF EXISTS scale,
      DROP COLUMN IF EXISTS offset_x,
      DROP COLUMN IF EXISTS offset_y,
      DROP COLUMN IF EXISTS rotation
      ''',
      [],
    );
  }
}
