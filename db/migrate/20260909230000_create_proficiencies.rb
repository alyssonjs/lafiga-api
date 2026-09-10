# frozen_string_literal: true

# Catálogo de proficiências — FASE 0 (só idioma por enquanto).
#
# Até aqui as ~1.004 proficiências das fichas eram STRING LIVRE dentro de jsonb:
# sem chave estrangeira, sem validação, e erro de grafia falhando em SILÊNCIO —
# a linha só não aparecia na ficha. Foi assim que "Veículos terrestres" acabou
# com quatro grafias e 14 proficiências ficaram órfãs sem ninguém notar.
#
# ⚠️ A tabela de APELIDOS não é acessório: é ela que deixa o que já está gravado
# continuar a casar. Sem ela, catalogar seria uma migração destrutiva.
class CreateProficiencies < ActiveRecord::Migration[6.0]
  def change
    create_table :proficiencies do |t|
      t.string  :api_index,    null: false
      t.string  :name,         null: false
      t.string  :category,     null: false
      t.string  :sub_category
      # Guarda o que é específico do tipo sem alargar o schema a cada tipo novo:
      # atributo sugerido da ferramenta, propriedades da arma, e a relação
      # dialeto <-> Primordial (quem fala um entende os quatro).
      t.jsonb   :metadata,     null: false, default: {}
      t.string  :source,       null: false, default: 'PHB'
      t.boolean :published,    null: false, default: true
      t.timestamps
    end
    add_index :proficiencies, :api_index, unique: true
    add_index :proficiencies, %i[category sub_category]

    create_table :proficiency_aliases do |t|
      t.references :proficiency, null: false, foreign_key: true
      # Forma NORMALIZADA (minúscula, sem acento, espaços colapsados) — é por
      # ela que se resolve.
      t.string :alias_key, null: false
      # A grafia como foi encontrada, para auditoria: sem isto não dá para
      # saber QUEM escreveu errado, só que alguém escreveu.
      t.string :raw
      t.timestamps
    end
    # ⚠️ Único GLOBALMENTE, de propósito. Se um dia duas categorias disputarem
    # o mesmo apelido, o seed FALHA — e falhar alto é o que se quer: quer dizer
    # que a mesma palavra passou a significar duas coisas e alguém tem de
    # decidir qual. Silêncio aqui é como o defeito nasceu da primeira vez.
    add_index :proficiency_aliases, :alias_key, unique: true
  end
end
