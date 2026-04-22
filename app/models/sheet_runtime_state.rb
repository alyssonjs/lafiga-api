# Estado mutável de uma ficha (HP fica em `sheets`; tudo MENOS HP fica aqui).
#
# - Default safe-by-construction (defaults da migration garantem leitura sem
#   nil); model reforça via `before_validation` para o caso de updates parciais
#   esquecerem campos.
# - `as_payload` é a forma canônica usada pelo controller e pelo summary.
class SheetRuntimeState < ApplicationRecord
  EXHAUSTION_RANGE = (0..6).freeze

  DEATH_SAVES_DEFAULT = { 'successes' => 0, 'failures' => 0, 'stable' => false }.freeze
  HIT_DICE_DIES = %w[d6 d8 d10 d12].freeze

  belongs_to :sheet

  validates :sheet_id, uniqueness: true
  validates :exhaustion, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 6 }
  validate  :death_saves_must_be_in_range

  before_validation :normalize_jsonb_fields

  # Forma canônica para serialização. Sempre devolve chaves estáveis.
  def as_payload
    {
      death_saves: normalized_death_saves,
      hit_dice_used: normalized_hit_dice_used,
      exhaustion: exhaustion.to_i,
      conditions: Array(conditions),
      concentration: concentration,
      spell_slots_used: Hash(spell_slots_used),
      class_resources_used: Hash(class_resources_used),
      last_short_rest_at: last_short_rest_at,
      last_long_rest_at:  last_long_rest_at,
      updated_at: updated_at
    }
  end

  # Aplica patch parcial, fazendo merge inteligente em campos JSONB de mapa
  # (hit_dice_used, spell_slots_used, class_resources_used). Para campos
  # escalares (exhaustion) ou snapshot completo (death_saves, conditions,
  # concentration) faz substituição.
  def apply_patch!(patch)
    h =
      if patch.is_a?(ActionController::Parameters)
        patch.to_unsafe_h
      elsif patch.respond_to?(:to_h)
        patch.to_h
      else
        Hash(patch)
      end
    h = h.deep_stringify_keys

    self.death_saves          = h['death_saves'] if h.key?('death_saves')
    self.exhaustion           = h['exhaustion'].to_i if h.key?('exhaustion')
    self.conditions           = Array(h['conditions']) if h.key?('conditions')
    self.concentration        = h['concentration'] if h.key?('concentration')

    if h.key?('hit_dice_used')
      self.hit_dice_used = Hash(hit_dice_used).merge(Hash(h['hit_dice_used']).transform_values(&:to_i))
    end

    if h.key?('spell_slots_used')
      self.spell_slots_used = Hash(spell_slots_used).merge(Hash(h['spell_slots_used']).transform_values(&:to_i))
    end

    if h.key?('class_resources_used')
      self.class_resources_used = Hash(class_resources_used).merge(Hash(h['class_resources_used']).transform_values(&:to_i))
    end

    save!
    self
  end

  private

  def normalize_jsonb_fields
    self.death_saves          = normalized_death_saves
    self.hit_dice_used        = normalized_hit_dice_used
    self.spell_slots_used     = Hash(spell_slots_used)
    self.class_resources_used = Hash(class_resources_used)
    self.conditions           = Array(conditions)
  end

  def normalized_death_saves
    base = DEATH_SAVES_DEFAULT.dup
    Hash(death_saves).each do |k, v|
      key = k.to_s
      next unless base.key?(key)
      base[key] = key == 'stable' ? !!v : [[v.to_i, 0].max, 3].min
    end
    base
  end

  def normalized_hit_dice_used
    base = {}
    Hash(hit_dice_used).each do |k, v|
      key = k.to_s
      next unless HIT_DICE_DIES.include?(key)
      base[key] = [v.to_i, 0].max
    end
    base
  end

  def death_saves_must_be_in_range
    ds = Hash(death_saves)
    %w[successes failures].each do |k|
      v = ds[k].to_i
      errors.add(:death_saves, "#{k} fora do intervalo 0..3") if v < 0 || v > 3
    end
  end
end
