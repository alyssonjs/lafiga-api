module CharacterDraftSteps
  class ClassStepService < BaseStepService
    def step_key = 'class'

    protected

    def apply!(merged)
      # Snapshot ANTES de mutar para que o branch ZX2 (deep_merge vs replace)
      # consiga distinguir "PATCH parcial mesma classe" de "troca de classe
      # com level1Choices novas".
      prev_class_id = merged.dig('selectedClass', 'id') || merged['_classId']

      if data.key?('classId')
        merged['_classId'] = data['classId']
        merged['selectedClass'] = data['classId'] ? { 'id' => data['classId'] } : nil
      end
      if data.key?('subclassId')
        merged['selectedSubclass'] = data['subclassId'] ? { 'id' => data['subclassId'] } : nil
      end
      merged['classSkillPicks'] = Array(data['classSkillPicks']) if data.key?('classSkillPicks')

      # ZX2 do segundo audit: antes era `merged['level1Choices'] = (data['level1Choices'] || {})`,
      # que SUBSTITUIA o hash inteiro. PATCH parcial com so `{ fighting_style: 'defense' }`
      # apagava `skills`, `expertise`, `instruments`, etc. ja salvos. Paridade com
      # ProgressionEditService::B7.1 (deep_merge em per_level[N]) e ClassEditService
      # (que faz `row1.merge!(data['level1Choices'])` na MESMA classe).
      #
      # Excecao: TROCA de classe com PATCH atomico {classId: novo, level1Choices: {...}}.
      # Nesse caso o cliente quer sobrescrever (instrumentos do Bardo nao fazem sentido
      # pro Guerreiro). O cleanup destrutivo continua em `invalidate!` (B4.1) para o
      # caso onde a troca chega SEM level1Choices reenviadas.
      if data.key?('level1Choices')
        new_class_id = merged.dig('selectedClass', 'id') || merged['_classId']
        class_changed = prev_class_id.present? && new_class_id.present? && prev_class_id.to_s != new_class_id.to_s

        patch_l1 = data['level1Choices'].is_a?(Hash) ? data['level1Choices'] : {}
        merged['level1Choices'] =
          if class_changed
            patch_l1
          else
            prev_l1 = merged['level1Choices'].is_a?(Hash) ? merged['level1Choices'].deep_dup : {}
            prev_l1.deep_merge(patch_l1)
          end
      end
    end

    def invalidate!(prev, merged)
      prev_id = prev.dig('selectedClass', 'id') || prev['_classId']
      new_id  = merged.dig('selectedClass', 'id') || merged['_classId']
      return if prev_id.to_s == new_id.to_s

      # Bug B4.1 do relatorio de auditoria de steps: o invalidate! historicamente
      # sobrescrevia level1Choices/subclass/spellSelections sempre que o id
      # mudava — incluindo o caso de PATCH atomico {classId, level1Choices,
      # subclassId, ...} (criacao fresh ou troca consciente do cliente).
      # Resultado: o cliente enviava todas as escolhas certas no mesmo request
      # e via tudo apagado quando o draft chegava de volta.
      #
      # Estrategia: so apagar o que NAO veio no mesmo PATCH. Se o usuario
      # enviou `level1Choices` junto, claramente quer manter aquelas escolhas;
      # apply! ja colocou o valor certo em `merged`.
      destructive = prev_id.present? && new_id.present?
      keys_to_clear = []

      unless data.key?('subclassId')
        merged['selectedSubclass'] = nil
        keys_to_clear << 'selectedSubclass'
      end
      unless data.key?('level1Choices')
        merged['level1Choices'] = {}
        keys_to_clear << 'level1Choices'
      end
      unless data.key?('levelChoices')
        merged['levelChoices'] = []
        keys_to_clear << 'levelChoices'
      end
      unless data.key?('level1HpChoice')
        merged['level1HpChoice'] = nil
        keys_to_clear << 'level1HpChoice'
      end
      unless data.key?('spellSelections')
        merged['spellSelections'] = { 'cantrips' => [], 'known' => [], 'spellbook' => [], 'prepared' => [] }
        keys_to_clear << 'spellSelections'
      end

      # Gap G8.2 do relatorio de auditoria de steps: equipment do wizard
      # (mode/choices/generic/startingGold) era especifico da classe ANTIGA
      # — pacote inicial Bardo nao faz sentido para Mago. Mesma logica de
      # B4.1: so zera o que nao veio no MESMO PATCH (cliente que envia
      # `{classId, equipmentMode, equipmentChoices, ...}` atomicamente
      # mantem suas escolhas).
      unless data.key?('equipmentMode')
        merged['equipmentMode'] = nil
        keys_to_clear << 'equipmentMode'
      end
      unless data.key?('equipmentChoices')
        merged['equipmentChoices'] = []
        keys_to_clear << 'equipmentChoices'
      end
      unless data.key?('equipmentGenericSelections')
        merged['equipmentGenericSelections'] = {}
        keys_to_clear << 'equipmentGenericSelections'
      end
      unless data.key?('startingGoldRolled')
        merged['startingGoldRolled'] = nil
        keys_to_clear << 'startingGoldRolled'
      end

      merged['progressionSubLevel'] = 2

      keys_to_clear.each { |k| clear!(k, reason: DESTRUCTIVE_REASONS[:class_changed], confirm: destructive) }
    end
  end
end
