class Api::V1::Player::SheetPreparedSpellsController < ApplicationController
  before_action :authorize_request

  def index
    sheet = current_user_sheet
    # Materialize magias "sempre preparadas" (classe e subclasse) antes de listar
    begin
      ap_spell_ids = []
      # Helper: to_slug for resilient lookup
      to_slug = ->(s) { ActiveSupport::Inflector.transliterate(s.to_s).downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-+|-+$/,'') }
      resolve_spell = lambda do |label|
        nm = label.to_s.strip
        return nil if nm.blank?
        sp = Spell.find_by(name: nm) || Spell.find_by(api_index: nm)
        return sp if sp
        sp = Spell.where('LOWER(name) = ?', nm.downcase).first
        return sp if sp
        slug = to_slug.call(nm)
        Spell.find_by(api_index: slug)
      end

      meta = (sheet.metadata || {})
      per_level = (meta.dig('class_choices','per_level') || {})
      chosen_terrain = begin
        key = nil
        per_level.values.each do |row|
          v = row['terrain'] || row[:terrain] || row['terreno'] || row[:terreno]
          next unless v
          key = (v.is_a?(Hash) ? (v['id'] || v[:id] || v['name'] || v[:name]) : v)
          break if key
        end
        key ? to_slug.call(key) : nil
      rescue
        nil
      end

      sheet.sheet_klasses.find_each do |sk|
        lvl = (sk.level || 1).to_i
        # From SubKlass (Domain/Oath/Circle/Patron etc.)
        if sk.sub_klass_id.present?
          ids_sub = SpellSource
            .where(source_type: 'SubKlass', source_id: sk.sub_klass_id, always_prepared: true)
            .where('min_class_level IS NULL OR min_class_level <= ?', lvl)
            .pluck(:spell_id)
          ap_spell_ids |= ids_sub

          # Also include always_prepared_by_terrain from levels_json (e.g., Druid Land circle)
          begin
            sub = sk.sub_klass
            if sub&.levels_json.present?
              rows = JSON.parse(sub.levels_json) rescue []
              rows = Array(rows).select { |r| r.is_a?(Hash) && (r['level'].to_i <= lvl) }
              names = []
              rows.each do |r|
                buckets = []
                buckets << r if r['grants'].is_a?(Hash)
                feats = Array(r['features']).select { |f| f.is_a?(Hash) }
                feats.each { |f| buckets << f if f['grants'].is_a?(Hash) }
                buckets.each do |node|
                  spells = (node.dig('grants','spells') || {})
                  terr = (spells['always_prepared_by_terrain'] || {})
                  next unless chosen_terrain && terr[chosen_terrain]
                  terr_map = terr[chosen_terrain] || {}
                  terr_map.keys.map(&:to_i).sort.each do |k|
                    next if k > lvl
                    Array(terr_map[k.to_s]).each { |nm| names << nm }
                  end
                end
              end
              names.uniq.each do |nm|
                sp = resolve_spell.call(nm)
                next unless sp
                ap_spell_ids << sp.id
              end
            end
          rescue => _e
          end
        end
      end
      # Normalize: only subclass-provided spells should remain auto=true
      if ap_spell_ids.any?
        SheetPreparedSpell.where(sheet_id: sheet.id, auto: true).where.not(spell_id: ap_spell_ids).update_all(auto: false)
      else
        # No subclass auto spells → ensure none are flagged auto
        SheetPreparedSpell.where(sheet_id: sheet.id, auto: true).update_all(auto: false)
      end
      ap_spell_ids.each do |sid|
        SheetPreparedSpell.find_or_create_by!(sheet_id: sheet.id, spell_id: sid) do |sp|
          sp.auto = true
          sp.source = 'class'
        end
      end
    rescue => _e
      # falhas nessa etapa não devem quebrar a listagem
    end

    prepared = SheetPreparedSpell.where(sheet_id: sheet.id)
    render json: { sheet_prepared_spells: prepared }, status: :ok
  end

  def create
    sheet = current_user_sheet
    # Normalize common params that may come nested under :sheet_prepared_spell
    spell_id = params[:spell_id] || params.dig(:sheet_prepared_spell, :spell_id)
    # Boolean#cast(nil) => nil; column `auto` is NOT NULL — default user-prepared rows to false.
    raw_auto = if params.key?(:auto)
      params[:auto]
    else
      nested = params[:sheet_prepared_spell]
      nested.is_a?(ActionController::Parameters) && nested.key?(:auto) ? nested[:auto] : nil
    end
    auto = raw_auto.nil? ? false : ActiveModel::Type::Boolean.new.cast(raw_auto)

    # Check if spell is already prepared (idempotent)
    existing_spell = SheetPreparedSpell.find_by(sheet_id: sheet.id, spell_id: spell_id)
    if existing_spell
      # Idempotente: retorna OK com o registro existente
      return render json: { sheet_prepared_spell: existing_spell }, status: :ok
    end
    
    # Gate against limit using best-effort prepared classes
    begin
      prep_klass = sheet.sheet_klasses.includes(:klass).map(&:klass).find { |k| %w[cleric druid wizard paladin].include?(k.api_index) }
      if prep_klass
        limit = SpellRules.prepared_limit_for(sheet, prep_klass)
        non_auto = SheetPreparedSpell.where(sheet_id: sheet.id, auto: false).count
        if non_auto >= limit
          return render json: { error: "Limite de magias preparadas alcançado (#{non_auto}/#{limit})" }, status: :unprocessable_entity
        end
      end
    rescue => _e
      # if any error, skip gate and let model validations handle (none by default)
    end

    # Wizard hardening: se a ficha tiver somente Mago como conjurador preparado,
    # só permitir preparar magias que estejam no grimório (SheetKnownSpell do Mago).
    begin
      if auto != true
        prepared_klasses = sheet.sheet_klasses.includes(:klass).map(&:klass).select { |k| %w[cleric druid wizard paladin].include?(k.api_index) }
        prepared_keys = prepared_klasses.map(&:api_index).uniq
        if prepared_keys == ['wizard']
          wizard_sk = sheet.sheet_klasses.includes(:klass).find { |sk| sk.klass.api_index == 'wizard' }
          if wizard_sk && !SheetKnownSpell.exists?(sheet_klass_id: wizard_sk.id, spell_id: spell_id)
            return render json: { error: 'Mago: só pode preparar magias que estejam no grimório.' }, status: :unprocessable_entity
          end
        end
      end
    rescue => _e
      # Em caso de erro inesperado, não bloquear — outras validações ainda ocorrem
    end

    sp = SheetPreparedSpell.create!(sheet_id: sheet.id, spell_id: spell_id, auto: auto, source: 'class')
    render json: { sheet_prepared_spell: sp }, status: :created
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    sheet = current_user_sheet
    sp = SheetPreparedSpell.find_by!(sheet_id: sheet.id, id: params[:id])
    sp.destroy
    head :no_content
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Not found' }, status: :not_found
  end

  private

  def current_user_sheet
    # Accept both query param (?sheet_id=) and nested body { sheet_prepared_spell: { sheet_id: ... } }
    sheet_id = params[:sheet_id] || params.dig(:sheet_prepared_spell, :sheet_id) || (params.dig(:params, :sheet_id) rescue nil)
    sheet = Sheet.find(sheet_id)
    raise StandardError, 'Forbidden' unless current_user_may_access_sheet?(sheet)
    sheet
  end
end
