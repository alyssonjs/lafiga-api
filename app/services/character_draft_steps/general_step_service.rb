module CharacterDraftSteps
  class GeneralStepService < BaseStepService
    def step_key = 'general'

    protected

    def apply!(merged)
      keys = %w[name playerName isNPC npcRole npcFaction npcLocation npcStatus dmNotes]
      keys.each do |k|
        next unless data.key?(k)
        v = data[k]
        # ZS6 do segundo audit: campos de texto eram persistidos sem strip — o
        # warn de "name vazio" so disparava se o nome fosse 100% vazio. Strings
        # so de espaco ("   ") passavam como validas, gerando personagens com
        # nome em branco visivel. Agora normalizamos no apply.
        v = v.strip if v.is_a?(String)
        merged[k] = v
      end

      if data.key?('level')
        new_level = [[data['level'].to_i, 1].max, 20].min
        merged['level'] = new_level
      end

      warn!('name vazio') if merged['name'].to_s.strip.empty?
    end

    def invalidate!(prev, merged)
      # Level downgrade trims levelChoices. Same logic as front mergeDraftPartialWithCleanup.
      prev_lv = prev['level'].to_i
      new_lv  = merged['level'].to_i
      return if new_lv >= prev_lv

      lc = Array(merged['levelChoices'])
      kept = lc.select { |row| row['level'].to_i <= new_lv }
      if kept.length != lc.length
        merged['levelChoices'] = kept
        clear!('levelChoices')
      end
      merged['progressionSubLevel'] = [merged['progressionSubLevel'].to_i, [2, new_lv].max].min

      # ZS2 do segundo audit: a versao antiga so podava `levelChoices` no
      # downgrade, mas spellSelections (cantrips/conhecidos/preparadas) nao era
      # revisada. Resultado: personagem cai de nivel 5 para nivel 1 mas
      # mantinha 4 cantrips e magias de nivel 3 conhecidas. Para conservadores
      # (Cleric/Druid/Sorcerer/Wizard etc.), recortamos qualquer chave numerica
      # > new_lv em spellSelections.
      sel = merged['spellSelections']
      return unless sel.is_a?(Hash)

      changed = false
      sel.each_value do |bucket|
        next unless bucket.is_a?(Hash)
        bucket.keys.each do |lv_key|
          next unless lv_key.to_s.match?(/\A\d+\z/)
          if lv_key.to_i > new_lv
            bucket.delete(lv_key)
            changed = true
          end
        end
      end
      clear!('spellSelections') if changed
    end
  end
end
