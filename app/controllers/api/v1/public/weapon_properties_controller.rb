require 'net/http'
require 'uri'

class Api::V1::Public::WeaponPropertiesController < ApplicationController
  BASE = 'https://www.dnd5eapi.co'.freeze

  # GET /api/v1/public/weapon_properties/:id
  def show
    idx = params[:id]
    data = fetch_json("/api/2014/weapon-properties/#{idx}") || fetch_json("/api/weapon-properties/#{idx}")
    if data
      render json: data, status: :ok
    else
      render json: { error: 'not available' }, status: :not_found
    end
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
    Rails.logger.warn("WeaponProperties proxy failed: #{e.class}: #{e.message}")
    nil
  end
end

