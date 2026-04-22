# frozen_string_literal: true

require 'yaml'

namespace :spells do
  desc 'Replace all spells in DB from config/spells.yml (NUKE=1 to clear dependencies first)'
  task replace: :environment do
    path = Rails.root.join('config','spells.yml')
    unless File.exist?(path)
      puts "[spells] File not found: #{path}"
      next
    end

    # Robust loader: handle files that (accidentally) define 'spells:' more than once
    content = File.read(path)
    segments = []
    current = []
    inside = false
    content.each_line do |line|
      if line.match?(/^\s*spells:\s*$/)
        segments << current.join if inside && current.any?
        current = []
        inside = true
        next
      end
      current << line if inside
    end
    segments << current.join if inside && current.any?

    all_rows = []
    if segments.any?
      segments.each_with_index do |seg, idx|
        begin
          y = YAML.safe_load("spells:\n" + seg, permitted_classes: [], aliases: true) || {}
          rows = Array(y['spells'])
          all_rows.concat(rows)
        rescue => e
          puts "[spells] YAML segment #{idx+1} failed to parse: #{e.message}"
        end
      end
    else
      # Fallback to standard single-block load
      begin
        y = YAML.load_file(path) || {}
        all_rows = Array(y['spells'])
      rescue => e
        puts "[spells] YAML load failed: #{e.message}"
        all_rows = []
      end
    end

    if all_rows.empty?
      puts "[spells] No spells found in #{path}"
      next
    end

    nuke = ENV['NUKE'].to_s.strip.downcase.in?(['1','true','yes'])
    if nuke
      puts "[spells] NUKE=1: clearing SpellSource, SheetKnownSpell, SheetPreparedSpell, and Spell..."
      SpellSource.delete_all
      if ActiveRecord::Base.connection.data_source_exists?('sheet_known_spells')
        ActiveRecord::Base.connection.execute('DELETE FROM sheet_known_spells')
      end
      if ActiveRecord::Base.connection.data_source_exists?('sheet_prepared_spells')
        ActiveRecord::Base.connection.execute('DELETE FROM sheet_prepared_spells')
      end
      Spell.delete_all
    end

    created = 0
    updated = 0
    failed  = 0

    all_rows.each do |row|
      next unless row.is_a?(Hash)
      api_index = row['api_index'].to_s.presence
      name      = row['name'].to_s
      level     = row['level']
      school    = row['school']
      range     = row['range']
      components= Array(row['components']).join(', ')
      material  = row['material']
      ritual    = row['ritual']
      duration  = row['duration']
      concentration = row['concentration']
      casting_time  = row['casting_time']
      desc      = Array(row['desc']).join("\n\n")
      higher    = Array(row['higher_level']).join("\n\n")

      if api_index.blank?
        puts "[spells] Skip row without api_index: #{name}"
        failed += 1
        next
      end

      sp = Spell.find_or_initialize_by(api_index: api_index)
      before_new = sp.new_record?
      begin
        sp.name = name
        sp.level = level
        sp.school = school if sp.respond_to?(:school=)
        sp.range = range if sp.respond_to?(:range=)
        sp.components = components if sp.respond_to?(:components=)
        sp.material = material if sp.respond_to?(:material=)
        sp.ritual = ritual unless ritual.nil?
        sp.duration = duration if sp.respond_to?(:duration=)
        sp.concentration = concentration unless concentration.nil?
        sp.casting_time = casting_time if sp.respond_to?(:casting_time=)
        sp.desc = desc if sp.respond_to?(:desc=)
        sp.higher_level = higher if sp.respond_to?(:higher_level=)
        sp.save!
        if before_new
          created += 1
        else
          updated += 1 if sp.previous_changes.except('updated_at').any?
        end
      rescue => e
        failed += 1
        puts "[spells] Failed upsert for #{api_index} (#{name}): #{e.class} #{e.message}"
      end
    end

    puts "[spells] Spells upsert complete. created=#{created} updated=#{updated} failed=#{failed} total=#{created+updated+failed}"

    # === Associate spells to classes from config/spell_class_index.yml ===
    begin
      idx_path = Rails.root.join('config', 'spell_class_index.yml')
      if File.exist?(idx_path)
        data = YAML.load_file(idx_path) || {}
        map  = data['spell_class_index'] || {}

        # Map PT class keys -> Klass.api_index
        CLASS_API_MAP = {
          'bardo' => 'bard',
          'bruxo' => 'warlock',
          'clérigo' => 'cleric',
          'clerigo' => 'cleric',
          'druida' => 'druid',
          'feiticeiro' => 'sorcerer',
          'mago' => 'wizard',
          'paladino' => 'paladin',
          'patrulheiro' => 'ranger'
        }.freeze

        # Optional sync to remove extra links for these classes only
        sync = ENV['SYNC'].to_s.strip.downcase.in?(['1','true','yes'])
        target_klass_ids = {}
        CLASS_API_MAP.values.uniq.each do |api|
          k = Klass.find_by(api_index: api)
          target_klass_ids[api] = k&.id
        end

        added_links = 0
        warnings = 0

        # Build desired associations: { [klass_id] => Set<spell_id> }
        desired = Hash.new { |h,k| h[k] = Set.new }
        map.each do |spell_api, cls_hash|
          sp = Spell.find_by(api_index: spell_api.to_s)
          unless sp
            puts "[spells] WARN: spell not found for class index: #{spell_api}"
            warnings += 1
            next
          end
          (cls_hash || {}).each do |pt_key, spell_lvl|
            api = CLASS_API_MAP[pt_key.to_s]
            unless api
              puts "[spells] WARN: unknown class key '#{pt_key}' for #{spell_api} (skipping)"
              warnings += 1
              next
            end
            klass = Klass.find_by(api_index: api)
            unless klass
              puts "[spells] WARN: Klass not found for api_index='#{api}' (#{pt_key})"
              warnings += 1
              next
            end
            # Optional check: provided spell level should match Spell.level
            if !spell_lvl.nil? && sp.level.to_i != spell_lvl.to_i
              puts "[spells] NOTE: level mismatch for #{spell_api} (DB=#{sp.level} idx=#{spell_lvl})"
            end
            desired[klass.id] << sp.id
          end
        end

        # Sync mode: remove any SpellSource for target classes that are not desired
        if sync
          desired.each_key do |klass_id|
            existing = SpellSource.where(source_type: 'Klass', source_id: klass_id)
            existing.find_each do |ss|
              next if desired[klass_id].include?(ss.spell_id)
              ss.destroy
            end
          end
        end

        # Create missing SpellSource links
        desired.each do |klass_id, spell_ids|
          spell_ids.each do |sid|
            ss = SpellSource.find_or_initialize_by(source_type: 'Klass', source_id: klass_id, spell_id: sid)
            if ss.new_record?
              # Do not set min_class_level here: spell level != class level requirement
              ss.always_prepared = false
              ss.save!
              added_links += 1
            end
          end
        end

        puts "[spells] Class links: added=#{added_links} warnings=#{warnings} sync=#{sync}"
      else
        puts "[spells] Skipping class links: file not found #{idx_path}"
      end
    rescue => e
      puts "[spells] ERROR while linking class spell lists: #{e.class} #{e.message}"
    end
  end
end


