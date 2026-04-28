# frozen_string_literal: true

module Admin
  # Remove referências a uma Spell das fichas antes de apagar o registro:
  # - metadata.spell_selections (cantrips / known / spellbook / prepared)
  # - metadata.class_choices.per_level[*] (cantrips, spells, segredos, arcano místico, etc.)
  #
  # Usado só por DELETE admin com `force=true`. IDs similares por string (ex.: "304" vs 304).
  class SpellForceDeletePurgeService
    def initialize(spell)
      @spell = spell
    end

    def call
      sheet_ids = affected_sheet_ids
      return if sheet_ids.empty?

      tokens = match_tokens
      Sheet.where(id: sheet_ids).find_each do |sheet|
        meta = (sheet.metadata || {}).deep_dup.deep_stringify_keys
        next if meta.blank?

        purge_spell_selections!(meta, tokens)
        purge_class_choices!(meta, tokens)

        sheet.update_column(:metadata, meta) # sem validações; evita efeitos colaterais de save
      end
    end

    private

    def affected_sheet_ids
      sk_ids = SheetKnownSpell.where(spell_id: @spell.id).distinct.pluck(:sheet_klass_id)
      from_known = SheetKlass.where(id: sk_ids).distinct.pluck(:sheet_id)
      from_prep = SheetPreparedSpell.where(spell_id: @spell.id).distinct.pluck(:sheet_id)
      (from_known + from_prep).uniq
    end

    def match_tokens
      [
        @spell.id.to_s,
        @spell.api_index.to_s,
        @spell.name.to_s
      ].map(&:strip).reject(&:blank?).uniq
    end

    def token_matches?(raw, tokens)
      case raw
      when Integer
        raw == @spell.id
      when Hash
        h = raw.stringify_keys
        sid = h['id'].to_s
        return true if sid.present? && sid == @spell.id.to_s
        api = h['api_index'].to_s
        return true if api.present? && tokens.include?(api)
        n = h['name'].to_s
        return true if n.present? && n.strip == @spell.name.to_s.strip
        false
      else
        s = raw.to_s.strip
        return false if s.blank?
        tokens.any? { |t| s == t } || s == @spell.id.to_s
      end
    end

    def purge_array!(arr, tokens)
      return arr unless arr.is_a?(Array)
      arr.reject { |el| token_matches?(el, tokens) }
    end

    def purge_spell_selections!(meta, tokens)
      sel = meta['spell_selections']
      return unless sel.is_a?(Hash)

      sel = sel.stringify_keys
      %w[cantrips known spellbook prepared].each do |k|
        next unless sel[k].is_a?(Array)
        sel[k] = purge_array!(sel[k], tokens)
      end
      meta['spell_selections'] = sel
    end

    def purge_progression_row!(row, tokens)
      return unless row.is_a?(Hash)

      %w[cantrips spells learn_any_class_spells].each do |key|
        next unless row[key].is_a?(Array)
        row[key] = purge_array!(row[key], tokens)
      end

      row.keys.each do |k|
        ks = k.to_s
        next unless ks.match?(/\A(magical_secrets_|mystic_arcanum_)/)

        v = row[k]
        if v.is_a?(Array)
          row[k] = purge_array!(v, tokens)
        elsif token_matches?(v, tokens)
          row[k] = []
        end
      end
    end

    def purge_class_choices!(meta, tokens)
      cc = meta['class_choices']
      return unless cc.is_a?(Hash) && cc['per_level'].is_a?(Hash)

      cc['per_level'].each_value do |row|
        next unless row.is_a?(Hash)
        purge_progression_row!(row, tokens)
        fc = row['featureChoices']
        purge_progression_row!(fc, tokens) if fc.is_a?(Hash)
      end
    end
  end
end
