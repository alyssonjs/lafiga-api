require 'ostruct'

class Api::V1::Public::KlassesController < ApplicationController
  before_action :set_klass, only: [:show, :levels, :subclasses]

  def index
    klasses = Klass.all
    render json: {klasses: klasses}, status: 200
  end
  
  def show
    render json: {klass: @klass}, status: 200
  end

  def levels
    levels = @klass.class_levels.includes(:spellcasting, :features).to_a

    # Build a per-level overlay map for subclass spellcasting, if requested
    overlay = {}
    if params[:subclass_id].present?
      begin
        sub = @klass.sub_klasses.find_by(api_index: params[:subclass_id]) || @klass.sub_klasses.find_by(id: params[:subclass_id])
        subclass_api = sub&.api_index || params[:subclass_id].to_s
        (1..20).each do |lv|
          entry = SubclassSpellcasting.lookup(klass_api: @klass.api_index, subclass_api: subclass_api, level: lv)
          next unless entry
          overlay[lv] = {
            level: entry.slots.keys.map(&:to_i).max || 0,
            cantrips_known: entry.cantrips_known,
            spells_known: entry.spells_known,
            spell_slots: entry.slots,
            casting_ability: entry.ability
          }
        end
      rescue => _e
        # ignore overlay errors to keep endpoint stable
      end
    end

    # Serialize manually to guarantee presence of spellcasting key when overlaying
    payload = levels.map do |cl|
      base = {
        id: cl.id,
        klass_id: cl.klass_id,
        level: cl.level,
        prof_bonus: cl.prof_bonus,
        ability_score_bonuses: cl.ability_score_bonuses,
        features: cl.features.as_json
      }
      sc = cl.spellcasting ? cl.spellcasting.as_json : nil
      sc ||= overlay[cl.level.to_i]
      base[:spellcasting] = sc if sc.present?
      base
    end

    render json: { class_levels: payload }, status: :ok
  end

  def subclasses
    subclasses = ClassRules.available_subclasses(@klass.api_index)
    
    render json: {
      klass: {
        id: @klass.id,
        name: @klass.name,
        api_index: @klass.api_index
      },
      subclasses: subclasses
    }, status: :ok
  end

  private

  def set_klass
    ident = params[:id].to_s
    @klass = Klass.find_by(id: ident) || Klass.find_by(api_index: ident)
    raise ActiveRecord::RecordNotFound, "Klass not found" unless @klass
  rescue StandardError => e
    render json: { error: e.message }, status: :not_found
  end
end
