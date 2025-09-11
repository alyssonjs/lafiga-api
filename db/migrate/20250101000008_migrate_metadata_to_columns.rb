class MigrateMetadataToColumns < ActiveRecord::Migration[6.0]
  def up
    # Migrar dados do metadata para as novas colunas
    Sheet.find_each do |sheet|
      metadata = sheet.metadata || {}
      
      # Migrar alignment
      if metadata['alignment'].present?
        alignment = Alignment.find_by(api_index: metadata['alignment']['index'])
        sheet.update_column(:alignment_id, alignment&.id)
      end
      
      # Migrar background
      if metadata['background_key'].present?
        background = Background.find_by(api_index: metadata['background_key'])
        sheet.update_column(:background_id, background&.id)
        sheet.update_column(:background_key, metadata['background_key'])
      end
      
      # Migrar current_level
      if metadata['current_level'].present?
        sheet.update_column(:current_level, metadata['current_level'])
      end
      
      # Migrar race_choices
      if metadata['race_choices'].present?
        sheet.update_column(:race_choices, metadata['race_choices'])
      end
      
      # Migrar class_choices
      if metadata['class_choices'].present?
        sheet.update_column(:class_choices, metadata['class_choices'])
      end
      
      # Migrar summaries
      if metadata['race_summary'].present?
        sheet.update_column(:race_summary, metadata['race_summary'])
      end
      
      if metadata['class_summary'].present?
        sheet.update_column(:class_summary, metadata['class_summary'])
      end
      
      if metadata['background_summary'].present?
        sheet.update_column(:background_summary, metadata['background_summary'])
      end
      
      if metadata['features_by_level'].present?
        sheet.update_column(:features_by_level, metadata['features_by_level'])
      end
      
      # Migrar race_bonuses_applied
      if metadata['race_bonuses_applied'].present?
        sheet.update_column(:race_bonuses_applied, metadata['race_bonuses_applied'])
      end
    end
  end

  def down
    # Reverter migração - mover dados de volta para metadata
    Sheet.find_each do |sheet|
      metadata = sheet.metadata || {}
      
      # Reverter alignment
      if sheet.alignment_id.present?
        alignment = Alignment.find(sheet.alignment_id)
        metadata['alignment'] = {
          'index' => alignment.api_index,
          'name' => alignment.name,
          'desc' => alignment.desc
        }
      end
      
      # Reverter background
      if sheet.background_id.present?
        background = Background.find(sheet.background_id)
        metadata['background_key'] = background.api_index
        metadata['background'] = background.name
      end
      
      # Reverter current_level
      if sheet.current_level.present?
        metadata['current_level'] = sheet.current_level
      end
      
      # Reverter race_choices
      if sheet.race_choices.present?
        metadata['race_choices'] = sheet.race_choices
      end
      
      # Reverter class_choices
      if sheet.class_choices.present?
        metadata['class_choices'] = sheet.class_choices
      end
      
      # Reverter summaries
      if sheet.race_summary.present?
        metadata['race_summary'] = sheet.race_summary
      end
      
      if sheet.class_summary.present?
        metadata['class_summary'] = sheet.class_summary
      end
      
      if sheet.background_summary.present?
        metadata['background_summary'] = sheet.background_summary
      end
      
      if sheet.features_by_level.present?
        metadata['features_by_level'] = sheet.features_by_level
      end
      
      # Reverter race_bonuses_applied
      if sheet.race_bonuses_applied.present?
        metadata['race_bonuses_applied'] = sheet.race_bonuses_applied
      end
      
      sheet.update_column(:metadata, metadata)
    end
  end
end
