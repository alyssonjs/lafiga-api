module CharacterSheetEdits
  # Abilities edit em modo edit: edita os atributos BASE do personagem (point-buy
  # / valor antes de increments raciais/ASI/feat) e re-sincroniza as colunas
  # `str/dex/con/int/wis/cha` do Sheet via `sync_ability_columns_from_metadata!`.
  #
  # Bugs B5.1/B5.2/B5.3 do relatorio de auditoria de steps: antes deste fix,
  # o service:
  #   - Lia `sheet.str` direto (B5.3) — em personagens com
  #     `meta['ability_scores_include_all_increments']` esse valor e o TOTAL,
  #     nao o base. UI carregava 18 e o user editava como base.
  #   - Gravava `sheet.send("#{k}=", v.to_i)` direto (B5.1) — qualquer
  #     execucao posterior de `sync_ability_columns_from_metadata!` (em
  #     ProgressionEdit, FeatAssignment, etc.) sobrescrevia o valor com
  #     `base + race + asi + feat`, descartando a edicao.
  #   - Nao atualizava `meta['base_ability_scores']` (B5.2) — drift permanente.
  class AbilitiesEditService < BaseSheetEditService
    KEYS = %w[str dex con int wis cha].freeze

    def step_key = 'abilities'

    # Devolve sempre o BASE (point-buy sem increments). Se ainda nao houver
    # `meta['base_ability_scores']` (personagem legado pre-fix), faz fallback
    # para `coluna_atual - increments_aplicados`.
    def read
      meta = sheet.metadata || {}
      stored_base = meta['base_ability_scores']

      if stored_base.is_a?(Hash) && stored_base.keys.any?
        scores = KEYS.each_with_object({}) { |k, h| h[k] = (stored_base[k] || stored_base[k.to_sym]).to_i }
      else
        # Legado: subtrai increments aplicados das colunas (mesma logica de
        # `build_abilities` em modo nao-authoritative).
        race_inc = (meta['race_bonuses_applied'] || {}).deep_stringify_keys
        asi_inc, feat_inc = compute_other_increments(meta)
        scores = KEYS.each_with_object({}) do |k, h|
          h[k] = sheet.send(k).to_i - race_inc[k].to_i - asi_inc[k].to_i - feat_inc[k].to_i
        end
      end

      { 'abilityScores' => scores }
    end

    protected

    def apply!
      scores = data['abilityScores'] || {}
      old_con_total = sheet.con.to_i

      # Persiste o BASE em meta — fonte da verdade canonica para `build_abilities`
      # com `ability_scores_include_all_increments=true`. Sem isso, qualquer
      # `sync_ability_columns_from_metadata!` posterior sobrescreve com lixo.
      meta = (sheet.metadata || {}).deep_stringify_keys
      base = (meta['base_ability_scores'] || {}).deep_dup
      KEYS.each do |k|
        v = scores[k]
        base[k] = v.to_i if v.present?
      end
      meta['base_ability_scores'] = base
      sheet.metadata = meta
      sheet.save!

      # Re-sincroniza colunas: `base + race + asi + feat`. Tambem flipa
      # `ability_scores_include_all_increments=true` (idempotente).
      CharacterSheetSummaryService.sync_ability_columns_from_metadata!(sheet.reload)

      # Se o CON TOTAL mudou, ajusta hp_max preservando ratio. Comparamos contra
      # o `old_con_total` (coluna pre-update) — `sheet.reload` ja tem o novo.
      new_con_total = sheet.con.to_i
      if new_con_total != old_con_total
        recompute_hp_max!(new_con: new_con_total)
        sheet.save!
      end
    end

    private

    # Soma incrementos por chave (str/dex/...) provenientes de:
    #   - per_level[N].asi (mode 'plus2'/'plus1x2')
    #   - per_level[N].feats[*].ability_bonuses
    #   - sheet.metadata['feats'][*].ability_bonuses (Variant Human + ASI feat)
    #
    # Reaproveita a logica que ja existe em `build_abilities`, mas como aqui so
    # precisamos do agregado (nao do breakdown), inline a versao simples — evita
    # carregar o builder inteiro so para inverter o calculo no `read` legado.
    def compute_other_increments(meta)
      asi_inc = Hash.new(0)
      feat_inc = Hash.new(0)

      pl = (meta.dig('class_choices', 'per_level') || {})
      pl.each_value do |row|
        next unless row.is_a?(Hash)
        accumulate_asi!(asi_inc, row['asi'] || row[:asi])
        Array(row['feats'] || row[:feats]).each do |f|
          accumulate_ability_bonuses!(feat_inc, (f.is_a?(Hash) ? (f['ability_bonuses'] || f[:ability_bonuses]) : nil))
        end
      end

      Array(meta['feats']).each do |f|
        accumulate_ability_bonuses!(feat_inc, (f.is_a?(Hash) ? (f['ability_bonuses'] || f[:ability_bonuses]) : nil))
      end

      [asi_inc, feat_inc]
    end

    def accumulate_asi!(acc, asi)
      return unless asi.is_a?(Hash)
      mode = (asi['mode'] || asi[:mode]).to_s
      case mode
      when 'plus2'
        k = (asi['ability1'] || asi[:ability1]).to_s.downcase
        acc[k] += 2 if KEYS.include?(k)
      when 'plus1x2'
        a1 = (asi['ability1'] || asi[:ability1]).to_s.downcase
        a2 = (asi['ability2'] || asi[:ability2]).to_s.downcase
        acc[a1] += 1 if KEYS.include?(a1)
        acc[a2] += 1 if KEYS.include?(a2)
      end
    end

    def accumulate_ability_bonuses!(acc, ab)
      return unless ab
      bonuses = ab.is_a?(String) ? safe_parse(ab) : ab
      return unless bonuses.is_a?(Hash)
      bonuses.each do |k, v|
        ks = k.to_s.downcase
        acc[ks] += v.to_i if KEYS.include?(ks)
      end
    end

    def safe_parse(str)
      JSON.parse(str)
    rescue JSON::ParserError
      nil
    end
  end
end
