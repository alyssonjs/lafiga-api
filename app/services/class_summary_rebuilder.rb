# Recomputes Sheet#class_summary (column + metadata) from authoritative sources:
# Klass + ClassRules + class_choices.per_level + legacy `instruments_selected` at
# class_choices root.
#
# Idempotente. Pode rodar:
#   - durante provisionamento (chamado por CharacterProvisioningService)
#   - em SheetEditServices apos mudanca de classe/subclasse/nivel
#   - via rake `sheets:rebuild_class_summary` para backfill de fichas legadas
#
# Usage:
#   ClassSummaryRebuilder.call(sheet)
#   ClassSummaryRebuilder.call(sheet, wizard_klass: { 'instrumentsSelected' => [...] })
class ClassSummaryRebuilder
  def self.call(sheet, wizard_klass: nil)
    new(sheet, wizard_klass: wizard_klass).call
  end

  def initialize(sheet, wizard_klass: nil)
    @sheet = sheet
    @wizard_klass = wizard_klass
  end

  def call
    sheet = @sheet
    sk = sheet.sheet_klasses.order(level: :desc, id: :asc).first
    return log_skip(sheet, 'no_sheet_klass') unless sk

    klass_record = sk.klass
    return log_skip(sheet, 'no_klass_record') unless klass_record

    api_index = klass_record.api_index.presence
    unless api_index
      Rails.logger.warn("ClassSummaryRebuilder: skipping sheet=#{sheet.id} klass_id=#{klass_record.id} (api_index missing)")
      return false
    end

    meta = (sheet.metadata || {}).deep_stringify_keys
    cc = (meta['class_choices'] || {})
    per_level = (cc['per_level'] || {})
    row1 = (per_level['1'] || per_level[1] || {})
    row1 = {} unless row1.is_a?(Hash)

    chosen_skills = Array(row1['skills'] || row1[:skills]).map(&:to_s)

    instruments = collect_instruments(row1: row1, class_choices_root: cc, wizard_klass: @wizard_klass)

    picks = {}
    if sk&.sub_klass&.api_index.present?
      picks[:subclass_id] = sk.sub_klass.api_index
    end

    applied = ClassRules.apply(
      {
        klass_id: api_index,
        level: sk.level.to_i,
        picks: picks,
        skills_selected: chosen_skills,
        instruments_selected: instruments
      }
    )

    tool_lines = flatten_tool_proficiencies(applied[:tool_proficiencies])

    summary_cs = {
      'name'                  => (applied[:name] || klass_record.name).to_s,
      'klass_id'              => klass_record.id,
      'hit_die'               => applied[:hit_die].to_s,
      'armor_proficiencies'   => Array(applied[:armor_proficiencies]).map(&:to_s),
      'weapon_proficiencies'  => Array(applied[:weapon_proficiencies]).map(&:to_s),
      'tools'                 => tool_lines,
      'skills'                => (Array(applied[:skills_selected]).presence || chosen_skills).map(&:to_s),
      'saving_throws'         => Array(applied[:saving_throws]).map(&:to_s)
    }

    sheet.reload
    meta = (sheet.metadata || {}).deep_dup
    col_raw = sheet.read_attribute(:class_summary)
    col_summary = col_raw.is_a?(Hash) ? col_raw.deep_dup.stringify_keys : {}
    meta_raw = meta['class_summary']
    meta_summary = meta_raw.is_a?(Hash) ? meta_raw.deep_dup.stringify_keys : {}

    # Preserve existing skills choice if rebuilder runs without fresh picks.
    fresh = summary_cs
    if fresh['skills'].blank? && (col_summary['skills'].present? || meta_summary['skills'].present?)
      fresh['skills'] = (col_summary['skills'].presence || meta_summary['skills']).to_a
    end

    merged = col_summary.merge(meta_summary).merge(fresh)
    meta['class_summary'] = merged
    sheet.update_columns(metadata: meta, class_summary: merged)
    Rails.logger.info("ClassSummaryRebuilder: rebuilt sheet=#{sheet.id} klass=#{api_index} armor=#{merged['armor_proficiencies'].size} weapons=#{merged['weapon_proficiencies'].size} tools=#{merged['tools'].size}")
    true
  rescue StandardError => e
    Rails.logger.error("ClassSummaryRebuilder: sheet=#{sheet.id} #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    false
  end

  private

  # Collect instruments from every known historical location.
  # Modern flow: class_choices.per_level['1'].instruments
  # Legacy flow: class_choices.instruments_selected (root)
  # Wizard flow (provisioning time): wizard.klass.instrumentsSelected
  def collect_instruments(row1:, class_choices_root:, wizard_klass:)
    inst_rows = []
    inst_rows.concat(Array(row1['instruments'] || row1[:instruments] || row1['instruments_selected'] || row1[:instruments_selected]))
    inst_rows.concat(Array(class_choices_root['instruments_selected'] || class_choices_root[:instruments_selected]))
    inst_rows.concat(Array(class_choices_root['instruments'] || class_choices_root[:instruments]))
    if wizard_klass.is_a?(Hash)
      wiz = wizard_klass.stringify_keys
      inst_rows.concat(Array(wiz['instrumentsSelected'] || wiz['instruments_selected'] || wiz['instruments']))
    end
    inst_rows.map do |x|
      if x.is_a?(Hash)
        xh = x.stringify_keys
        (xh['name'] || xh['id']).to_s
      else
        x.to_s
      end
    end.compact.map(&:strip).reject(&:blank?).uniq
  end

  def flatten_tool_proficiencies(tool_profs)
    out = []
    Array(tool_profs).each do |t|
      case t
      when String
        out << t.to_s.strip if t.present?
      when Hash
        out.concat(extract_from_hash(t))
      when Array
        # ClassRules emits e.g. ["instruments", {choose:3, choices:[...]}].
        # Skip the metadata wrapper itself (nothing chosen yet there);
        # actual selections come as the trailing Hash {instruments:[...]}.
        t.each { |inner| out.concat(extract_from_hash(inner)) if inner.is_a?(Hash) }
      end
    end
    out.compact.map(&:strip).reject(&:blank?).uniq
  end

  def extract_from_hash(t)
    out = []
    h = t.stringify_keys
    %w[instruments tools artisan gaming kits].each do |k|
      arr = h[k]
      next unless arr.is_a?(Array)
      arr.each { |x| out << (x.is_a?(Hash) ? (x.stringify_keys['name'] || x.stringify_keys['id']) : x).to_s.strip }
    end
    out
  end

  def log_skip(sheet, reason)
    Rails.logger.warn("ClassSummaryRebuilder: skipping sheet=#{sheet.id} reason=#{reason}")
    false
  end
end
