require 'yaml'
require 'ostruct'

class EquipmentCatalog
  class << self
    def normalize_index(key)
      (key || '').to_s.downcase.strip
        .gsub(' ', '-')
        .gsub(/ç/, 'c')
        .gsub(/á|à|ã|â/, 'a')
        .gsub(/é|ê/, 'e')
        .gsub(/í/, 'i')
        .gsub(/ó|ô|õ/, 'o')
        .gsub(/ú/, 'u')
        .gsub(/[^a-z0-9\-]+/, '-')
        .gsub(/-+/, '-')
        .gsub(/^-|-$/, '')
    end

    def data
      return @data if defined?(@data) && @data
      path = Rails.root.join('config', 'equipment.yml')
      @data = if File.exist?(path)
        YAML.safe_load(File.read(path)) || {}
      else
        {}
      end
      @data['weapons'] ||= {}
      @data['armors']  ||= {}
      @data['shields'] ||= default_shields_payload
      @data['gear']    ||= {}
      @data['packs']   ||= {}
      @data['tools']   ||= {}
      @data['consumables'] ||= {}
      @data
    rescue => e
      Rails.logger.warn("EquipmentCatalog load failed: #{e.class}: #{e.message}")
      @data = { 'weapons' => {}, 'armors' => {}, 'shields' => ['shield'] }
    end

    def weapon_row(idx)
      key = normalize_index(idx)
      w = lookup_entry(data['weapons'], key)
      if w
        props = Array(w['properties']).map { |p| normalize_index(p) }
        return {
          type: w['type'],
          hands: (w['hands'] || (props.include?('two-handed') ? 2 : 1)).to_i,
          light: props.include?('light') || props.include?('leve'),
          finesse: props.include?('finesse'),
          versatile: props.include?('versatile') || props.include?('versatil'),
          category: w['category'],
          damage_die: w['damage_die'],
          versatile_die: w['versatile_die'],
          heavy: props.include?('heavy') || props.include?('pesada'),
          reach: props.include?('reach') || props.include?('alcance'),
          loading: props.include?('loading') || props.include?('carregamento'),
          special: props.include?('special') || props.include?('especial'),
          thrown: props.include?('thrown') || props.include?('arremesso'),
          range: w['range']
        }
      end
      # fallback to EquipmentRules
      EquipmentRules::WEAPON_TABLE[EquipmentRules.normalize_index(OpenStruct.new(item_index: key))] rescue nil
    end

    def armor_row(idx)
      key = normalize_index(idx)
      a = lookup_entry(data['armors'], key)
      if a
        return {
          cat: a['cat'],
          base: a['base'],
          dex_cap: a['dex_cap'],
          stealth_dis: !!a['stealth_dis'],
          str_req: a['str_req']
        }
      end
      EquipmentRules::ARMOR_TABLE[key] rescue nil
    end

    def shield_indexes
      raw = data['shields']
      list = case raw
      when Hash
        raw.keys
      when Array
        raw
      when nil
        []
      else
        Array(raw)
      end
      list.map { |s| normalize_index(s) }.uniq
    end

    def list_weapons_by_property(prop)
      idx = normalize_index(prop)
      weapons = data['weapons']
      matched = weapons.select do |_k, w|
        props = Array(w['properties']).map { |p| normalize_index(p) }
        case idx
        when 'ammunition', 'municao'
          (w['type'] == 'ranged') && !props.include?('thrown') && !props.include?('arremesso')
        when 'two-handed', 'duas-maos'
          (w['hands'].to_i == 2) && !props.include?('versatile') && !props.include?('versatil')
        else
          props.include?(idx)
        end
      end

      # if YAML incomplete, consider fallback rules
      if matched.empty?
        t = EquipmentRules::WEAPON_TABLE rescue {}
        matched = t.select do |_k, row|
          case normalize_index(prop)
          when 'ammunition', 'municao' then row[:type] == 'ranged' && !row[:thrown]
          when 'two-handed', 'duas-maos' then row[:hands].to_i == 2 && !row[:versatile]
          when 'finesse' then !!row[:finesse]
          when 'light', 'leve' then !!row[:light]
          when 'heavy', 'pesada' then !!row[:heavy]
          when 'reach', 'alcance' then !!row[:reach]
          when 'loading', 'carregamento' then !!row[:loading]
          when 'special', 'especial' then !!row[:special]
          when 'thrown', 'arremesso' then !!row[:thrown]
          when 'versatile', 'versatil' then !!row[:versatile]
          else false
          end
        end
      end

      matched.keys
    end

    def list_weapons(category: nil, type: nil)
      weapons = data['weapons']
      list = weapons.select do |_k, w|
        ok = true
        ok &&= (w['category'] == category) if category
        ok &&= (w['type'] == type) if type
        ok
      end.keys
      if list.empty?
        t = EquipmentRules::WEAPON_TABLE rescue {}
        list = t.select do |_k, row|
          ok = true
          ok &&= (row[:category] == category) if category
          ok &&= (row[:type] == type) if type
          ok
        end.keys
      end
      list
    end

    def list_armors
      data['armors'].keys.presence || (EquipmentRules::ARMOR_TABLE.keys rescue [])
    end

    # Finds the canonical YAML slug for an item name, alias, or index
    # This is a PUBLIC method used by StartingEquipmentService
    def find_index(name)
      key = normalize_index(name)
      sections = %w[weapons armors gear packs tools consumables]
      sections.each do |section|
        store = data[section] || {}
        next unless store.is_a?(Hash)
        return key if store[key]
        store.each do |slug, row|
          normalized_name = normalize_index(row['name']) if row.is_a?(Hash) && row['name']
          aliases = Array(row['aliases']).map { |a| normalize_index(a) }
          return slug if aliases.include?(key) || normalized_name == key
        end
      end

      shields = data['shields']
      case shields
      when Hash
        return key if shields[key]
        shields.each do |slug, row|
          aliases = Array(row['aliases']).map { |a| normalize_index(a) }
          normalized_name = normalize_index(row['name']) if row['name']
          return slug if aliases.include?(key) || normalized_name == key
        end
      when Array
        shields.each do |slug|
          idx = normalize_index(slug)
          return idx if idx == key
        end
      end
      
      # Also check database items by props aliases
      if defined?(Item)
        item = Item.find_by(api_index: key)
        return item.api_index if item
        # Search by aliases in props
        Item.where("props->>'aliases' IS NOT NULL").find_each do |it|
          aliases = Array(it.props['aliases']).map { |a| normalize_index(a) }
          return it.api_index if aliases.include?(key)
        end
      end
      
      nil
    end

    private

    def default_shields_payload
      {
        'shield' => {
          'name' => 'Escudo',
          'aliases' => %w[escudo shield],
          'ac_bonus' => 2
        }
      }
    end

    def lookup_entry(collection, key)
      return nil unless collection.is_a?(Hash)
      entry = collection[key]
      return entry if entry
      collection.each do |_slug, row|
        aliases = Array(row['aliases']).map { |a| normalize_index(a) }
        return row if aliases.include?(key)
      end
      nil
    end
  end
end
