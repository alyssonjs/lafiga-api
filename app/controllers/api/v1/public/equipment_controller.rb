require 'net/http'
require 'uri'

class Api::V1::Public::EquipmentController < ApplicationController
  BASE = 'https://www.dnd5eapi.co'.freeze

  # GET /api/v1/public/equipment/:index
  def show
    idx = (params[:id] || params[:index]).to_s.downcase
    local = local_equipment(idx)
    return render json: local, status: :ok if local

    data = fetch_json("/api/2014/equipment/#{idx}") || fetch_json("/api/equipment/#{idx}")
    return render json: data, status: :ok if data

    render json: { error: 'not available' }, status: :not_found
  end

  # GET /api/v1/public/equipment_categories/:index
  def categories
    idx = (params[:id] || params[:index]).to_s.downcase
    local = local_equipment_category(idx)
    return render json: local, status: :ok if local

    data = fetch_json("/api/2014/equipment-categories/#{idx}") || fetch_json("/api/equipment-categories/#{idx}")
    return render json: data, status: :ok if data

    render json: { error: 'not available' }, status: :not_found
  end

  # GET /api/v1/public/weapon_properties/:index
  def weapon_properties
    idx = (params[:id] || params[:index]).to_s.downcase
    local = local_weapon_property(idx)
    return render json: local, status: :ok if local

    data = fetch_json("/api/2014/weapon-properties/#{idx}") || fetch_json("/api/weapon-properties/#{idx}")
    return render json: data, status: :ok if data

    render json: { error: 'not available' }, status: :not_found
  end

  private

  def fetch_json(path)
    url = URI.join(BASE, path)
    res = Net::HTTP.start(url.host, url.port, use_ssl: url.scheme == 'https', read_timeout: 5, open_timeout: 3) do |http|
      req = Net::HTTP::Get.new(url)
      http.request(req)
    end
    return nil unless res.is_a?(Net::HTTPSuccess)
    JSON.parse(res.body) rescue nil
  rescue => e
    Rails.logger.warn("Equipment proxy failed: #{e.class}: #{e.message}")
    nil
  end

  # Build a weapon-property response from our local EquipmentRules table
  def local_weapon_property(idx)
    # Map accepted indexes to a predicate over EquipmentRules::WEAPON_TABLE rows
    predicates = {
      'finesse'     => ->(row) { !!row[:finesse] },
      'leve'        => ->(row) { !!row[:light] }, # alias pt-br
      'light'       => ->(row) { !!row[:light] },
      'pesada'      => ->(row) { !!row[:heavy] }, # alias pt-br
      'heavy'       => ->(row) { !!row[:heavy] },
      'alcance'     => ->(row) { !!row[:reach] }, # alias pt-br
      'reach'       => ->(row) { !!row[:reach] },
      'carregamento'=> ->(row) { !!row[:loading] }, # alias pt-br
      'loading'     => ->(row) { !!row[:loading] },
      'especial'    => ->(row) { !!row[:special] }, # alias pt-br
      'special'     => ->(row) { !!row[:special] },
      'arremesso'   => ->(row) { !!row[:thrown] }, # alias pt-br
      'thrown'      => ->(row) { !!row[:thrown] },
      'duas-maos'   => ->(row) { row[:hands].to_i == 2 && !row[:versatile] }, # alias pt-br
      'two-handed'  => ->(row) { row[:hands].to_i == 2 && !row[:versatile] },
      'versatil'    => ->(row) { !!row[:versatile] }, # alias pt-br
      'versatile'   => ->(row) { !!row[:versatile] },
      'municao'     => ->(row) { row[:type] == 'ranged' && !row[:thrown] }, # alias pt-br
      'ammunition'  => ->(row) { row[:type] == 'ranged' && !row[:thrown] },
    }

    pred = predicates[idx]
    return nil unless pred

    # Prefer YAML catalog; fall back to EquipmentRules
    if defined?(EquipmentCatalog)
      # Build rows from catalog
      catalog_rows = {}
      (EquipmentCatalog.data['weapons'] || {}).each do |k, _|
        row = EquipmentCatalog.weapon_row(k)
        catalog_rows[k] = row if row
      end
      matched = catalog_rows.select { |_k, row| pred.call(row) }
    else
      matched = {}
    end

    if matched.empty? && defined?(EquipmentRules)
      table = EquipmentRules::WEAPON_TABLE rescue {}
      matched = table.select { |_k, row| pred.call(row) }
    end
    return nil if matched.empty?

    {
      index: idx,
      name: weapon_property_name(idx),
      desc: weapon_property_desc(idx),
      url: "/api/v1/public/weapon_properties/#{idx}",
      weapons: matched.map { |k, _| { index: k, name: k.tr('-', ' '), url: "/api/v1/public/equipment/#{k}" } }
    }
  end

  def weapon_property_name(idx)
    names = {
      'finesse' => 'Finesse',
      'leve' => 'Leve', 'light' => 'Light',
      'pesada' => 'Pesada', 'heavy' => 'Heavy',
      'alcance' => 'Alcance', 'reach' => 'Reach',
      'carregamento' => 'Carregamento', 'loading' => 'Loading',
      'especial' => 'Especial', 'special' => 'Special',
      'arremesso' => 'Arremesso', 'thrown' => 'Thrown',
      'duas-maos' => 'Duas Mãos', 'two-handed' => 'Two-Handed',
      'versatil' => 'Versátil', 'versatile' => 'Versatile',
      'municao' => 'Munição', 'ammunition' => 'Ammunition'
    }
    names[idx] || idx.to_s
  end

  def weapon_property_desc(idx)
    # Minimal helpful descriptions in pt-BR; can be expanded later
    descs = {
      'finesse' => ['Você pode usar seu modificador de Destreza para jogadas de ataque e dano.'],
      'light' => ['Arma leve; adequada para combate com duas armas.'],
      'leve' => ['Arma leve; adequada para combate com duas armas.'],
      'heavy' => ['Criaturas Pequenas sofrem desvantagem nas jogadas de ataque.'],
      'pesada' => ['Criaturas Pequenas sofrem desvantagem nas jogadas de ataque.'],
      'reach' => ['Seu alcance com esta arma aumenta em 1,5 m (5 pés).'],
      'alcance' => ['Seu alcance com esta arma aumenta em 1,5 m (5 pés).'],
      'loading' => ['Você só pode efetuar um ataque com esta arma por Ação/ação bônus, independentemente do total de ataques.'],
      'carregamento' => ['Você só pode efetuar um ataque com esta arma por Ação/ação bônus, independentemente do total de ataques.'],
      'special' => ['Esta arma possui regras especiais; veja a descrição específica da arma.'],
      'especial' => ['Esta arma possui regras especiais; veja a descrição específica da arma.'],
      'thrown' => ['Você pode arremessar a arma para realizar um ataque à distância.'],
      'arremesso' => ['Você pode arremessar a arma para realizar um ataque à distância.'],
      'two-handed' => ['Você precisa de duas mãos para empunhar esta arma.'],
      'duas-maos' => ['Você precisa de duas mãos para empunhar esta arma.'],
      'versatile' => ['Pode ser usada com uma ou duas mãos; dano maior com duas mãos.'],
      'versatil' => ['Pode ser usada com uma ou duas mãos; dano maior com duas mãos.'],
      'ammunition' => ['A arma utiliza munição adequada (setas, virotes, etc.).'],
      'municao' => ['A arma utiliza munição adequada (setas, virotes, etc.).']
    }
    descs[idx] || []
  end

  # Local equipment show: builds from EquipmentRules weapon/armor tables
  def local_equipment(idx)
    return nil unless defined?(EquipmentRules)
    t = if defined?(EquipmentCatalog) && EquipmentCatalog.data['weapons'].present?
      Hash[(EquipmentCatalog.data['weapons'] || {}).map { |k,_| [k, EquipmentCatalog.weapon_row(k)] }]
    else
      EquipmentRules::WEAPON_TABLE rescue nil
    end
    a = if defined?(EquipmentCatalog) && EquipmentCatalog.data['armors'].present?
      Hash[(EquipmentCatalog.data['armors'] || {}).map { |k,_| [k, EquipmentCatalog.armor_row(k)] }]
    else
      EquipmentRules::ARMOR_TABLE  rescue nil
    end

    if t && t[idx]
      row = t[idx]
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

      return {
        index: idx,
        name: idx.tr('-', ' '),
        equipment_category: { index: 'weapon', name: 'Weapon' },
        weapon_category: row[:category].to_s,
        weapon_range: row[:type] == 'ranged' ? 'Ranged' : 'Melee',
        damage: row[:damage_die].to_s.empty? ? nil : { damage_dice: row[:damage_die] },
        two_handed_damage: row[:versatile_die] ? { damage_dice: row[:versatile_die] } : nil,
        range: row[:range] ? { normal: row[:range].split('/').first.to_i, long: row[:range].split('/').last.to_i } : nil,
        properties: props.map { |p| { index: p, name: weapon_property_name(p), url: "/api/v1/public/weapon_properties/#{p}" } }.compact,
        url: "/api/v1/public/equipment/#{idx}"
      }.compact
    end

    if a && a[idx]
      row = a[idx]
      name = idx.tr('-', ' ')
      ac = { base: row[:base], dex_bonus: !row[:dex_cap].to_i.zero?, max_bonus: row[:dex_cap] }
      return {
        index: idx,
        name: name,
        equipment_category: { index: 'armor', name: 'Armor' },
        armor_category: row[:cat].capitalize,
        armor_class: ac,
        str_minimum: row[:str_req],
        stealth_disadvantage: !!row[:stealth_dis],
        url: "/api/v1/public/equipment/#{idx}"
      }.compact
    end

    # Shields (heuristic)
    shields = if defined?(EquipmentCatalog) then EquipmentCatalog.shield_indexes else ['shield'] end
    if shields.any? { |s| idx.include?(s) }
      return {
        index: idx,
        name: idx.tr('-', ' '),
        equipment_category: { index: 'armor', name: 'Armor' },
        armor_category: 'Shield',
        armor_class: { base: 2, dex_bonus: false },
        stealth_disadvantage: false,
        url: "/api/v1/public/equipment/#{idx}"
      }
    end

    nil
  end

  # Local equipment category list from EquipmentRules
  def local_equipment_category(idx)
    return nil unless defined?(EquipmentRules)
    t = if defined?(EquipmentCatalog) && EquipmentCatalog.data['weapons'].present?
      EquipmentCatalog.data['weapons']
    else
      EquipmentRules::WEAPON_TABLE rescue nil
    end
    a = if defined?(EquipmentCatalog) && EquipmentCatalog.data['armors'].present?
      EquipmentCatalog.data['armors']
    else
      EquipmentRules::ARMOR_TABLE  rescue nil
    end
    return nil unless t || a

    items = []
    title = idx

    case idx
    when 'simple-weapons'
      title = 'Simple Weapons'
      items = if defined?(EquipmentCatalog) && t.is_a?(Hash) && t.values.first.is_a?(Hash) && t.values.first['category']
        t.select { |_k, v| v['category'] == 'simple' }.map { |k, _| k }
      else
        t.select { |_k, v| v[:category] == 'simple' }.map { |k, _| k }
      end
    when 'martial-weapons'
      title = 'Martial Weapons'
      items = if defined?(EquipmentCatalog) && t.values.first.is_a?(Hash) && t.values.first['category']
        t.select { |_k, v| v['category'] == 'martial' }.map { |k, _| k }
      else
        t.select { |_k, v| v[:category] == 'martial' }.map { |k, _| k }
      end
    when 'simple-melee-weapons'
      title = 'Simple Melee Weapons'
      items = if defined?(EquipmentCatalog) && t.values.first.is_a?(Hash) && t.values.first['type']
        t.select { |_k, v| v['category'] == 'simple' && v['type'] == 'melee' }.map { |k, _| k }
      else
        t.select { |_k, v| v[:category] == 'simple' && v[:type] == 'melee' }.map { |k, _| k }
      end
    when 'simple-ranged-weapons'
      title = 'Simple Ranged Weapons'
      items = if defined?(EquipmentCatalog) && t.values.first.is_a?(Hash) && t.values.first['type']
        t.select { |_k, v| v['category'] == 'simple' && v['type'] == 'ranged' }.map { |k, _| k }
      else
        t.select { |_k, v| v[:category] == 'simple' && v[:type] == 'ranged' }.map { |k, _| k }
      end
    when 'martial-melee-weapons'
      title = 'Martial Melee Weapons'
      items = if defined?(EquipmentCatalog) && t.values.first.is_a?(Hash) && t.values.first['type']
        t.select { |_k, v| v['category'] == 'martial' && v['type'] == 'melee' }.map { |k, _| k }
      else
        t.select { |_k, v| v[:category] == 'martial' && v[:type] == 'melee' }.map { |k, _| k }
      end
    when 'martial-ranged-weapons'
      title = 'Martial Ranged Weapons'
      items = if defined?(EquipmentCatalog) && t.values.first.is_a?(Hash) && t.values.first['type']
        t.select { |_k, v| v['category'] == 'martial' && v['type'] == 'ranged' }.map { |k, _| k }
      else
        t.select { |_k, v| v[:category] == 'martial' && v[:type] == 'ranged' }.map { |k, _| k }
      end
    when 'armor'
      title = 'Armor'
      items = a.keys + (defined?(EquipmentCatalog) ? EquipmentCatalog.shield_indexes : ['shield'])
    when 'shields'
      title = 'Shields'
      items = (defined?(EquipmentCatalog) ? EquipmentCatalog.shield_indexes : ['shield'])
    else
      return nil
    end

    {
      index: idx,
      name: title,
      equipment: items.map { |k| { index: k, name: k.tr('-', ' '), url: "/api/v1/public/equipment/#{k}" } }
    }
  end
end
