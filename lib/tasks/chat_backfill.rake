namespace :chat do
  desc "Ensure a private chat channel exists for every group and sync memberships"
  task backfill_group_channels: :environment do
    puts "Backfilling group chat channels..."
    Group.find_each do |g|
      ch = g.ensure_chat_channel!
      g.sync_channel_memberships!
      puts "Ensured channel #{ch.slug} for group #{g.id} (#{g.name})"
    end
    puts "Done."
  end
end

