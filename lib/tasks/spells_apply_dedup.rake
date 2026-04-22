# frozen_string_literal: true

# Lafiga: applies the dedup actions produced by `spells:import_xlsx` (which
# detected duplicate spells in the YAML — e.g. a `pt-*` mirror of an SRD
# canonical entry — and chose which one to keep).
#
# For each pair { removed_api_index, kept_api_index }, this task:
#   1. Repoints SpellSource rows from the removed Spell to the kept Spell
#      (deduping if both already exist for the same source/spell pair).
#   2. Repoints SheetKnownSpell / SheetPreparedSpell rows likewise (when the
#      tables exist), preserving uniqueness via DELETE + UPDATE.
#   3. Deletes the removed Spell row.
#
# Idempotent: if the removed_api_index no longer exists in the DB, the entry
# is just skipped.
#
# Usage:
#   1) bundle exec rake spells:import_xlsx WRITE=1   # generates docs/spells_dedup_actions.json
#   2) bundle exec rake spells:apply_dedup
#   3) bundle exec rake spells:replace               # syncs renamed names + descriptions

require 'json'

namespace :spells do
  desc 'Apply spell dedup actions from docs/spells_dedup_actions.json (migrates FKs, deletes orphans)'
  task apply_dedup: :environment do
    actions_path = Rails.root.join('docs', 'spells_dedup_actions.json')
    unless File.exist?(actions_path)
      puts "[spells:apply_dedup] no actions file at #{actions_path} — nothing to do."
      next
    end

    actions = JSON.parse(File.read(actions_path))
    if actions.empty?
      puts '[spells:apply_dedup] actions file is empty — nothing to do.'
      next
    end

    has_known    = ActiveRecord::Base.connection.data_source_exists?('sheet_known_spells')
    has_prepared = ActiveRecord::Base.connection.data_source_exists?('sheet_prepared_spells')

    skipped = 0
    migrated_pairs = 0
    deleted_spells = 0
    moved_sources = 0
    moved_known = 0
    moved_prepared = 0

    actions.each do |action|
      removed_idx = action['removed_api_index'].to_s
      kept_idx    = action['kept_api_index'].to_s
      next if removed_idx.empty? || kept_idx.empty?

      removed_spell = Spell.find_by(api_index: removed_idx)
      kept_spell    = Spell.find_by(api_index: kept_idx)

      if removed_spell.nil?
        puts "[spells:apply_dedup] skip: removed api_index '#{removed_idx}' not in DB"
        skipped += 1
        next
      end

      if kept_spell.nil?
        puts "[spells:apply_dedup] WARN: kept api_index '#{kept_idx}' not in DB — leaving '#{removed_idx}' alone"
        skipped += 1
        next
      end

      ActiveRecord::Base.transaction do
        # SpellSource: (source_type, source_id, spell_id) is logically unique.
        # Delete duplicates first (where the kept already has an entry for
        # the same source), then move the survivors.
        dup_sources = SpellSource.where(spell_id: removed_spell.id).where(
          source_type: SpellSource.where(spell_id: kept_spell.id).select(:source_type),
          source_id:   SpellSource.where(spell_id: kept_spell.id).select(:source_id),
        )
        dup_count = dup_sources.count
        dup_sources.delete_all if dup_count.positive?

        moved = SpellSource.where(spell_id: removed_spell.id).update_all(spell_id: kept_spell.id)
        moved_sources += moved

        if has_known
          moved_known_now = move_table('sheet_known_spells', removed_spell.id, kept_spell.id)
          moved_known += moved_known_now
        end

        if has_prepared
          moved_prepared_now = move_table('sheet_prepared_spells', removed_spell.id, kept_spell.id)
          moved_prepared += moved_prepared_now
        end

        removed_spell.destroy!
        deleted_spells += 1
        migrated_pairs += 1

        puts "[spells:apply_dedup] '#{action['removed_name']}' (#{removed_idx}) -> '#{action['kept_name']}' (#{kept_idx}) " \
             "[sources_moved=#{moved} sources_dup_deleted=#{dup_count}]"
      end
    end

    puts "[spells:apply_dedup] summary: pairs=#{migrated_pairs} skipped=#{skipped} " \
         "spells_deleted=#{deleted_spells} sources_moved=#{moved_sources} " \
         "known_moved=#{moved_known} prepared_moved=#{moved_prepared}"
  end

  # Moves rows in a sheet_*_spells table from removed_spell_id to kept_spell_id,
  # avoiding (sheet_id, spell_id) collisions by deleting losers first. Returns
  # number of rows actually moved (post-dedup).
  def move_table(table_name, removed_id, kept_id)
    conn = ActiveRecord::Base.connection
    # Discover the unique key beyond spell_id (usually sheet_id).
    cols = conn.columns(table_name).map(&:name)
    sheet_col = cols.find { |c| c == 'sheet_id' || c == 'character_sheet_id' }
    unless sheet_col
      # Fallback: just update naive
      return conn.exec_update(
        "UPDATE #{table_name} SET spell_id = #{kept_id.to_i} WHERE spell_id = #{removed_id.to_i}",
      )
    end

    # Delete rows in the removed_id set whose (sheet_col) already has a row
    # for kept_id, to avoid violating the uniqueness invariant.
    conn.exec_delete(<<~SQL.squish)
      DELETE FROM #{table_name}
       WHERE spell_id = #{removed_id.to_i}
         AND #{sheet_col} IN (
           SELECT #{sheet_col} FROM #{table_name} WHERE spell_id = #{kept_id.to_i}
         )
    SQL

    conn.exec_update(
      "UPDATE #{table_name} SET spell_id = #{kept_id.to_i} WHERE spell_id = #{removed_id.to_i}",
    )
  end
end
