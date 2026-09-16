# frozen_string_literal: true

# Carimbo de edição do Mestre nas sub-classes.
#
# `sub_klasses` nasceu sem timestamps: não há como distinguir uma sub tocada pelo
# compêndio de uma que é exatamente o que a rake de import escreveu. Sem essa
# distinção a guarda do import não tem em que se apoiar — `apply_subclass_overrides!`
# faz replace-all do `levels_json`, então re-rodar a rake apagaria a edição do
# Mestre em silêncio (é o mesmo buraco que a fase 1 fechou em `klasses.rules`).
#
# ⚠️ `edited_at` fica NULL em TODAS as linhas existentes de propósito:
# NULL = "é o livro", e o import segue livre para sobrescrevê-las. Só o que a
# página gravar passa a ser pulado (salvo `FORCE=1`).
class AddTimestampsAndEditedAtToSubKlasses < ActiveRecord::Migration[6.0]
  def up
    add_timestamps :sub_klasses, null: true
    add_column :sub_klasses, :edited_at, :datetime

    # Backfill antes do NOT NULL: sem ele o `add_timestamps null: false` quebraria
    # nas linhas já existentes, e ordenar por data mentiria.
    agora = connection.quote(Time.current)
    execute("UPDATE sub_klasses SET created_at = #{agora}, updated_at = #{agora}")

    change_column_null :sub_klasses, :created_at, false
    change_column_null :sub_klasses, :updated_at, false
  end

  def down
    remove_column :sub_klasses, :edited_at
    remove_timestamps :sub_klasses
  end
end
