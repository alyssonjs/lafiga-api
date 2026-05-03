# frozen_string_literal: true

# Adiciona campos editáveis pelo admin no modal "Editar Classe" do front
# (`ClassFormModal.tsx`):
#
# - `description`: texto rich (HTML) com a descrição da classe.
# - `primary_ability`: habilidade primária (string livre — ex.: "Sabedoria",
#   "Forca ou Destreza"). Distinto de `spellcasting_ability` (que só
#   atende casters); a primária é exibida na ficha e no compendium para
#   toda classe.
# - `saving_throws`: array de habilidades nas quais a classe é proficiente
#   em testes de resistência (ex.: `["Sabedoria", "Carisma"]`).
#
# Antes desta migration o controller `Api::V1::Admin::Klasses` aceitava
# apenas `name/api_index/hit_die/spellcasting_ability/subclass_level/rules`,
# então o modal salvava esses campos em vão — perdiam-se ao recarregar.
class AddDescriptionAndMetadataToKlasses < ActiveRecord::Migration[6.0]
  def change
    add_column :klasses, :description, :text, null: true
    add_column :klasses, :primary_ability, :string, null: true
    add_column :klasses, :saving_throws, :jsonb, null: true, default: []
  end
end
