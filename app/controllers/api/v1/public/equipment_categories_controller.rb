require 'net/http'
require 'uri'

class Api::V1::Public::EquipmentCategoriesController < ApplicationController
  BASE = 'https://www.dnd5eapi.co'.freeze

  # GET /api/v1/public/equipment_categories/:id
  def show
    idx = params[:id].to_s.downcase
    local = local_equipment_category(idx)
    return render json: local, status: :ok if local

    data = fetch_json("/api/2014/equipment-categories/#{idx}") || fetch_json("/api/equipment-categories/#{idx}")
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
    Rails.logger.warn("EquipmentCategories proxy failed: #{e.class}: #{e.message}")
    nil
  end

  def local_equipment_category(idx)
    return nil unless defined?(EquipmentCatalog) || defined?(EquipmentRules)
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
