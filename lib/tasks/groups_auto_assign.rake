namespace :groups do
  desc "Auto-assign unassigned characters into groups (min 2, max 5 per group) and ensure chat channels"
  task auto_assign_unassigned: :environment do
    min_size = (ENV['MIN_SIZE'] || 2).to_i
    max_size = (ENV['MAX_SIZE'] || 5).to_i
    raise "MIN_SIZE must be >= 1" unless min_size >= 1
    raise "MAX_SIZE must be >= MIN_SIZE" unless max_size >= min_size

    chars = Character.where(group_id: nil).order(:id).to_a
    puts "Unassigned characters: #{chars.size}"
    if chars.empty?
      puts "Nothing to do."
      next
    end

    # Partition into chunks of up to max_size
    chunks = []
    while chars.any?
      chunks << chars.shift(max_size)
    end

    # If the last chunk has 1 and we have a previous chunk with > min_size, rebalance
    if chunks.size > 1 && chunks.last.size == 1
      prev = chunks[-2]
      if prev.size > min_size
        chunks.last.unshift(prev.pop)
      end
    end

    ActiveRecord::Base.transaction do
      chunks.each_with_index do |members, idx|
        # If chunk smaller than min_size and we can't rebalance, still proceed
        # but warn the operator.
        if members.size < min_size
          warn "Chunk ##{idx+1} has only #{members.size} member(s); below min_size=#{min_size}"
        end

        name = "Auto Group #{Time.now.strftime('%Y%m%d')}-#{idx+1}"
        day  = (idx % 120) + 1
        g = Group.create!(name: name, day: day)
        puts "Created group ##{g.id} (#{g.name}) with day=#{day}"

        members.each do |ch|
          ch.update!(group_id: g.id)
          puts " - Assigned character ##{ch.id} (#{ch.name}) to group ##{g.id}"
        end

        # Ensure chat channel and memberships
        g.ensure_chat_channel!
        g.sync_channel_memberships!
      end
    end

    puts "Done."
  end
end

