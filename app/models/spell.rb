class Spell < ApplicationRecord
  # spell_id => lista de `klasses.api_index` ligados via SpellSource (so tipo Klass).
  def self.klass_api_indexes_by_spell_id(spell_ids)
    return {} if spell_ids.blank?

    pairs = SpellSource.where(source_type: 'Klass', spell_id: spell_ids)
      .joins('INNER JOIN klasses ON klasses.id = spell_sources.source_id')
      .pluck(:spell_id, 'klasses.api_index')
    pairs.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(sid, api), memo|
      memo[sid] << api if api.present?
    end.transform_values(&:uniq)
  end
end
