module CharacterDraftSteps
  # Per-level save: writes ONLY draft_data['levelChoices'][N-2] when `level` is provided.
  # When `level` is omitted, accepts the full `levelChoices` array (legacy bulk save).
  # Side-effect: spellSelections (global) replaced when sent.
  class ProgressionStepService < BaseStepService
    def step_key = 'progression'

    protected

    def apply!(merged)
      merged['levelChoices'] ||= []

      if level && level >= 2
        # ZX3 do segundo audit (paridade com B7.1 do ProgressionEditService):
        # antes era `existing[idx] = row` direto. PATCH parcial editando so `hp` do
        # nivel 4 descartava `feat`, `expertise`, `spells`, `subclassChoice` etc.
        # salvos previamente naquele nivel. Agora deep_merge: PATCH sobrescreve
        # apenas o que veio, preserva o resto. Para zerar uma chave especifica,
        # caller manda `nil`/`[]` explicito.
        #
        # ZS3 do segundo audit: passamos pelo LevelChoiceNormalizer DEPOIS do
        # merge para garantir que o front possa enviar `asiChoice` (shape do
        # wizard) e que o backend persista no shape canonico `asi`. Antes
        # creation guardava `asiChoice` literalmente, e edit guardava `asi`,
        # gerando drift entre fluxos.
        patch_row = (data['levelChoice'] || {}).deep_dup
        patch_row['level'] = level

        existing = merged['levelChoices'].dup
        idx = existing.find_index { |r| r['level'].to_i == level }
        if idx
          existing_row = (existing[idx] || {}).deep_dup
          merged_row = existing_row.deep_merge(patch_row)
          if patch_row.key?('asi') || patch_row.key?(:asi)
            merged_row['asi'] = patch_row['asi'] || patch_row[:asi]
          end
          existing[idx] = merged_row
        else
          existing << patch_row
          existing.sort_by! { |r| r['level'].to_i }
        end
        idx ||= existing.find_index { |r| r['level'].to_i == level }
        existing[idx] = LevelChoiceNormalizer.normalize_row(existing[idx]) if idx
        merged['levelChoices'] = existing
      elsif data.key?('levelChoices')
        merged['levelChoices'] = Array(data['levelChoices']).map { |r| LevelChoiceNormalizer.normalize_row(r) }
      end

      # ZX3 (paridade com B7.2 do ProgressionEditService): antes era `=` direto.
      # PATCH com so `cantrips` zerava `known`/`prepared`/`spellbook` salvos.
      # Agora deep_merge: arrays nao mencionados sao preservados; quem QUER zerar
      # uma sub-aba envia `[]` explicito.
      if data.key?('spellSelections') && data['spellSelections'].is_a?(Hash)
        prev_sel = merged['spellSelections'].is_a?(Hash) ? merged['spellSelections'].deep_dup : {}
        merged['spellSelections'] = prev_sel.deep_merge(data['spellSelections'])
      end

      merged['level1HpChoice'] = data['level1HpChoice'] if data.key?('level1HpChoice')

      merged['progressionSubLevel'] = data['progressionSubLevel'].to_i if data.key?('progressionSubLevel')

      char_level = merged['level'].to_i
      if char_level > 1 && merged['levelChoices'].length > (char_level - 1)
        warn!('levelChoices excedem level atual')
      end
    end
  end
end
