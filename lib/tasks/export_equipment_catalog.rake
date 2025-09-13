namespace :equipment do
  desc 'Export EquipmentRules into config/equipment.yml (merging existing entries)'
  task export_yaml: :environment do
    require 'yaml'

    rules = EquipmentRules

    weapons_rules = rules::WEAPON_TABLE rescue {}
    armors_rules  = rules::ARMOR_TABLE  rescue {}
    shields_rules = rules::SHIELD_INDEXES rescue ['shield']

    dest_path = Rails.root.join('config', 'equipment.yml')
    existing = if File.exist?(dest_path)
      YAML.safe_load(File.read(dest_path)) || {}
    else
      {}
    end

    existing['weapons'] ||= {}
    existing['armors']  ||= {}
    existing['shields'] ||= Array(shields_rules)

    # Helper to titleize names
    titleize = ->(idx) { idx.to_s.tr('-', ' ').split.map { |w| w[0] ? w[0].upcase + w[1..] : w }.join(' ') }

    # Build weapons
    weapons_out = existing['weapons'].dup
    weapons_rules.each do |idx, row|
      props = []
      props << 'ammunition' if row[:type] == 'ranged' && !row[:thrown]
      props << 'finesse'    if row[:finesse]
      props << 'heavy'      if row[:heavy]
      props << 'light'      if row[:light]
      props << 'loading'    if row[:loading]
      props << 'reach'      if row[:reach]
      props << 'special'    if row[:special]
      props << 'thrown'     if row[:thrown]
      props << 'two-handed' if row[:hands].to_i == 2 && !row[:versatile]
      props << 'versatile'  if row[:versatile]

      wrow = {
        'name' => titleize.call(idx),
        'type' => row[:type],
        'hands' => row[:hands],
        'category' => row[:category],
        'damage_die' => row[:damage_die],
        'versatile_die' => row[:versatile_die],
        'properties' => props,
        'range' => row[:range]
      }.compact

      # Merge: keep existing if present, otherwise set
      weapons_out[idx] = (weapons_out[idx] || {}).merge(wrow) { |_k, old, new| old.nil? || old == '' ? new : old }
    end

    # Build armors
    armors_out = existing['armors'].dup
    armors_rules.each do |idx, row|
      arow = {
        'cat' => row[:cat],
        'base' => row[:base],
        'dex_cap' => row[:dex_cap],
        'stealth_dis' => row[:stealth_dis],
        'str_req' => row[:str_req]
      }.compact
      armors_out[idx] = (armors_out[idx] || {}).merge(arow) { |_k, old, new| old.nil? || old == '' ? new : old }
    end

    # Shields
    shields_out = (Array(existing['shields']) + Array(shields_rules)).uniq

    # Sort keys for stability
    weapons_out = weapons_out.sort.to_h
    armors_out  = armors_out.sort.to_h

    out = {
      'weapons' => weapons_out,
      'armors' => armors_out,
      'shields' => shields_out
    }

    File.write(dest_path, out.to_yaml)
    puts "Wrote #{dest_path} with #{weapons_out.size} weapons and #{armors_out.size} armors."
  end
end

