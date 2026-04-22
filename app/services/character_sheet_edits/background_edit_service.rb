module CharacterSheetEdits
  class BackgroundEditService < BaseSheetEditService
    def step_key = 'background'

    def read
      bg = sheet.background
      meta = sheet.metadata || {}
      bg_summary = meta['background_summary'].is_a?(Hash) ? meta['background_summary'] : {}
      bg_col = sheet.read_attribute(:background_summary)
      bg_col = {} unless bg_col.is_a?(Hash)
      bc = (meta['background_choices'] || {})

      # Para cada campo, prefira a escolha persistida em `background_choices` (fonte
      # canônica do step), depois faça fallback para o `background_summary` (escrito
      # pelo provisioning) — assim personagens criados antes do edit-flow ainda
      # devolvem as escolhas que o provisioning inferiu.
      pick = ->(key_choice, key_summary) {
        v = Array(bc[key_choice])
        v.presence || Array(bg_summary[key_summary]).presence || Array(bg_col[key_summary])
      }

      # Bug B3.2 do relatorio de auditoria de steps: antes do fix, `apply!`
      # concatenava `tools + languages` num unico array em
      # `meta['background_proficiencies']`, e o `read` devolvia esse array
      # inteiro como `backgroundToolChoices` — entao o idioma "Anão" do
      # Soldado virava "ferramenta" ao reabrir o step. Agora persistimos
      # separadamente em `background_choices.{tools,languages}` (canonico)
      # e mantemos o legado `background_proficiencies` so para retrocompat
      # com chars antigos que nao tiveram re-save apos o fix.
      {
        'backgroundId'   => sheet.background_id&.to_s,
        'backgroundName' => bg&.name,
        'backgroundToolChoices'    => Array(bc['tools']).presence ||
                                      Array(bg_summary['tools']).presence ||
                                      Array(bg_col['tools']) || [],
        'backgroundLanguageChoices'=> Array(bc['languages']).presence ||
                                      Array(bg_summary['languages']).presence ||
                                      Array(bg_col['languages']) || [],
        'backgroundPersonalityTraits' => pick.call('traits', 'personality_traits') || [],
        'backgroundIdeals' => pick.call('ideals', 'ideals') || [],
        'backgroundBonds'  => pick.call('bonds', 'bonds') || [],
        'backgroundFlaws'  => pick.call('flaws', 'flaws') || []
      }
    end

    BACKGROUND_CHANGED_REASON =
      'Trocar de antecedente apaga as proficiencias em ferramentas/idiomas e os ' \
      'tracos de personalidade do antecedente anterior.'

    CHOICE_KEYS = %w[traits ideals bonds flaws].freeze

    protected

    def apply!
      background_changed = false

      if data.key?('backgroundId')
        # Bug B3.1 do relatorio de auditoria de steps: antes usavamos `to_i`
        # direto, entao slug ('soldier', 'soldado') virava 0 e o background era
        # apagado silenciosamente. Espelha o pattern de `RaceEditService` /
        # `ClassEditService` (resolve por id numerico OU api_index kebab/snake).
        #
        # ZE1 do segundo audit: o resolve_background_id retorna `nil` para slugs
        # invalidos. Antes, o codigo entrava no branch `new_bg_id.to_i (=0) !=
        # sheet.background_id.to_i (positivo)` e gravava `sheet.background_id
        # = nil` — perdia o background do personagem silenciosamente. Agora
        # distinguimos 3 casos:
        #   1. raw nil/blank  -> caller pediu clear EXPLICITO (aceita).
        #   2. slug invalido  -> warn! e NAO altera nada (skip do branch).
        #   3. slug valido    -> mesma logica anterior.
        raw = data['backgroundId']
        if raw.nil? || raw.to_s.strip.empty?
          if sheet.background_id.present?
            background_changed = true
            sheet.background_id = nil
          end
        else
          new_bg_id = resolve_background_id(raw)
          if new_bg_id.nil?
            warn!("backgroundId '#{raw}' nao corresponde a nenhum Background conhecido — campo nao alterado")
          elsif new_bg_id.to_i != sheet.background_id.to_i
            background_changed = sheet.background_id.present? && new_bg_id.present?
            sheet.background_id = new_bg_id
          end
        end
      end

      meta = (sheet.metadata || {}).deep_stringify_keys
      bc = (meta['background_choices'] || {}).deep_dup

      # Gap G3.3 do relatorio de auditoria de steps: trocar de background no
      # edit mode mantinha `background_choices.{traits,ideals,bonds,flaws}` e
      # `background_proficiencies` do bg antigo. Mesma logica do creation
      # (BackgroundStepService): so zera as chaves que NAO vieram no MESMO
      # PATCH. `force: true` requerido para confirmar destruicao.
      if background_changed
        # ZE8 do segundo audit: a versao antiga emitia um unico
        # `clear!('metadata.background_choices')` generico — UI mostrava aviso
        # impreciso ("vai perder background_choices") sem dizer quais sub-chaves.
        # Agora rastreamos sub-chaves especificas e emitimos clear! granular,
        # paridade com Race/Class.
        cleared_keys_local = []
        CHOICE_KEYS.each do |k|
          next if data.key?("background#{k.capitalize}") || data.key?("background_#{k}")
          payload_key = case k
                        when 'traits' then 'backgroundPersonalityTraits'
                        when 'ideals' then 'backgroundIdeals'
                        when 'bonds'  then 'backgroundBonds'
                        when 'flaws'  then 'backgroundFlaws'
                        end
          next if data.key?(payload_key)
          if bc[k].present?
            bc[k] = []
            cleared_keys_local << "background_choices.#{k}"
          end
        end

        unless data.key?('backgroundToolChoices') || data.key?('backgroundLanguageChoices')
          if meta['background_proficiencies'].present?
            meta['background_proficiencies'] = []
            cleared_keys_local << 'background_proficiencies'
          end
          # Bug B3.2: zera tambem os campos canonicos (tools/languages
          # separados em `background_choices`) — sem isso, ao trocar de
          # background sem reenviar profs, o read voltaria a devolver
          # tools/languages do bg antigo via `bc['tools']`/`bc['languages']`.
          if bc['tools'].present? || bc['languages'].present?
            bc['tools'] = []
            bc['languages'] = []
            cleared_keys_local << 'background_choices.tools'
            cleared_keys_local << 'background_choices.languages'
          end
        end

        # `background_summary` sera reconstruido em `rebuild_background_summary!`
        # logo abaixo a partir do novo bg + choices vazias.
        cleared_keys_local.each do |k|
          clear!(k, reason: BACKGROUND_CHANGED_REASON, confirm: true)
        end
      end

      bc['traits'] = Array(data['backgroundPersonalityTraits']) if data.key?('backgroundPersonalityTraits')
      bc['ideals'] = Array(data['backgroundIdeals'])            if data.key?('backgroundIdeals')
      bc['bonds']  = Array(data['backgroundBonds'])             if data.key?('backgroundBonds')
      bc['flaws']  = Array(data['backgroundFlaws'])             if data.key?('backgroundFlaws')

      # Bug B3.2 do relatorio de auditoria de steps: tools e languages tem
      # semantica diferente (tools = SheetItem proficiencia; languages =
      # idiomas falados/escritos) e precisam ser persistidos separadamente
      # para o `read` reconstruir corretamente. Antes do fix, o `read`
      # devolvia `meta['background_proficiencies']` (tools+langs misturados)
      # como `backgroundToolChoices`, fazendo o idioma "Anão" do Soldado
      # virar "ferramenta" ao reabrir o step na UI.
      bc['tools']     = Array(data['backgroundToolChoices'])     if data.key?('backgroundToolChoices')
      bc['languages'] = Array(data['backgroundLanguageChoices']) if data.key?('backgroundLanguageChoices')

      meta['background_choices'] = bc

      # Mantem o legado `background_proficiencies` (tools+langs concatenado)
      # porque outros consumidores (CharacterSheetSummaryService, exports
      # antigos) ainda leem dessa chave. Eventualmente sera removido apos
      # migracao completa para `background_choices.{tools,languages}`.
      if data.key?('backgroundToolChoices') || data.key?('backgroundLanguageChoices')
        legacy_tools = data.key?('backgroundToolChoices') ? Array(data['backgroundToolChoices']) : Array(bc['tools'])
        legacy_langs = data.key?('backgroundLanguageChoices') ? Array(data['backgroundLanguageChoices']) : Array(bc['languages'])
        meta['background_proficiencies'] = legacy_tools + legacy_langs
      end

      if sheet.background
        sheet.background_key = sheet.background.api_index
        meta['background'] = sheet.background.name
        meta['background_key'] = sheet.background.api_index
      end

      # Reidempotente: re-deriva `background_summary` (skills/tools/feature/equipment/
      # languages + personality/ideals/bonds/flaws escolhidos) toda vez que algo do
      # background muda. Sem isso, `metadata.background_summary` continuava com o
      # snapshot do provisioning inicial — ou pior, vazio — e o
      # `CharacterSheetSummaryService#build_background` devolvia
      # `background.skills: []`, fazendo o step "Antecedente" do wizard parecer
      # incompleto após reload.
      rebuild_background_summary!(meta)

      sheet.metadata = meta
      sheet.save!
    end

    private

    # X2: delega ao helper compartilhado.
    def resolve_background_id(raw)
      resolve_polymorphic_id(Background, raw)
    end

    def rebuild_background_summary!(meta)
      bg = sheet.background
      return unless bg && bg.api_index.present?

      bc = meta['background_choices'] || {}

      # ZE4 do segundo audit: a versao antiga lia tools/idiomas APENAS de `data`,
      # ignorando o que ja estava persistido em `bc`. PATCH parcial (so
      # personality, sem tocar em tools) gerava summary com `tools: []` mesmo
      # tendo escolhas salvas. Agora preferimos `data` (mais novo, fresh edit)
      # e caimos para `bc` quando `data` omite a chave — paridade com o
      # deep_merge geral do edit service.
      tool_data = data.key?('backgroundToolChoices') ? Array(data['backgroundToolChoices']) : Array(bc['tools'])
      tool_choices = tool_data.map { |x| x.is_a?(Hash) ? (x['name'] || x[:name]) : x }.compact

      lang_data = data.key?('backgroundLanguageChoices') ? Array(data['backgroundLanguageChoices']) : Array(bc['languages'])
      lang_choices = lang_data.map { |x| x.is_a?(Hash) ? (x['name'] || x[:name]) : x }.compact
      summary = BackgroundRules.apply(
        key: bg.api_index,
        choices: {
          languages: lang_choices,
          tools: tool_choices,
          gaming_set: tool_choices,
          instrument: tool_choices,
          personalityTraits: Array(bc['traits']),
          ideals: Array(bc['ideals']),
          bonds: Array(bc['bonds']),
          flaws: Array(bc['flaws'])
        }
      )
      stringified = summary.deep_stringify_keys
      meta['background_summary'] = stringified
      sheet.background_summary = stringified
    rescue StandardError => e
      warn!("BackgroundRules.apply falhou: #{e.message}")
    end
  end
end
