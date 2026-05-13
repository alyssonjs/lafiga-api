# frozen_string_literal: true

# Relaxa a unique constraint do `sheet_feats` para suportar talentos
# repetíveis (Adepto Elemental, Mágico Iniciante, Adepto Marcial, Poliglota,
# Perito, Conjurador de Ritual). Antes, `unique: (sheet_id, feat_id)`
# bloqueava o segundo pick mesmo quando o feat era cumulativo por design.
#
# Nova chave: `(sheet_id, feat_id, level_gained)` — permite múltiplas linhas
# do mesmo feat se vierem de níveis distintos (ASI nv 4 + ASI nv 8, p.ex.).
# A lógica de "não duplicar no mesmo level" é responsabilidade do
# `FeatAssignmentService` (via `SheetFeatLevelCleaner`).
class AllowRepeatableFeatsInSheetFeats < ActiveRecord::Migration[6.0]
  def up
    remove_index :sheet_feats, name: 'index_sheet_feats_on_sheet_id_and_feat_id' if index_exists?(:sheet_feats, %i[sheet_id feat_id], name: 'index_sheet_feats_on_sheet_id_and_feat_id')
    add_index :sheet_feats, %i[sheet_id feat_id level_gained],
              unique: true,
              name: 'index_sheet_feats_on_sheet_feat_level'
  end

  def down
    remove_index :sheet_feats, name: 'index_sheet_feats_on_sheet_feat_level' if index_exists?(:sheet_feats, %i[sheet_id feat_id level_gained], name: 'index_sheet_feats_on_sheet_feat_level')
    add_index :sheet_feats, %i[sheet_id feat_id],
              unique: true,
              name: 'index_sheet_feats_on_sheet_id_and_feat_id'
  end
end
