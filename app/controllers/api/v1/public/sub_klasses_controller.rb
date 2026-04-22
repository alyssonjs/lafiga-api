class Api::V1::Public::SubKlassesController < ApplicationController
  before_action :set_sub_klass, only: [:show, :levels, :always_prepared_spells]

  def index
    sub_klasses = SubKlass.all

    render json: {sub_klasses: sub_klasses}, status: 200
  end

  def show
    render json: {sub_klass: @sub_klass}, status: 200
  end

  def levels
    levels = @sub_klass.sub_klass_levels.includes(:features).to_a
    # Merge grants/choices from levels_json (compiled by rake) if present
    grants_map = begin
      parsed = JSON.parse(@sub_klass.levels_json || '[]')
      parsed.each_with_object({}) do |row, h|
        lvl = row['level'].to_i
        h[lvl] = {
          'grants' => (row['grants'] || {}),
          'choices' => (row['choices'] || {})
        }.compact
      end
    rescue
      {}
    end

    payload = levels.map do |lvl|
      base = {
        id: lvl.id,
        level: lvl.level,
        features: lvl.features.as_json,
      }
      ext = grants_map[lvl.level.to_i] || {}
      base.merge(ext)
    end

    render json: { sub_klass_levels: payload }, status: :ok
  end

  # GET /api/v1/public/sub_klasses/:id/always_prepared_spells?level=3
  def always_prepared_spells
    lvl = params[:level].to_i
    rel = SpellSource.where(source_type: 'SubKlass', source_id: @sub_klass.id, always_prepared: true)
    if lvl > 0
      rel = rel.where('min_class_level IS NULL OR min_class_level <= ?', lvl)
    end
    spells = Spell.where(id: rel.select(:spell_id))
    # Fallback: if DB has no mapping, consult subclass rules (YAML/derived) to assemble list
    if spells.blank?
      begin
        parent_api = @sub_klass.klass&.api_index
        sub_api = @sub_klass.api_index
        if parent_api.present? && sub_api.present?
          subs = ClassRules.available_subclasses(parent_api)
          hit = subs.find { |s| s[:id].to_s == sub_api.to_s }
          if hit && hit[:always_prepared].is_a?(Hash)
            limit = (lvl > 0) ? lvl : 20
            wanted_names = []
            hit[:always_prepared].each do |k, arr|
              next unless k.to_i <= limit
              Array(arr).each { |nm| wanted_names << nm.to_s }
            end
            if wanted_names.any?
              spells = Spell.where(name: wanted_names)
            end
          end
        end
      rescue => _e
        # ignore fallback failures to keep endpoint stable
      end
    end
    render json: { spells: spells }, status: :ok
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def set_sub_klass
    ident = params[:id].to_s
    @sub_klass = SubKlass.find_by(id: ident) || SubKlass.find_by(api_index: ident)
    raise ActiveRecord::RecordNotFound, "SubKlass not found" unless @sub_klass
  rescue StandardError => e
    render json: { error: e.message }, status: :not_found
  end
end
