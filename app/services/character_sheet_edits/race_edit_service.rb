module CharacterSheetEdits
  # Race edit em modo edit: troca raca/sub-raca, persiste raceChoices/gender e
  # **recomputa todo o snapshot racial** (race_summary, race_bonuses_applied,
  # ability columns, hp_max via CON delta).
  #
  # Bugs B2.2 e B2.3 do relatorio de auditoria de steps: antes deste fix,
  # `recompute_race_summary!` so persistia name/speed/languages/proficiencies e
  # **descartava traits/darkvision/sub_race_name extras**. E `apply!` nao
  # atualizava `meta['race_bonuses_applied']` nem chamava
  # `CharacterSheetSummaryService.sync_ability_columns_from_metadata!` apos
  # mudar race_id — entao trocar Anao (CON+2) por Halfling (DES+2) deixava o
  # CON antigo somado nas colunas e o DES novo nao aparecia. Replicado da
  # logica de provisioning (`character_provisioning_service.rb:222-296`).
  class RaceEditService < BaseSheetEditService
    ABILITY_KEYS = %w[str dex con int wis cha].freeze

    def step_key = 'race'

    def read
      race = sheet.race_id.present? ? Race.find_by(id: sheet.race_id) : nil
      sub_race = sheet.sub_race_id.present? ? SubRace.find_by(id: sheet.sub_race_id) : nil
      meta = sheet.metadata || {}
      race_choices = meta.dig('race_choices') || {}

      {
        'raceId' => sheet.race_id&.to_s,
        'subraceId' => sheet.sub_race_id&.to_s,
        # Nomes/slugs canônicos do banco — fonte da verdade para o front. Sem isso o
        # front tinha que adivinhar pelo id (DB id vs catálogo mock id) e quebrava
        # quando o catálogo desatualizava ou o backend devolvia id numérico cru.
        'raceName' => race&.name,
        'raceRuleSlug' => race&.api_index,
        'subraceName' => sub_race&.name,
        'subraceRuleSlug' => sub_race&.api_index,
        'raceChoices' => race_choices,
        # Bug B2.1 do relatorio de auditoria: antes devolvia `nil` hardcoded.
        # Variant Human persiste a escolha do feat racial em
        # `race_choices.variantHumanASI` (mesma estrutura usada por
        # `CharacterProvisioningService` para invocar `FeatAssignmentService`).
        'featId' => extract_racial_feat_id(race_choices),
        'gender' => (sheet.avatar_customization || {})['gender']
      }
    end

    protected

    def apply!
      new_race_id = data['raceId']
      resolved_race_id = resolve_race_id(new_race_id)
      if new_race_id.present? && resolved_race_id.present? && resolved_race_id != sheet.race_id.to_i
        ensure_playable_race_allowed!(race_id: resolved_race_id, sub_race_id: nil)
        clear!('sheet.metadata.race_choices', reason: DESTRUCTIVE_REASONS[:race_changed], confirm: true)
        sheet.race_id = resolved_race_id
        sheet.sub_race_id = nil
      end

      if data.key?('subraceId')
        # Mesma motivação do `ClassEditService`: aceita id numérico, slug
        # do banco (kebab/snake) ou ruleSlug do catálogo do front.
        target_race_id = sheet.race_id
        resolved_sub = resolve_sub_race_id(data['subraceId'], race_id: target_race_id)
        if data['subraceId'].present? && resolved_sub.nil?
          warn!("subraceId '#{data['subraceId']}' não resolveu para nenhuma SubRace de race_id=#{target_race_id}; nada alterado")
        else
          ensure_playable_race_allowed!(race_id: target_race_id, sub_race_id: resolved_sub)
          sheet.sub_race_id = resolved_sub
        end
      end

      if data.key?('raceChoices')
        meta = (sheet.metadata || {}).deep_stringify_keys
        meta['race_choices'] = data['raceChoices']
        sheet.metadata = meta
        
        # ZF9: Apply Variant Human feat if variantHumanASI is present
        vh = data['raceChoices'].is_a?(Hash) ? (data['raceChoices']['variantHumanASI'] || data['raceChoices'][:variantHumanASI]) : nil
        if vh.is_a?(Hash) && (vh['mode'] || vh[:mode]).to_s == 'feat'
          feat_id = vh['featId'] || vh[:featId] || vh['featName'] || vh[:featName]
          if feat_id.present?
            choices = vh['choices'] || vh[:choices] || {}
            FeatAssignmentService.call(sheet: sheet, feat_id: feat_id, level_gained: 1, choices: choices)
          end
        end
      end

      if data.key?('gender')
        # Gap G10.2 do relatorio de auditoria de steps: chave canonica de
        # gender e UMA SO — `sheet.avatar_customization['gender']`. Tanto
        # este service como AvatarEditService escrevem exatamente aqui;
        # PATCHes paralelos resolvem por last-write-wins na mesma chave
        # (aceitavel) e o `read` de ambos faz `dig('gender')`. NUNCA
        # introduzir uma coluna paralela (`sheet.gender`) sem antes
        # remover esta chave de `avatar_customization`.
        ac = (sheet.avatar_customization || {}).deep_stringify_keys
        ac['gender'] = data['gender']
        sheet.avatar_customization = ac
      end

      sheet.save!

      # Re-deriva todo snapshot racial: race_summary (com traits/darkvision/etc)
      # e race_bonuses_applied. Idempotente — pode rodar mesmo quando so
      # raceChoices/gender mudaram (atualiza idiomas escolhidos, p.ex.).
      recompute_race_summary_and_bonuses!

      # Re-sincroniza colunas de ability scores: subtrai bonus racial antigo
      # implicito e soma novo (`build_abilities` agora ve race_bonuses_applied`
      # atualizado).
      CharacterSheetSummaryService.sync_ability_columns_from_metadata!(sheet.reload)

      # PV máximo deve refletir CON atual e também bônus raciais como Robustez Anã (+1/nível),
      # mesmo quando o total de CON não muda (ex.: Anão Montanha ↔ Anão da Colina).
      recompute_hp_max!(new_con: sheet.con.to_i)
      sheet.save! if sheet.changed?

      # Bug "Drow → Tiefling guardava magias antigas": antes deste reapply,
      # o edit per-step de raca nao tocava SheetKnownSpell.from_race — entao
      # mudar raca via wizard de edicao deixava as magias da raca anterior
      # presas na ficha (Globos de Luz do Drow continuavam apos virar
      # Tiefling). RacialSpellsService.call agora limpa `from_race` antes
      # de re-aplicar, deixando a operacao idempotente.
      reapply_racial_spells!

      # `apply!` retorna implicitamente; warnings/cleared keys ja foram
      # acumulados via `warn!`/`clear!`.
    end

    private

    def extract_racial_feat_id(race_choices)
      hv = (race_choices['variantHumanASI'] || race_choices[:variantHumanASI])
      return nil unless hv.is_a?(Hash) && (hv['mode'] || hv[:mode]).to_s == 'feat'
      hv['featId'] || hv[:featId] || hv['featName'] || hv[:featName]
    end

    def recompute_race_summary_and_bonuses!
      race = Race.find_by(id: sheet.race_id) or return
      sub_race = SubRace.find_by(id: sheet.sub_race_id)
      rid = race.api_index.presence || race.name.to_s.parameterize(separator: '_')
      sid = sub_race&.api_index&.presence || sub_race&.name&.to_s&.parameterize(separator: '_')
      choices = (sheet.metadata || {}).dig('race_choices') || {}
      extra_langs = Array(choices['chosenLanguages']).flatten.compact.map(&:to_s)
      applied = RaceRules.apply(race_id: rid, subrace_id: sid, choices: { extraLanguages: extra_langs })

      # Speed em 3 níveis (paridade com CharacterProvisioningService:281-288):
      #   1. `applied[:speed]` do RaceRules.apply (fonte canônica do YAML)
      #   2. `race.speed_ft` da coluna do model (legado, raramente usado)
      #   3. 30 ft como fallback final (último recurso para raça sem dados)
      # Antes, o RaceEdit pulava o nível 2 com `.to_i.nonzero? || 30`,
      # gerando inconsistência silenciosa criação ↔ edição.
      applied_speed = applied[:speed].to_i
      speed_ft = if applied_speed.positive?
                   applied_speed
                 elsif race.respond_to?(:speed_ft) && race.speed_ft.present?
                   race.speed_ft.to_i
                 else
                   30
                 end

      summary = {
        'name' => race.name,
        'race_name' => race.name,
        'speed_ft' => speed_ft,
        'sub_race_name' => sub_race&.name
      }.compact
      summary['languages'] = applied[:languages].map(&:to_s) if applied[:languages].present?
      summary['proficiencies'] = applied[:proficiencies].deep_stringify_keys if applied[:proficiencies].is_a?(Hash)
      # Darkvision vem como Hash `{range: 60}` no YAML; `RaceRules.normalize_range`
      # cuida da extração. Antes do fix, `.to_i` direto em Hash retornava 0 e
      # a linha nunca gravava (mesmo bug do CPS pré-fix).
      dv_val = RaceRules.normalize_range(applied[:darkvision])
      summary['darkvision'] = dv_val if dv_val.positive?

      # Traits: junta base_traits da raca + traits da sub-raca (mesma logica do
      # CharacterProvisioningService:261-269). Sem isso a edicao de raca apaga
      # darkvision, fey ancestry, brave, etc. da ficha.
      begin
        trait_records = race.base_traits.to_a
        trait_records += sub_race.traits.to_a if sub_race
        trait_records.uniq!(&:id)
        if trait_records.any?
          summary['traits'] = trait_records.map { |t| { 'name' => t.name, 'description' => t.description.to_s } }
        end
      rescue StandardError => e
        warn!("traits da raca falharam: #{e.message}")
      end

      sheet.race_summary = summary

      # `race_bonuses_applied` e a fonte da verdade para `inc_race` em
      # `character_sheet_summary_service.rb#build_abilities`. Sem atualizar aqui,
      # ability scores ficam stale apos troca de raca (bug B2.3).
      meta = (sheet.metadata || {}).deep_stringify_keys
      ability_bonuses = (applied[:ability] || {}).each_with_object({}) do |(k, v), h|
        ks = k.to_s.downcase
        next unless ABILITY_KEYS.include?(ks)
        h[ks] = v.to_i if v.to_i != 0
      end
      meta['race_bonuses_applied'] = ability_bonuses
      sheet.metadata = meta
      sheet.save!
    rescue StandardError => e
      warn!("RaceRules.apply falhou: #{e.message}")
    end

    # Re-aplica magias raciais inatas com base na raca/sub-raca atual da
    # ficha. Idempotente: `RacialSpellsService` limpa todas as magias com
    # `source: 'race'` antes de inserir as novas, entao chamadas repetidas
    # sao seguras e a troca de raca remove magias antigas automaticamente.
    def reapply_racial_spells!
      return unless sheet.race_id.present?
      return unless sheet.sheet_klasses.exists?

      race = Race.find_by(id: sheet.race_id) or return
      sub_race = SubRace.find_by(id: sheet.sub_race_id)
      rid = race.api_index.presence || race.name.to_s.parameterize(separator: '_')
      sid = sub_race&.api_index&.presence || sub_race&.name&.to_s&.parameterize(separator: '_')
      choices = (sheet.metadata || {}).dig('race_choices') || {}
      extra_langs = Array(choices['chosenLanguages']).flatten.compact.map(&:to_s)
      race_rule = RaceRules.apply(race_id: rid, subrace_id: sid, choices: { extraLanguages: extra_langs })

      RacialSpellsService.call(
        sheet: sheet,
        race_rule: race_rule,
        character_level: CharacterRules.total_level(sheet)
      )
    rescue StandardError => e
      warn!("RacialSpellsService falhou: #{e.message}")
    end

    def ensure_playable_race_allowed!(race_id:, sub_race_id:)
      return if allow_non_playable_race?

      race_record = race_id.present? ? Race.find_by(id: race_id) : nil
      if race_record.present? && !race_record.playable?
        raise ArgumentError, 'Raça indisponível para personagens de jogador. Apenas mestres podem usá-la em NPCs.'
      end

      sub_race_record = sub_race_id.present? ? SubRace.find_by(id: sub_race_id) : nil
      return unless sub_race_record.present? && !sub_race_record.playable?

      raise ArgumentError, 'Sub-raça indisponível para personagens de jogador. Apenas mestres podem usá-la em NPCs.'
    end

    def allow_non_playable_race?
      Group.user_is_dm?(current_user) && sheet_npc?
    end

    def sheet_npc?
      general = (sheet.metadata || {}).dig('general') || {}
      ActiveModel::Type::Boolean.new.cast(general['isNPC'] || general[:isNPC])
    end

    # X2: agora delega ao helper compartilhado em BaseSheetEditService.
    def resolve_race_id(raw)
      resolve_polymorphic_id(Race, raw)
    end

    def resolve_sub_race_id(raw, race_id:)
      return nil if raw.blank?
      str = raw.to_s.strip
      if str.match?(/\A\d+\z/)
        sr = SubRace.find_by(id: str.to_i)
        return sr&.race_id == race_id ? sr.id : nil
      end
      slug_kebab = str.downcase.gsub('_', '-')
      slug_snake = slug_kebab.tr('-', '_')
      SubRace.where(race_id: race_id)
             .where('LOWER(api_index) IN (?)', [slug_kebab, slug_snake])
             .pick(:id)
    end
  end
end
