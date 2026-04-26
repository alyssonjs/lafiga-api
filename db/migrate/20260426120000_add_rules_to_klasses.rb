# frozen_string_literal: true

# Fonte de verdade futura para regras de classe (substitui gradualmente ClassRules::CLASS_RULES).
# null ou {} => continua a usar o hash em `class_rules.rb` para esse api_index.
class AddRulesToKlasses < ActiveRecord::Migration[6.0]
  def change
    add_column :klasses, :rules, :jsonb, null: true
  end
end
