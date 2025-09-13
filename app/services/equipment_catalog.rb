require 'yaml'
require 'ostruct'

class EquipmentCatalog
  class << self
    def normalize_index(key)
      (key || '').to_s.downcase.strip.gsub(' ', '-').gsub(/ç/,'c').gsub(/á|à|ã|â/,'a').gsub(/é|ê/,'e').gsub(/í/,'i').gsub(/ó|ô|õ/,'o').gsub(/ú/,'u')
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
      @data['shields'] ||= ['shield']
      @data
    rescue => e
      Rails.logger.warn("EquipmentCatalog load failed: #{e.class}: #{e.message}")
      @data = { 'weapons' => {}, 'armors' => {}, 'shields' => ['shield'] }
    end

    def weapon_row(idx)
      key = normalize_index(idx)
      w = data['weapons'][key]
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
      a = data['armors'][key]
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
      Array(data['shields']).map { |s| normalize_index(s) }
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
  end
end
