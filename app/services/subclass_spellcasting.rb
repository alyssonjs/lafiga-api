# frozen_string_literal: true

require 'yaml'

# Lightweight lookup for subclass-specific spellcasting progressions
# Backed by config/subclass_spellcasting.yml
class SubclassSpellcasting
  Entry = Struct.new(
    :ability,            # e.g., 'CHA'
    :list_source_klass,  # e.g., 'sorcerer' (api_index of the class that defines the spell list)
    :cantrips_known,     # Integer for this class level
    :spells_known,       # Integer for this class level
    :slots,              # Hash like { '1'=>2, '2'=>1 }
    keyword_init: true
  )

  def self.yml
    @yml ||= begin
      path = Rails.root.join('config', 'subclass_spellcasting.yml')
      File.exist?(path) ? YAML.load_file(path) : {}
    rescue
      {}
    end
  end

  # Returns an Entry for the given klass/subclass pair at a specific class level (or nil)
  # klass_api: e.g., 'barbarian'
  # subclass_api: e.g., 'barbaro-cicatrizes-runicas'
  # level: Integer (class level within that class)
  def self.lookup(klass_api:, subclass_api:, level:)
    data = yml.dig(klass_api.to_s, subclass_api.to_s)
    return nil unless data

    # Find the nearest level row <= level
    rows = (data['table'] || {}).keys.map(&:to_i).sort
    return nil if rows.empty?
    key = rows.select { |lv| lv <= level.to_i }.max
    return nil unless key

    row = (data['table'][key.to_s] || {})
    Entry.new(
      ability: (data['ability'] || data[:ability] || 'CHA').to_s.upcase,
      list_source_klass: (data['list_source_klass_api'] || data[:list_source_klass_api] || nil).to_s,
      cantrips_known: row['cantrips'] || row[:cantrips] || 0,
      spells_known: row['spells'] || row[:spells] || 0,
      slots: normalize_slots(row['slots'] || row[:slots])
    )
  end

  def self.normalize_slots(val)
    case val
    when Hash
      # already in the expected format
      val.transform_keys(&:to_s)
    when Array
      # array like [4,2] => { '1'=>4, '2'=>2 }
      out = {}
      val.each_with_index { |qty, idx| out[(idx + 1).to_s] = qty }
      out
    else
      {}
    end
  end
end

