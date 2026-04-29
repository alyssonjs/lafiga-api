module CharacterSheetEdits
  # Per-level edit on an active sheet. Updates `metadata.class_choices.per_level[N]`
  # and bumps SheetKlass.level if needed; preserves HP_current ratio when leveling.
  class ProgressionEditService < BaseSheetEditService
    def step_key = 'progression'

    def read
      meta_pl = (sheet.metadata || {}).dig('class_choices', 'per_level') || {}
      level_choices = meta_pl
        .reject { |k, _| k == '1' }
        .map do |lv, row|
          # Normaliza primeiro (asiChoice -> asi) p/ canonicalizar shape salvo
          # com chave legada do front, depois desnormaliza (asi -> asiChoice)
          # p/ devolver no shape que o ASIChooser do wizard consome.
          canonical = LevelChoiceNormalizer.normalize_row(row)
          LevelChoiceNormalizer.denormalize_row(canonical).merge('level' => lv.to_i)
        end
        .sort_by { |r| r['level'] }
      {
        'levelChoices'        => level_choices,
        # Bug B7.3 do relatorio de auditoria: antes era `2` hardcoded. Em
        # personagem nivel 7, abrir o step Progression voltava o usuario para a
        # tab do nivel 2 ao inves do nivel mais recente (7). O front faz
        # `clamp(2, current_level)` antes de usar (ver
        # draftStorage.ts:247) entao devolver `current_level` aponta para a tab
        # do nivel mais alto editavel.
        'progressionSubLevel' => [1, sheet.current_level.to_i].max,
        'spellSelections'     => extract_spell_selections
      }
    end

    protected

    def apply!
      # Ordem: param `level` (query/body) > progressionSubLevel (wizard Próximo) >
      # levelChoice.level (PATCH incremental). Sem isso o CharacterCreation envia só
      # levelChoices[] + progressionSubLevel + spellSelections — target_level ficava nil,
      # apply! retornava cedo e spellSelections nunca persistia (GET voltava lista velha).
      target_level = @level.to_i if @level.present? && @level.to_i >= 2
      if target_level.blank?
        ps = data['progressionSubLevel'] || data[:progressionSubLevel]
        target_level = ps.to_i if ps.present?
      end
      if target_level.blank? || target_level < 2
        lc_lv = data.dig('levelChoice', 'level') || data.dig(:levelChoice, :level)
        target_level = lc_lv.to_i if lc_lv.present?
      end
      return warn!('nivel ausente para progression edit') if target_level.nil? || target_level < 2

      pre_apply_level = sheet.sheet_klasses.order(level: :desc).first&.level.to_i
      # ZE3 do segundo audit: snapshot do CON ANTES de qualquer mutacao. Usado
      # mais abaixo para detectar Δ CON real (incluindo editar ASI no MESMO
      # nivel, que nao subia hp_max — o old check `if level_changed` ignorava).
      old_con = sheet.con.to_i

      meta = (sheet.metadata || {}).deep_stringify_keys
      meta['class_choices'] ||= {}
      meta['class_choices']['per_level'] ||= {}
      # Normaliza `asiChoice` (front) -> `asi` (canonical) para que CharacterSheetSummaryService
      # aplique o +2/+1 aos atributos e nao haja "glitch de pontos" ao reabrir a edicao.
      raw_row = (data['levelChoice'] || {}).deep_dup
      normalized_patch = LevelChoiceNormalizer.normalize_row(raw_row)

      # Bug B7.1 do relatorio de auditoria de steps: antes era `=` direto, entao
      # PATCH parcial (ex.: editar so o `hp` do nivel 4) descartava `feat`,
      # `expertise`, `spells`, `subclassChoice` etc. salvos previamente. Agora
      # deep-merge: o PATCH sobrescreve apenas as chaves que vieram, preservando
      # o resto. UI de progression pode editar incrementalmente sem medo.
      existing_row = (meta['class_choices']['per_level'][target_level.to_s] || {}).deep_dup
      meta['class_choices']['per_level'][target_level.to_s] = existing_row.deep_merge(normalized_patch)
      sheet.metadata = meta

      level_changed = false
      sk = sheet.sheet_klasses.order(level: :desc).first
      if sk && sk.level.to_i < target_level
        sk.level = target_level
        sk.save!
        sheet.current_level = target_level
        level_changed = true
        # ZE3 do segundo audit: NAO recompute hp_max aqui — `sheet.con` ainda
        # e o ANTIGO (sync_ability_columns_from_metadata! ainda nao rodou,
        # entao o ASI gravado em per_level[target_level] nao chegou nas
        # colunas). hp_max usaria CON pre-ASI e ficaria incorreto. Movido
        # para depois do sync abaixo.
      end

      if data.key?('spellSelections') && data['spellSelections'].is_a?(Hash)
        # Bug B7.2 do relatorio de auditoria de steps: antes era `=` direto. PATCH
        # contendo so `cantrips` zerava `known`/`prepared`/`spellbook` salvos
        # previamente. Deep-merge preserva sub-arrays nao mencionados; quando o
        # caller QUER zerar uma sub-aba, basta enviar `[]` explicito.
        existing_sel = (meta['spell_selections'] || {}).deep_dup
        meta['spell_selections'] = existing_sel.deep_merge(normalize_spell_selections(data['spellSelections']))
        sheet.metadata = meta
      end

      sheet.save!

      sync_sheet_known_spells_from_spell_selections! if data.key?('spellSelections') && data['spellSelections'].is_a?(Hash)

      # ASI-as-feat: ProgressionEditService apenas grava `per_level[N].asi`
      # no metadata. Antes desta chamada, escolher Observador na edicao do
      # nivel 4 nao criava SheetFeat nem populava metadata['feats'] — entao
      # a ficha mostrava SAB inalterada. AsiFeatApplier ponteia per_level
      # -> FeatAssignmentService (que ja trata idempotencia: re-edit do mesmo
      # nivel substitui o feat anterior). Ver
      # spec/services/level_up_service_feats_spec.rb.
      AsiFeatApplier.call(sheet: sheet.reload, level: target_level)

      # Subclass selecionada num nivel pode adicionar grants de proficiencia;
      # ClassSummaryRebuilder lê sub_klass.levels_json indiretamente via Klass
      # apenas para skills, mas o merge final em CharacterSheetSummaryService
      # ja cobre subclass grants. Mesmo assim chamamos para refletir mudancas
      # de skills/instrumentos por nivel.
      ClassSummaryRebuilder.call(sheet)

      # Re-sincroniza str/dex/... a partir do metadata (incluindo o asi recem-gravado),
      # caso contrario o flag `ability_scores_include_all_increments` faz a leitura de
      # `build_abilities` voltar as colunas antigas e o ASI editado nao aparece (gera o
      # "glitch de pontos" na proxima edicao).
      CharacterSheetSummaryService.sync_ability_columns_from_metadata!(sheet.reload)

      # PV: alinhar com `per_level` + racial (como o wizard). Antes só recomputava
      # quando CON mudava ou o nível subia — editar PV no mesmo nível não atualizava hp_max.
      hp_patch = normalized_patch.stringify_keys.key?('hp')
      if hp_patch || sheet.con.to_i != old_con || level_changed
        apply_progression_hp_to_sheet!
        sheet.save!
      end

      # Gap G7.5 do relatorio de auditoria de steps: ProgressionEditService
      # bypassava o LevelUpGuardService, entao um cliente podia subir o
      # personagem para o nivel N sem ter feito as escolhas obrigatorias dos
      # niveis anteriores (manobras de Battle Master, invocacoes de Bruxo,
      # disciplinas de Quatro Elementos, snacks de Cozinheiro, fighting style
      # de Guerreiro, etc.). Resultado: ficha permanecia em estado invalido
      # até o LevelUpService bater no guard num futuro level-up programatico.
      #
      # Estrategia:
      #   - So roda guard quando target_level > pre_apply_level (level-up
      #     real), pois editar per_level de um nivel ja existente nao precisa
      #     re-validar (esse nivel ja passou no guard no passado).
      #   - `force: true` na requisicao pula a validacao (mesma semantica de
      #     destrutividade ja existente em race/class edit).
      #   - Falha do guard levanta excecao que sera capturada pelo wrapper
      #     `ActiveRecord::Base.transaction` em `BaseSheetEditService#call`,
      #     fazendo rollback completo do PATCH e reportando os requisitos
      #     faltantes no `requires_confirmation` para a UI exibir.
      enforce_level_up_guard!(target_level: target_level, pre_apply_level: pre_apply_level)
    end

    private

    def enforce_level_up_guard!(target_level:, pre_apply_level:)
      return if force?
      return unless target_level > pre_apply_level

      sk = sheet.sheet_klasses.order(level: :desc).first
      return unless sk&.klass

      guard = LevelUpGuardService.call(sheet: sheet.reload, klass: sk.klass)
      return if guard.success?

      msgs = guard.errors.full_messages
      msgs.each { |m| warn!(m) }
      @requires_confirmation = {
        reason: "Subir para nivel #{target_level} requer escolhas pendentes: #{msgs.join('; ')}",
        cleared: ['progression.level_up']
      }
      raise ActiveRecord::Rollback
    rescue ActiveRecord::Rollback
      raise
    rescue StandardError => e
      # ZE5 do segundo audit: a versao antiga so logava warn e CONTINUAVA, deixando
      # passar level-ups que o guard nao conseguiu validar por bug interno. Como
      # o guard pode estar bloqueando regras criticas (subclasse pendente, ASI nao
      # escolhido), preferimos rollback + log nivel error. Cliente recebe 500 com
      # trace_id (via ZC4) — mais visivel que estado inconsistente silencioso.
      Rails.logger.error "[ProgressionEditService] LevelUpGuardService raised: #{e.class}: #{e.message}\n#{e.backtrace&.first(10)&.join("\n")}"
      raise ActiveRecord::Rollback
    end

    # Devolve o shape `{ cantrips, known, spellbook, prepared }` que o wizard
    # consome em `SpellPicker`/`SpellPreparation`. Estratégia em duas camadas:
    #
    # 1. Se `metadata.spell_selections` existe (caminho da criação atual e do
    #    PATCH em edição), usamos integralmente — é o "rascunho" do que o
    #    usuário escolheu, com a separação cantrip/known/spellbook/prepared.
    # 2. Caso contrário (personagens antigos provisionados antes do campo, ou
    #    fichas geradas via admin/import), reconstruímos a partir do BANCO:
    #    SheetKnownSpell + SheetPreparedSpell. Sem isso o Mago abria o step
    #    "Grimório & Preparação" totalmente vazio e tinha que re-escolher
    #    todas as cantrips/magias preparadas — bug "cantrips não persistem".
    def extract_spell_selections
      meta_sel = (sheet.metadata || {})['spell_selections']
      spell_selection_keys = %w[cantrips known spellbook prepared]
      if meta_sel.is_a?(Hash) && (meta_sel.keys.map(&:to_s) & spell_selection_keys).any?
        return normalize_spell_selections(meta_sel)
      end
      derive_spell_selections_from_db
    rescue StandardError => e
      Rails.logger.warn "[ProgressionEditService] derive spell selections failed: #{e.class}: #{e.message}"
      { 'cantrips' => [], 'known' => [], 'spellbook' => [], 'prepared' => [] }
    end

    def derive_spell_selections_from_db
      cantrips = []
      known = []
      sk_ids = sheet.sheet_klasses.pluck(:id)
      if sk_ids.any?
        rows = SheetKnownSpell
                 .joins(:spell)
                 .where(sheet_klass_id: sk_ids)
                 .pluck('spells.level', 'spells.name')
        rows.each do |lvl, name|
          (lvl.to_i.zero? ? cantrips : known) << name.to_s
        end
      end

      prepared_user = SheetPreparedSpell
                        .joins(:spell)
                        .where(sheet_id: sheet.id, auto: false)
                        .pluck('spells.name')
                        .map(&:to_s)

      # Para classes "spellbook" (Mago), o "spellbook" é o próprio conjunto de
      # magias conhecidas (não-cantrip). Para conjuradores espontâneos/preparados
      # `spellbook` fica vazio (UI esconde a aba).
      is_wizard = begin
        primary_sk = sheet.sheet_klasses.order(level: :desc).first
        primary_sk&.klass&.api_index.to_s == 'wizard'
      rescue StandardError
        false
      end

      {
        'cantrips' => cantrips.uniq,
        'known' => known.uniq,
        'spellbook' => is_wizard ? known.uniq : [],
        'prepared' => prepared_user.uniq
      }
    end

    def normalize_spell_selections(raw)
      sel = (raw || {}).deep_dup.stringify_keys
      %w[cantrips known spellbook prepared].each do |key|
        sel[key] = Array(sel[key]).map(&:to_s).uniq if sel.key?(key)
      end

      # No wizard, `spellbook` is the authoritative known-spell set. Older edit
      # payloads can carry stale `known`, which would re-add removed spells on
      # save/reprovision.
      if wizard_spellbook_mode? && sel['spellbook'].is_a?(Array)
        sel['known'] = sel['spellbook']
      end

      sel
    end

    def wizard_spellbook_mode?
      primary_sk = sheet.sheet_klasses.order(level: :desc).first
      primary_sk&.klass&.api_index.to_s == 'wizard'
    rescue StandardError
      false
    end

    # Alinha `SheetKnownSpell` (fonte do summary / catalog_by_id no KnownSpellsAggregator) com
    # `metadata.spell_selections` após PATCH — antes só o metadata mudava e a ficha continuava
    # com rows antigas do banco.
    def sync_sheet_known_spells_from_spell_selections!
      sheet.reload
      sk = sheet.sheet_klasses.order(level: :desc).first
      return unless sk&.klass

      if sheet.sheet_klasses.where.not(klass_id: sk.klass_id).exists?
        return
      end

      k = sk.klass
      rules = k.api_index.present? ? (ClassRules.find(k.api_index) || {}) : {}
      prep = (rules.dig(:feature_rules, :spellcasting, :mode) ||
        rules.dig(:spellcasting, :preparation)).to_s
      return if prep == 'prepared'

      meta = (sheet.metadata || {}).deep_stringify_keys
      sel = normalize_spell_selections(meta['spell_selections'] || {})

      class_sources = [nil, 'class', 'subclass']
      SheetKnownSpell.where(sheet_klass_id: sk.id, source: class_sources).delete_all

      resolver = SpellResolver.new
      ids = []
      %w[cantrips known].each do |key|
        Array(sel[key]).each do |tok|
          sp = resolver.resolve(tok)
          ids << sp.id.to_i if sp&.id.to_i.positive?
        end
      end

      # `sheet_known_spells` tem índice único (sheet_klass_id, spell_id) sem incluir `source`.
      # Magias raciais/feats permanecem após o delete_all acima; tentar create! para a mesma
      # spell_id aborta a transação PG (RecordNotUnique) e o rescue piora com InFailedSqlTransaction.
      ids.uniq.each do |sid|
        next if SheetKnownSpell.exists?(sheet_klass_id: sk.id, spell_id: sid)

        SheetKnownSpell.create!(sheet_klass_id: sk.id, spell_id: sid, source: 'class')
      end
    end
  end
end
