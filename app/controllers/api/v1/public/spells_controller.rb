class Api::V1::Public::SpellsController < ApplicationController
  # Truncamos `desc` no modo slim para reduzir payload da listagem (~500KB
  # com texto integral PHB) sem perder a 1a frase de preview no card.
  SLIM_DESC_CHARS = 200

  def index
    spells = Spell.all
    if params[:ids].present?
      ids = Array(params[:ids]).map(&:to_i).reject(&:zero?)
      spells = spells.where(id: ids) if ids.any?
    end
    # Subclass-aware lists with Patron expanded spells:
    # If subclass_id is present, compute base class list (possibly remapped via SubclassSpellcasting)
    # and UNION with SubKlass SpellSource entries marked notes='expanded'.
    if params[:subclass_id].present? && params[:klass_id].present?
      begin
        klass = Klass.find(params[:klass_id])
        # Resolve subclass by api_index or numeric id under this klass
        sub_rec = begin
          klass.sub_klasses.find_by(api_index: params[:subclass_id]) || klass.sub_klasses.find_by(id: params[:subclass_id])
        rescue
          nil
        end

        # Remap list source if subclass declares a different class list
        subclass_api = (sub_rec&.api_index.presence || params[:subclass_id].to_s)
        entry = SubclassSpellcasting.lookup(klass_api: klass.api_index, subclass_api: subclass_api, level: 20)
        list_api = entry&.list_source_klass.to_s
        base_klass = list_api.present? ? Klass.find_by(api_index: list_api) : klass

        # Build SpellSource scope for base class and subclass (expanded), applying level filter
        sources = []
        if base_klass
          sources << SpellSource.where(source_type: 'Klass', source_id: base_klass.id)
        end
        if sub_rec
          sources << SpellSource.where(source_type: 'SubKlass', source_id: sub_rec.id)
        end
        src_scope = sources.reduce(SpellSource.none) { |acc, s| acc.or(s) }
        if params[:level].present?
          lvl = params[:level].to_i
          src_scope = src_scope.where('min_class_level IS NULL OR min_class_level <= ?', lvl)
        end
        # If subclass present, only include subclass entries marked as expanded when combining
        if sub_rec
          base_scope = SpellSource.where(source_type: 'Klass', source_id: (base_klass&.id))
          base_scope = base_scope.where('min_class_level IS NULL OR min_class_level <= ?', params[:level].to_i) if params[:level].present?
          sub_scope  = SpellSource.where(source_type: 'SubKlass', source_id: sub_rec.id).where("coalesce(notes,'') = ?", 'expanded')
          sub_scope  = sub_scope.where('min_class_level IS NULL OR min_class_level <= ?', params[:level].to_i) if params[:level].present?
          src_scope  = base_scope.or(sub_scope)
        end

        spell_ids = src_scope.distinct.pluck(:spell_id)
        min_map = src_scope.group(:spell_id).minimum(:min_class_level)
        idx_map = klass_api_indexes_by_spell_id(spell_ids)
        list = Spell.where(id: spell_ids).map do |s|
          spell_payload(s).merge(
            'min_class_level' => (min_map[s.id] || 1),
            'klass_api_indexes' => idx_map[s.id] || []
          )
        end
        render json: { spells: list }, status: :ok and return
      rescue => _e
        # ignore and fallback to klass_id behavior
      end
    end
    if params[:klass_id].present?
      klass_id = params[:klass_id].to_i
      scope = SpellSource.where(source_type: 'Klass', source_id: klass_id)
      if params[:level].present?
        lvl = params[:level].to_i
        scope = scope.where('min_class_level IS NULL OR min_class_level <= ?', lvl)
      end
      # Build map spell_id -> min_class_level (nil => 1)
      min_map = scope.group(:spell_id).minimum(:min_class_level)
      ids = scope.pluck(:spell_id)
      idx_map = klass_api_indexes_by_spell_id(ids)
      list = Spell.where(id: ids).map do |s|
        spell_payload(s).merge(
          'min_class_level' => (min_map[s.id] || 1),
          'klass_api_indexes' => idx_map[s.id] || []
        )
      end
      render json: { spells: list }, status: :ok and return
    end

    spell_records = spells.to_a
    idx_map = klass_api_indexes_by_spell_id(spell_records.map(&:id))
    list = spell_records.map do |s|
      spell_payload(s).merge('klass_api_indexes' => idx_map[s.id] || [])
    end
    render json: { spells: list }, status: :ok
  end

  def show
    spell = Spell.find(params[:id])
    # Detail endpoint sempre devolve `desc` integral (forca view=full).
    render json: { spell: spell_payload(spell, view: 'full') }, status: :ok
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Spell not found' }, status: :not_found
  end

  private

  # Retorna o hash do spell respeitando o param `view`:
  #   - `view=full`  -> `desc` e `higher_level` integrais.
  #   - `view=slim`  (default na index) -> `desc` truncado em SLIM_DESC_CHARS,
  #     campo `short_desc` com a 1a frase, `higher_level` omitido.
  def spell_payload(spell, view: nil)
    mode = (view || params[:view]).to_s.downcase
    mode = 'slim' unless %w[full slim].include?(mode)
    base = spell.as_json
    return base if mode == 'full'

    full_desc = base['desc'].to_s
    truncated = full_desc.length > SLIM_DESC_CHARS
    short = truncated ? "#{full_desc[0, SLIM_DESC_CHARS].rstrip}…" : full_desc
    base.merge(
      'short_desc'            => short,
      'desc'                  => short,
      'higher_level'          => nil,
      'view'                  => 'slim',
      # Sinaliza explicitamente quando o front precisa lazy-fetchar via /show.
      # Magia curta no modo slim NAO esta truncada -> evita request desnecessario
      # em SpellDescriptionBody.
      'description_truncated' => truncated
    )
  end

  # spell_id => distinct klass api_index list (e.g. bard, wizard) for wizard filtering
  def klass_api_indexes_by_spell_id(spell_ids)
    return {} if spell_ids.blank?
    pairs = SpellSource.where(source_type: 'Klass', spell_id: spell_ids)
      .joins("INNER JOIN klasses ON klasses.id = spell_sources.source_id")
      .pluck(:spell_id, 'klasses.api_index')
    pairs.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(sid, api), memo|
      memo[sid] << api if api.present?
    end.transform_values(&:uniq)
  end
end
