import 'dart:io';
import 'package:vania/vania.dart';
import 'create_users_table.dart';
import 'create_posts_table.dart';
import 'create_sessions_table.dart';
import 'create_comments_table.dart';
import 'create_shares_table.dart';
import 'create_reposts_table.dart';
import 'create_likes_table.dart';

void main(List<String> args) async {
  await MigrationConnection().setup();
  if (args.isNotEmpty && args.first.toLowerCase() == "migrate:fresh") {
    await Migrate().dropTables();
  } else {
    await Migrate().registry();
  }
  await MigrationConnection().closeConnection();
  exit(0);
}

class Migrate {
  registry() async {
		 await CreateUserTable().up();
		 await CreatePostsTable().up();
		 await CreateSessionsTable().up();
		 await CreateCommentsTable().up();
		 await CreateSharesTable().up();
		 await CreateRepostsTable().up();
		 await CreateLikesTable().up();
	}

  dropTables() async {
		 await CreateLikesTable().down();
		 await CreateRepostsTable().down();
		 await CreateSharesTable().down();
		 await CreateCommentsTable().down();
		 await CreateSessionsTable().down();
		 await CreatePostsTable().down();
		 await CreateUserTable().down();
	 }
}
