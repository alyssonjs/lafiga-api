# Criatura tem PROFICIÊNCIA — em perícia e em teste de resistência. O bestiário
# já guarda as duas (`payload.skills`, `payload.savingThrows`) e o modelo de
# companheiro não tinha onde pô-las: a ficha nascia sem nenhuma.
#
# Arrays de texto e não jsonb porque é o que são: uma lista de nomes. As chaves
# de resistência são as siglas de atributo (str…cha).
class AddProficienciesToCompanionTemplates < ActiveRecord::Migration[6.0]
  def change
    add_column :companion_templates, :skill_proficiencies, :text, array: true, default: []
    add_column :companion_templates, :save_proficiencies, :text, array: true, default: []
  end
end
