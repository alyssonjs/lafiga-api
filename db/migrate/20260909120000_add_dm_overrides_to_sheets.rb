# frozen_string_literal: true

# Sobrescritas do MESTRE: valores que ele crava na ficha e que passam por cima
# do que o motor calcula (maldição, bênção de campanha, houserule, conserto de
# import).
#
# ⚠️ Coluna PRÓPRIA, e o motivo é a razão de existir desta camada:
# `CharacterSheetSummaryService.sync_ability_columns_from_metadata!` REESCREVE
# `str..cha` a partir do metadata, e é chamado por cinco caminhos (level up,
# provisionamento, talento, edição de atributos, edição de raça). Sobrescrita
# gravada na coluna do atributo some em silêncio no próximo nível. Aqui ela
# sobrevive, porque nada nesses caminhos toca este campo.
#
# Não vive em `metadata` porque `patchPlayerSheetMetadata` (front) substitui o
# metadata INTEIRO — um caller que esqueça o merge profundo levaria as
# sobrescritas junto.
class AddDmOverridesToSheets < ActiveRecord::Migration[6.0]
  def change
    add_column :sheets, :dm_overrides, :jsonb, null: false, default: {}
  end
end
