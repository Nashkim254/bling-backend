import 'dart:io';
import 'package:vania/vania.dart';
import 'create_users_table.dart';
import 'create_posts_table.dart';
import 'create_sessions_table.dart';
import 'create_comments_table.dart';
import 'create_shares_table.dart';
import 'create_reposts_table.dart';
import 'create_likes_table.dart';
import 'create_hashtags_table.dart';
import 'create_challenges_table.dart';
import 'create_challenge_entries_table.dart';
import 'create_personal_access_tokens_table.dart';
import 'create_chats_table.dart';
import 'create_wallets_table.dart';
import 'create_bling_packages_table.dart';
import 'create_bling_transactions_table.dart';
import 'create_follows_table.dart';
import 'create_notifications_table.dart';
import 'create_ads_table.dart';
import 'create_otps_table.dart';
import 'add_iap_columns.dart';
import 'add_commission_columns.dart';
import 'add_ad_campaign_columns.dart';
import 'create_ad_impressions_table.dart';
import 'create_ad_clicks_table.dart';
import 'create_conversations_table.dart';
import 'create_conversation_members_table.dart';
import 'create_message_reactions_table.dart';
import 'alter_chats_add_chat_fields.dart';
import 'alter_comments_add_parent_id.dart';
import 'create_blocks_table.dart';
import 'create_reports_table.dart';
import 'alter_users_add_status.dart';

void main(List<String> args) async {
  await MigrationConnection().setup();
  if (args.isNotEmpty && args.first.toLowerCase() == "migrate:fresh") {
    await Migrate().dropTables();
    await Migrate().registry();
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
    await CreateHashtagsTable().up();
    await CreateChallengesTable().up();
    await CreateChallengeEntriesTable().up();
    await CreatePersonalAccessTokensTable().up();
    await CreateChatsTable().up();
    await CreateWalletsTable().up();
    await CreateBlingPackagesTable().up();
    await CreateBlingTransactionsTable().up();
    await CreateFollowsTable().up();
    await CreateNotificationsTable().up();
    await CreateAdsTable().up();
    await CreateOtpsTable().up();
    await AddIapColumns().up();
    await AddCommissionColumns().up();
    await AddAdCampaignColumns().up();
    await CreateAdImpressionsTable().up();
    await CreateAdClicksTable().up();
    await CreateConversationsTable().up();
    await CreateConversationMembersTable().up();
    await CreateMessageReactionsTable().up();
    await AlterChatsAddChatFields().up();
    await AlterCommentsAddParentId().up();
    await CreateBlocksTable().up();
    await CreateReportsTable().up();
    await AlterUsersAddStatus().up();
  }

  dropTables() async {
    await CreateOtpsTable().down();
    await CreateAdsTable().down();
    await CreateNotificationsTable().down();
    await CreateFollowsTable().down();
    await CreateBlingTransactionsTable().down();
    await CreateBlingPackagesTable().down();
    await CreateWalletsTable().down();
    await CreateChatsTable().down();
    await CreatePersonalAccessTokensTable().down();
    await CreateChallengeEntriesTable().down();
    await CreateChallengesTable().down();
    await CreateHashtagsTable().down();
    await CreateLikesTable().down();
    await CreateRepostsTable().down();
    await CreateSharesTable().down();
    await CreateCommentsTable().down();
    await CreateSessionsTable().down();
    await CreatePostsTable().down();
    await CreateUserTable().down();
  }
}
