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
        'progressionSubLevel' => [2, sheet.current_level.to_i].max,
        'spellSelections'     => extract_spell_selections
      }
    end

    protected

    def apply!
      target_level = level || data.dig('levelChoice', 'level')&.to_i
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
        meta['spell_selections'] = existing_sel.deep_merge(data['spellSelections'])
        sheet.metadata = meta
      end

      sheet.save!

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

      # ZE3 do segundo audit: recomputa hp_max sempre que CON real mudar (ASI
      # mesmo nivel) OU quando subir de nivel (delta de hit-die por nivel).
      # Antes era so dentro do branch `if sk.level < target_level` e usava
      # CON pre-sync — bug duplo: ASI mesmo-nivel ignorava, level-up usava
      # CON antigo. Agora roda APOS sync, com CON real, em ambos cenarios.
      if sheet.con.to_i != old_con || level_changed
        recompute_hp_max!(new_con: sheet.con.to_i)
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
      return meta_sel if meta_sel.is_a?(Hash) && meta_sel.values.any? { |v| v.is_a?(Array) && v.any? }
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
  end
end
