module CharacterDraftSteps
  class EquipmentStepService < BaseStepService
    def step_key = 'equipment'

    protected

    def apply!(merged)
      # ZS4 do segundo audit: PATCH so com `equipmentMode` (ex. trocar de
      # 'choices' para 'gold') deixava `equipmentChoices`/`equipmentGenericSelections`
      # do preset anterior intactos. O front entendia o draft como hibrido
      # (gold + choices), gerando inventario duplicado no provision. Quando o
      # mode muda, a flag de modo abandona o preset oposto explicitamente.
      if data.key?('equipmentMode') && merged['equipmentMode'] != data['equipmentMode']
        new_mode = data['equipmentMode']
        if new_mode.to_s == 'gold'
          merged['equipmentChoices'] = []
          merged['equipmentGenericSelections'] = {}
          clear!('equipmentChoices')
        elsif new_mode.to_s == 'choices'
          merged['startingGoldRolled'] = nil
          clear!('startingGoldRolled')
        end
        merged['equipmentMode'] = new_mode
      elsif data.key?('equipmentMode')
        merged['equipmentMode'] = data['equipmentMode']
      end
      merged['equipmentChoices'] = Array(data['equipmentChoices']) if data.key?('equipmentChoices')
      merged['equipmentGenericSelections'] = (data['equipmentGenericSelections'] || {}) if data.key?('equipmentGenericSelections')
      merged['startingGoldRolled'] = data['startingGoldRolled'] if data.key?('startingGoldRolled')
    end
  end
end
