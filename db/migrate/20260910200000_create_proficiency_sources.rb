# frozen_string_literal: true

# Quem CONCEDE cada proficiência — o índice reverso.
#
# ⚠️ É REGISTRO, não autoridade (decisão de produto, 10/09/2026). Quem de facto
# concede continua a ser `race_rules.yml`, `class_rules.rb`,
# `background_rules.rb` e a coluna do `Feat`. Esta tabela serve para navegar,
# filtrar e auditar — marcar "Anão" aqui NÃO faz anão nenhum ganhar a
# proficiência. O motor de criação de personagem não é tocado.
#
# `origin` separa o que foi DERIVADO das fontes existentes do que o mestre
# associou à mão: sem isso, re-semear apagaria o trabalho dele.
class CreateProficiencySources < ActiveRecord::Migration[6.0]
  def change
    create_table :proficiency_sources do |t|
      t.references :proficiency, null: false, foreign_key: true
      # race · sub_race · klass · sub_klass · background · feat
      t.string :source_type, null: false
      # `api_index`/slug de quem concede — a chave estável.
      t.string :source_key, null: false
      # Rótulo para exibir. Denormalizado de propósito: as fontes vivem em
      # quatro lugares diferentes (YAML, hash Ruby, duas tabelas), e resolver o
      # nome a cada leitura significaria carregar os quatro.
      t.string :source_name
      t.string :origin, null: false, default: 'derived'
      t.timestamps
    end

    add_index :proficiency_sources, %i[proficiency_id source_type source_key],
              unique: true, name: 'idx_prof_sources_unicidade'
    add_index :proficiency_sources, %i[source_type source_key]
  end
end
