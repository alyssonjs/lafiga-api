require 'set'

class CharacterProvisioningService
  prepend SimpleCommand

  # Params:
  # - user: User (owner) for player flow; admin flow may pass nil and include character.user_id in payload
  # - payload: Hash with keys 'character' and 'wizard' (legacy, frontend builds this)
  # - character: Character record (used together with `from_server_draft: true`)
  # - from_server_draft: when true, derives payload from character.draft_data via
  #   CharacterDraftPayloadBuilder. Frontend can call /provision with no body.
  def initialize(user:, payload: {}, character: nil, from_server_draft: false, actor_user: nil)
    @current_user = user
    @actor_user = actor_user || user
    @payload = payload || {}
    @character_arg = character
    @from_server_draft = !!from_server_draft

    if @from_server_draft
      raise ArgumentError, 'from_server_draft requires `character:`' if @character_arg.nil?

      # Camada 2 (defesa em profundidade): rejeitamos chars sem draft_data
      # ANTES do builder/save, com mensagem precisa. O controller também faz
      # esse guard, mas mantemos aqui para proteger uso direto via Rails
      # console / Sidekiq / outros futuros controllers que esquecerem o guard.
      if (@character_arg.draft_data || {}).empty?
        raise ArgumentError,
              "from_server_draft chamado em character ##{@character_arg.id} " \
              "(status=#{@character_arg.status}) com draft_data vazio. Esse " \
              'caminho é exclusivo de drafts em criação; para editar chars ' \
              'ativos use PATCH /character_drafts/:id em modo edit.'
      end

      @payload = CharacterDraftPayloadBuilder.build(@character_arg)
    end
  end

  def call
    ActiveRecord::Base.transaction do
      cdata   = (@payload['character'] || @payload[:character] || {}).dup
      wizard  = (@payload['wizard']    || @payload[:wizard]    || {}).dup

      # Resolve owner
      owner = @current_user
      if owner.nil?
        uid = (cdata['user_id'] || cdata[:user_id]).presence
        raise StandardError, 'user_id obrigatório para provisão via admin' if uid.blank?
        owner = User.find(uid)
      end

      # Upsert Character (allow draft id)
      char = nil
      # Fallbacks for name/background from wizard payload when absent at character root
      name_fallback = begin
        (cdata['name'] || cdata[:name]).presence ||
        (wizard.dig('meta','name') || wizard.dig(:meta, :name)).presence
      rescue
        (cdata['name'] || cdata[:name])
      end
      background_fallback = begin
        (cdata['background'] || cdata[:background]).presence ||
        (wizard.dig('background','backgroundName') || wizard.dig(:background, :backgroundName)).presence
      rescue
        (cdata['background'] || cdata[:background])
      end

      if (cid = (cdata['id'] || cdata[:id]).presence)
        # DM/Admin pode reprovisionar fichas alheias (ex.: Mestre concluindo o
        # wizard de edicao de um PC importado). Player comum continua restrito
        # ao proprio escopo. Quando DM editando ficha de outro user, preservamos
        # o dono original — owner_id NAO e sobrescrito.
        char =
          if Group.user_is_dm?(owner)
            Character.find(cid)
          else
            owner.characters.find(cid)
          end
        # Só tocar em `group_id` se o payload trouxer a chave. Caso contrário, o
        # `||` cai em `nil` e o assign_attributes *desvinculava* o personagem
        # do grupo em todo reprovision/edição — grupo/campanha perdia o membro;
        # o `schedule.character_ids` do calendário continuava antigo (5 na UI)
        # enquanto o GroupSerializer listava só quem ainda tem `group_id` (4).
        attrs = {
          name: name_fallback,
          background: background_fallback,
          status: cdata['status'] || cdata[:status] || Character.statuses['active']
        }
        if cdata.key?('group_id') || cdata.key?(:group_id)
          attrs[:group_id] = cdata['group_id'] || cdata[:group_id]
        end
        char.assign_attributes(attrs)
        # keep draft_data if present from client
        char.draft_data = cdata['draft_data'] || cdata[:draft_data] if cdata.key?('draft_data') || cdata.key?(:draft_data)
        char.current_step = cdata['current_step'] || cdata[:current_step] if cdata.key?('current_step') || cdata.key?(:current_step)
        char.save!
      else
        char = owner.characters.create!(
          name: name_fallback,
          background: background_fallback,
          group_id: cdata['group_id'] || cdata[:group_id],
          status: cdata['status'] || cdata[:status] || Character.statuses['active'],
          draft_data: cdata['draft_data'] || cdata[:draft_data]
        )
      end

      # Prepare sheet base attributes from wizard
      race     = wizard['race']     || wizard[:race]     || {}
      bg       = wizard['background'] || wizard[:background] || {}
      klass    = wizard['klass']    || wizard[:klass]    || {}
      equip    = wizard['equipment']|| wizard[:equipment]|| {}
      meta     = wizard['meta']     || wizard[:meta]     || {}
      avatar_block = wizard['avatar'] || wizard[:avatar] || {}
      raw_avatar_cust = avatar_block['customization'] || avatar_block[:customization]
      avatar_cust =
        if raw_avatar_cust.is_a?(Hash)
          raw_avatar_cust.stringify_keys
        elsif raw_avatar_cust.is_a?(ActionController::Parameters)
          raw_avatar_cust.to_unsafe_h.stringify_keys
        else
          {}
        end

      # Atributos pós-racial (totais do payload). Fallback = atributo neutro
      # (mod 0) — `CharacterRules::ABILITY_SCORE_DEFAULT`. Diferente do
      # `payload_builder` que usa o piso do point-buy (8) quando o jogador
      # não definiu ainda no draft: aqui já é o estado final/persistido.
      ability_default = CharacterRules::ABILITY_SCORE_DEFAULT
      attrs = (race['attributes'] || race[:attributes] || {})
      base_str = (attrs['str'] || attrs[:str] || ability_default).to_i
      base_dex = (attrs['dex'] || attrs[:dex] || ability_default).to_i
      base_con = (attrs['con'] || attrs[:con] || ability_default).to_i
      base_int = (attrs['int'] || attrs[:int] || ability_default).to_i
      base_wis = (attrs['wis'] || attrs[:wis] || ability_default).to_i
      base_cha = (attrs['cha'] || attrs[:cha] || ability_default).to_i

      # Point-buy (sem racial) para summary/ASI — quando o front envia baseAttributes + abilityBonuses
      pb = race['baseAttributes'] || race[:base_attributes] || {}
      pb_hash = pb.is_a?(Hash) && pb.keys.any?
      meta_base_str = pb_hash ? (pb['str'] || pb[:str] || ability_default).to_i : base_str
      meta_base_dex = pb_hash ? (pb['dex'] || pb[:dex] || ability_default).to_i : base_dex
      meta_base_con = pb_hash ? (pb['con'] || pb[:con] || ability_default).to_i : base_con
      meta_base_int = pb_hash ? (pb['int'] || pb[:int] || ability_default).to_i : base_int
      meta_base_wis = pb_hash ? (pb['wis'] || pb[:wis] || ability_default).to_i : base_wis
      meta_base_cha = pb_hash ? (pb['cha'] || pb[:cha] || ability_default).to_i : base_cha

      race_bonus_raw = race['abilityBonuses'] || race[:abilityBonuses] || {}
      race_bonuses_applied = {}
      if race_bonus_raw.is_a?(Hash) && race_bonus_raw.present?
        %w[str dex con int wis cha].each do |k|
          v = (race_bonus_raw[k] || race_bonus_raw[k.to_sym]).to_i
          race_bonuses_applied[k] = v if v != 0
        end
      end

      race_id     = race['raceId']    || race[:raceId]
      sub_race_id = race['subRaceId'] || race[:subRaceId]
      if race_id.blank?
        race_slug = race['ruleId'] || race[:ruleId]
        race_id = Race.find_by(api_index: race_slug)&.id if race_slug.present?
      end
      if sub_race_id.blank?
        sub_slug = race['subRuleId'] || race[:subRuleId]
        sub_race_id = SubRace.find_by(api_index: sub_slug)&.id if sub_slug.present?
      end
      ensure_playable_race_allowed!(race_id: race_id, sub_race_id: sub_race_id, wizard: wizard)

      klass_id    = klass['klassId']  || klass[:klassId]
      if klass_id.blank?
        klass_slug = klass['klassRuleSlug'] || klass[:klassRuleSlug]
        klass_id = Klass.find_by(api_index: klass_slug)&.id if klass_slug.present?
      end
      level       = (klass['level']   || klass[:level] || 1).to_i
      subclass_id = klass['classSubclassId'] || klass[:classSubclassId]
      ensure_playable_klass_allowed!(klass_id: klass_id, subclass_id: subclass_id, wizard: wizard)
      per_level_raw = klass['classPicksByLevel'] || klass[:classPicksByLevel] || {}
      per_level = begin
        JSON.parse(per_level_raw.to_json)
      rescue
        per_level_raw.respond_to?(:dup) ? per_level_raw.dup : {}
      end
      # Merge class skill picks into level-1 row (frontend sends classSkillPicks separately)
      class_skills_pick = klass['classSkillPicks'] || klass[:classSkillPicks]
      if class_skills_pick.present?
        row1 = (per_level['1'] || per_level[1] || {}).is_a?(Hash) ? (per_level['1'] || per_level[1] || {}).dup : {}
        existing = Array(row1['skills'] || row1[:skills])
        merged = (existing + Array(class_skills_pick)).map(&:to_s).uniq
        row1 = row1.merge('skills' => merged)
        per_level['1'] = row1
      end

      # Build metadata (minimal skeleton)
      # base_ability_scores: valores do wizard (point-buy + racial já aplicados no payload).
      # Usado por CharacterSheetSummaryService ao sincronizar colunas para não somar ASIs/feats em cima de totais já persistidos.
      metadata = {
        race_choices: race['raceChoices'] || race[:raceChoices] || {},
        background: bg['backgroundName'] || bg[:backgroundName],
        background_key: bg['backgroundKey'] || bg[:backgroundKey],
        background_proficiencies: bg['backgroundProfs'] || bg[:backgroundProfs] || [],
        alignment: (meta['alignmentKey'] || meta[:alignmentKey]) ? { index: (meta['alignmentKey'] || meta[:alignmentKey]) } : nil,
        current_level: level,
        'base_ability_scores' => {
          'str' => meta_base_str, 'dex' => meta_base_dex, 'con' => meta_base_con,
          'int' => meta_base_int, 'wis' => meta_base_wis, 'cha' => meta_base_cha
        },
        class_choices: {
          per_level: per_level
        }
      }.compact
      metadata['race_bonuses_applied'] = race_bonuses_applied if race_bonuses_applied.present?
      merge_wizard_general_into_metadata!(metadata, wizard)

      # Upsert or create Sheet
      sheet = char.sheet || Sheet.new(character: char)
      # Compute conservative hp for level 1; LevelUpService will add more later.
      # Inclui +1 PV do 1º nível para traços como Robustez Anã (grants.hp_per_level em RaceRules).
      begin
        k = Klass.find(klass_id)
        # Hit die fallback (`DEFAULT_HIT_DIE` = 8) cobre o caso de uma classe
        # nova/legada ainda sem `hit_die` populado no DB. d8 é a mediana das
        # 12 classes do PHB (Bardo/Clérigo/Druida/Ladino/Monge/Patrulheiro).
        hd = k.hit_die.to_i.nonzero? || CharacterRules::DEFAULT_HIT_DIE
        con_mod = CharacterRules.modifier(base_con)
        row1_hp = begin
          r1 = per_level['1'] || per_level[1] || {}
          r1.is_a?(Hash) ? (r1['hp'] || r1[:hp]) : nil
        end
        init_hp = if row1_hp.is_a?(Hash)
                    SheetHpFromProgression.hp_gain_for_level_row(row1_hp, hd, con_mod)
                  else
                    [1, hd + con_mod].max
                  end
        r_prov = race_id.present? ? Race.find_by(id: race_id) : nil
        s_prov = sub_race_id.present? ? SubRace.find_by(id: sub_race_id) : nil
        rp = RacialHpBonus.per_level_from_race_records(
          r_prov, s_prov, race['raceChoices'] || race[:raceChoices] || {},
        )
        init_hp += rp if r_prov.present? && rp.positive?
      rescue StandardError => e
        Rails.logger.warn("[CharacterProvisioningService] init_hp: #{e.class}: #{e.message}")
        init_hp = CharacterRules::DEFAULT_HIT_DIE + CharacterRules.modifier(base_con)
      end
      # Resolver background_id a partir do api_index (backgroundKey)
      bg_key = bg['backgroundKey'] || bg[:backgroundKey]
      background_id = nil
      if bg_key.present?
        begin
          bg_record = Background.find_by(api_index: bg_key)
          background_id = bg_record&.id
        rescue => _e
          # Continuar sem background_id se não encontrar
        end
      end

      # Resolver alignment_id a partir do api_index (alignmentKey)
      alignment_key = meta['alignmentKey'] || meta[:alignmentKey]
      alignment_id = nil
      if alignment_key.present?
        begin
          alignment_record = Alignment.find_by(api_index: alignment_key)
          alignment_id = alignment_record&.id
        rescue => _e
          # Continuar sem alignment_id se não encontrar
        end
      end

      # JSONB summaries for list endpoint / frontend stub (race_id alone does not expose names in as_json)
      race_obj = race_id.present? ? Race.find_by(id: race_id) : nil
      sub_race_obj = sub_race_id.present? ? SubRace.find_by(id: sub_race_id) : nil
      race_sum = {}
      if race_obj
        # RaceRules.apply é a fonte canónica de speed/idiomas/proficiências da raça (incl. sub-raça):
        # mover para antes da montagem para podermos usar applied[:speed] e applied[:proficiencies].
        applied = nil
        begin
          rc = race['raceChoices'] || race[:raceChoices] || {}
          extra_langs = Array(rc['chosenLanguages'] || rc[:chosenLanguages]).flatten.compact.map(&:to_s)
          rid = race_obj.api_index.presence || race_obj.name.to_s.parameterize(separator: '_')
          sid = sub_race_obj&.api_index&.presence || sub_race_obj&.name&.to_s&.parameterize(separator: '_')
          applied = RaceRules.apply(
            race_id: rid,
            subrace_id: sid,
            choices: { extraLanguages: extra_langs }
          )
        rescue StandardError => e
          Rails.logger.warn("[CharacterProvisioningService] race_rules apply: #{e.class}: #{e.message}")
        end

        # Speed: preferir applied[:speed] (sub-raça pode sobrescrever — ex.: Wood Elf 35 ft).
        # Fallback: coluna na DB (não existe hoje), depois 30.
        applied_speed = applied.is_a?(Hash) ? applied[:speed].to_i : 0
        speed_ft = if applied_speed > 0
                     applied_speed
                   elsif race_obj.respond_to?(:speed_ft) && race_obj.speed_ft.present?
                     race_obj.speed_ft.to_i
                   else
                     30
                   end

        race_sum = {
          'name' => race_obj.name,
          'race_name' => race_obj.name,
          'speed_ft' => speed_ft
        }
        race_sum['sub_race_name'] = sub_race_obj.name if sub_race_obj

        # Darkvision: YAML expressa como Hash `{range: 60}` (formato canônico).
        # Sem `RaceRules.normalize_range`, fazer `.to_i` direto em Hash retorna 0
        # e a guarda `> 0` silencia tudo — race_summary ficava sem darkvision
        # na criação para 8 raças. Cobertura: race_creation_*_bdd_spec.rb.
        if applied.is_a?(Hash)
          dv_val = RaceRules.normalize_range(applied[:darkvision])
          race_sum['darkvision'] = dv_val if dv_val.positive?
        end
        begin
          trait_records = race_obj.base_traits.to_a
          trait_records += sub_race_obj.traits.to_a if sub_race_obj
          trait_records.uniq!(&:id)
          if trait_records.any?
            race_sum['traits'] = trait_records.map { |t| { 'name' => t.name, 'description' => t.description.to_s } }
          end
        rescue => _e
          # non-critical — traits may not be available
        end
        # Idiomas e proficiências da raça (lidas pelo CharacterSheetSummaryService#build_proficiencies):
        # persistir em race_summary para que o front receba `proficiencies.skills.race`.
        if applied.is_a?(Hash)
          langs = applied[:languages]
          race_sum['languages'] = langs.map(&:to_s) if langs.present?
          profs = applied[:proficiencies]
          if profs.is_a?(Hash) && profs.any?
            profs = profs.deep_stringify_keys
            # Resolver pick(s) do usuário em `proficiencies.tools.fixed` para uniformizar
            # com o formato de `weapons`/`armor` (arrays planos). Mantém `choices`/`choiceCount`
            # para auditoria. Resolve casos como Anão escolhendo "Ferramentas de ferreiro".
            chosen_tools = Array(rc['chosenTools'] || rc[:chosenTools])
                             .map { |t| t.is_a?(Hash) ? (t['name'] || t[:name] || t['id'] || t[:id]) : t }
                             .map(&:to_s).reject { |s| s.strip == '' }
            if chosen_tools.any?
              tb = profs['tools']
              if tb.is_a?(Hash)
                fixed_now = Array(tb['fixed']).map(&:to_s)
                tb['fixed'] = (fixed_now + chosen_tools).uniq
                profs['tools'] = tb
              else
                profs['tools'] = { 'fixed' => (Array(tb).map(&:to_s) + chosen_tools).uniq }
              end
            end
            race_sum['proficiencies'] = profs
          end
        end
      end
      bg_obj = background_id.present? ? Background.find_by(id: background_id) : nil
      bg_sum = bg_obj ? { 'name' => bg_obj.name } : {}

      # Antes de persistir metadata nova: se a ficha já existia com outra classe,
      # remove stack antiga para não mesclar class_choices / resumos da classe anterior.
      if klass_id.present? && sheet.persisted?
        begin
          k_reset = Klass.find(klass_id)
          reset_stale_class_for_sheet!(sheet: sheet, character: char, new_klass: k_reset)
          sheet.reload
        rescue ActiveRecord::RecordNotFound
          # klass_id inválido — segue fluxo normal
        end
      end

      # Reprovisionar com a mesma classe já no nível alvo: não resetar PV para o de nível 1,
      # senão hp_max fica só init_hp e LevelUpService não roda (level > sk.level é falso).
      skip_hp_reset = false
      if klass_id.present? && sheet.persisted?
        begin
          k_chk = Klass.find(klass_id)
          existing_sk = sheet.sheet_klasses.find_by(klass_id: k_chk.id)
          skip_hp_reset = existing_sk.present? && existing_sk.level.to_i == level.to_i && level.to_i > 1
        rescue StandardError
          skip_hp_reset = false
        end
      end

      sheet.assign_attributes(
        {
          race_id: race_id,
          sub_race_id: sub_race_id,
          background_id: background_id,
          alignment_id: alignment_id,
          current_level: level,
          str: base_str, dex: base_dex, con: base_con, int: base_int, wis: base_wis, cha: base_cha,
          race_summary: race_sum.presence || sheet.race_summary || {},
          background_summary: bg_sum.presence || sheet.background_summary || {},
          metadata: (sheet.metadata || {}).merge(metadata),
          avatar_customization: (avatar_cust.presence || sheet.avatar_customization.presence || {})
        }.merge(
          if skip_hp_reset
            {}
          else
            {
              hp_max: init_hp,
              hp_current: (sheet.hp_current.to_i > 0 ? [sheet.hp_current.to_i, init_hp].min : init_hp),
              temp_hp: 0
            }
          end
        )
      )
      sheet.save!
      sheet.reload if klass_id.present?

      # Create class at level 1, then level up remaining levels via service
      if klass_id.present?
        k = Klass.find(klass_id)
        raise StandardError, 'Ficha sem id após save; não é possível criar SheetKlass' if sheet.id.blank?

        sk = sheet.sheet_klasses.find_by(klass_id: k.id)
        unless sk
          # Resolve a subclasse, mas só anexa se o threshold da classe permitir no nível 1
          # (Bruxo/Feiticeiro têm subclass_level=1; Druida/Guerreiro etc. somente a partir de
          # 2/3). Anexar antes do threshold dispara `subclass_only_after_threshold` e quebra
          # a criação inteira — o LevelUpService aplica a subclasse no nível certo via
          # `meta.class_choices.subclass_id`.
          resolved_sub_id = resolve_subclass_id(subclass_id, klass_record: k, sheet_id: sheet.id)
          subclass_threshold = k.try(:subclass_level).to_i
          eligible_at_l1 = subclass_threshold <= 1
          sub_id = eligible_at_l1 ? resolved_sub_id : nil
          sk = sheet.sheet_klasses.create!(
            sheet_id: sheet.id,
            klass_id: k.id,
            sub_klass_id: sub_id,
            level: 1
          )
          FeatureGrantService.call(sheet: sheet, klass: k, from_level: 0, to_level: 1)
        end

        # Reprovision do mesmo personagem deve refletir o draft atual (replace),
        # não acumular picks antigos de magia. Limpamos apenas rows de origem de
        # classe (inclui legado `source=nil`) e preservamos grants externos.
        reset_current_class_spell_state!(sheet: sheet, klass_id: k.id)

        # Backfill defensivo: se o SheetKlass já existia mas está sem subclasse e tanto o nível
        # ATUAL do sk quanto o nível alvo já passaram do threshold, tenta resolver agora a partir
        # do payload (causa principal do bug "Colégio Bárdico vazio" em provisionamentos repetidos).
        # Atenção: precisa checar `sk.level >= subclass_level` também — se o sk acabou de ser
        # criado em level=1 e o threshold é 2 (Druida etc.), o LevelUpService cuida disso ao subir.
        # Sem essa guarda dispara `subclass_only_after_threshold` e estoura toda a criação.
        if sk.sub_klass_id.nil? && subclass_id.present? &&
           k.subclass_level.to_i.positive? &&
           level >= k.subclass_level.to_i &&
           sk.level.to_i >= k.subclass_level.to_i
          if (resolved = resolve_subclass_id(subclass_id, klass_record: k, sheet_id: sheet.id))
            sk.update!(sub_klass_id: resolved)
            Rails.logger.info "CharacterProvisioningService: backfill sub_klass_id=#{resolved} em sheet=#{sheet.id} sk=#{sk.id}"
          end
        end

        # Antes do LevelUpService: materializar cantrips/magias conhecidas do metadata para SheetKnownSpell.
        # Caso contrário LevelUpGuard exige truques no nível 1 e o level-up falha silenciosamente (HP só de L1).
        persist_aggregated_known_spells!(sheet)

        # Guard roda com sk.level ainda em 1 *antes* do primeiro incremento; classes
        # com spells_known/cantrips_known em L1 precisam de SheetKnownSpell já persistidos.
        LevelUpService.seed_level_one_known_spells!(sheet_id: sheet.id, klass_id: k.id)

        if level > sk.level.to_i
          delta = level - sk.level.to_i
          con_mod = CharacterRules.modifier(sheet.con)
          hp_rolls = []
          start_lv = sk.level.to_i + 1
          (start_lv..level).each do |lv|
            row = per_level[lv.to_s] || per_level[lv] || {}
            h = row['hp'] || row[:hp]
            next unless h.is_a?(Hash)
            dr = h['dieResult'] || h[:dieResult] || h['die_result'] || h[:die_result]
            if dr.present?
              hp_rolls << dr.to_i
            elsif (h['total'] || h[:total]).present?
              tot = (h['total'] || h[:total]).to_i
              hp_rolls << [tot - con_mod, 1].max
            end
          end
          lu_result = LevelUpService.call(
            sheet_id: sheet.id,
            klass_id: k.id,
            levels: delta,
            sub_klass_id: subclass_id,
            hp_rolls: (hp_rolls.size == delta ? hp_rolls : nil),
            allow_spell_auto_fill: true # import: completa a cota (determinístico) p/ passar o guard
          )
          unless lu_result&.success?
            msg = lu_result&.errors&.full_messages&.join('; ') || 'LevelUpService falhou'
            Rails.logger.error "CharacterProvisioningService: #{msg}"
            raise StandardError, msg
          end
        end

        sheet.reload
        sk_after = sheet.sheet_klasses.find_by(klass_id: k.id)
        reconcile_sheet_hp_if_stuck_at_level_one!(sheet, k, sk_after, level, per_level) if sk_after
        persist_class_summary_proficiencies!(sheet, k, sk_after, level, per_level, klass)
      end

      # Magias raciais precisam de um sheet_klass (primary_sk); roda após definir a classe.
      begin
        if race_id.present?
          race_choices = race['raceChoices'] || race[:raceChoices] || {}

          race_api_index = race['ruleId'] || race[:ruleId]
          subrace_api_index = race['subRuleId'] || race[:subRuleId]

          if race_api_index.blank?
            begin
              if race_id.to_s =~ /^\d+$/
                race_record = Race.find_by(id: race_id)
                race_api_index = race_record&.api_index
              end
              race_api_index ||= race_id
            rescue => _e
              race_api_index = race_id
            end
          end

          if subrace_api_index.blank? && sub_race_id.present?
            begin
              if sub_race_id.to_s =~ /^\d+$/
                subrace_record = SubRace.find_by(id: sub_race_id)
                subrace_api_index = subrace_record&.api_index
              end
              subrace_api_index ||= sub_race_id
            rescue => _e
              subrace_api_index = sub_race_id
            end
          end

          race_rule = RaceRules.apply(
            race_id: race_api_index,
            subrace_id: subrace_api_index,
            choices: race_choices
          )
          RacialSpellsService.call(
            sheet: sheet,
            race_rule: race_rule,
            character_level: level
          )
        end
      rescue => e
        Rails.logger.warn "CharacterProvisioningService: Failed to apply racial spells: #{e.message}"
        Rails.logger.warn e.backtrace.first(3).join("\n")
      end

      # Apply Background selection (metadata + equipment items)
      begin
        bg_key = bg['backgroundKey'] || bg[:backgroundKey]
        bg_choices = bg['backgroundChoices'] || bg[:backgroundChoices] || {}
        if bg_key.present?
          BackgroundAssignmentService.call(sheet: sheet, key: bg_key, choices: bg_choices)
          # Materialize background equipment — IDEMPOTENTE via `provisioning_run_id`.
          # Antes do fix v1: cada Concluir Edição re-rodava `insert_all` cego e
          # duplicava/triplicava itens na bolsa.
          # Antes do fix v2 (este): a guarda `existing_count.zero?` resolvia
          # duplicatas mas não tolerava troca de antecedente nem reset manual.
          # Agora reprovisionamos sempre, mas só substituímos itens que CARREGAM
          # `props_json['provisioning_run_id']` (manuais ficam intocados) e
          # preservamos `equipped`/`slot`/`notes` por (item_index, item_name).
          begin
            summary = BackgroundRules.apply(key: bg_key, choices: bg_choices.symbolize_keys) rescue nil
            equipment_rows = Array(summary && summary[:equipment])
            slugs = equipment_rows.map do |nm|
              name = nm.is_a?(Hash) ? (nm[:name] || nm['name']) : nm
              next if name.blank?
              EquipmentCatalog.normalize_index(name) rescue nil
            end.compact.uniq
            items_by_slug = slugs.any? ? Item.where(api_index: slugs).index_by(&:api_index) : {}
            now = Time.current

            coin_delta = Sheet::COIN_DEFAULTS.dup
            reprovision_items!(sheet: sheet, source: 'background') do
              equipment_rows.filter_map do |nm|
                name = nm.is_a?(Hash) ? (nm[:name] || nm['name']) : nm
                next if name.blank?

                # Itens como "Uma algibeira contendo 15 po" viram moedas, nao SheetItem.
                if AlgibeiraCoinParser.pouch_coin_item?(name)
                  w = AlgibeiraCoinParser.parse_pouch_wallet(name)
                  Sheet::COIN_KEYS.each { |k| coin_delta[k] += w[k].to_i }
                  next nil
                end

                slug = EquipmentCatalog.normalize_index(name) rescue nil
                item_record = slug.present? ? items_by_slug[slug] : nil
                {
                  sheet_id: sheet.id,
                  item_index: item_record&.api_index,
                  item_name: item_record&.name || name.to_s,
                  category: 'background',
                  quantity: 1,
                  equipped: false,
                  slot: nil,
                  source: 'background',
                  props_json: item_record&.props.presence || {},
                  notes: nil,
                  created_at: now,
                  updated_at: now
                }
              end
            end
            sheet.apply_coin_delta!(coin_delta) if Sheet::COIN_KEYS.any? { |k| coin_delta[k].to_i > 0 }
          rescue => e
            Rails.logger.warn "CharacterProvisioningService: background equipment materialization failed: #{e.class} — #{e.message}"
          end
        end
      rescue => e
        Rails.logger.warn "CharacterProvisioningService: background apply failed: #{e.class} — #{e.message}"
      end

      # Apply Feats from race (Human Variant) and per-level ASIs with mode 'feat'
      begin
        cleanup_non_feat_asi_levels!(sheet: sheet, per_level: per_level, max_level: level)

        # Human Variant feat
        rc = race['raceChoices'] || race[:raceChoices] || {}
        hv = rc['variantHumanASI'] || rc[:variantHumanASI]
        if hv.is_a?(Hash) && (hv['mode'] || hv[:mode]) == 'feat'
          feat_id = hv['featId'] || hv[:featId] || hv['featName'] || hv[:featName]
          if feat_id.present?
            raw = hv['choices'] || hv[:choices] || {}
            choices = raw.is_a?(ActionController::Parameters) ? raw.to_unsafe_h : raw.dup
            # normalize some fields like frontend does
            begin
              if choices['ability'] || choices[:ability]
                v = (choices['ability'] || choices[:ability]).to_s.downcase
                choices['ability'] = v
              end
              if choices['saving_throws'] || choices[:saving_throws]
                v = (choices['saving_throws'] || choices[:saving_throws]).to_s.downcase
                choices['saving_throws'] = v
              end
              # ensure arrays of names for cantrips/spells if objects were sent
              %w[cantrips spells maneuvers manobras].each do |key|
                val = choices[key] || choices[key.to_sym]
                next unless val
                arr = Array(val).map { |x| x.is_a?(Hash) ? (x['name'] || x[:name] || x['id'] || x[:id]) : x }.compact
                choices[key] = arr
              end
            rescue => _e
            end
            FeatAssignmentService.call(sheet: sheet, feat_id: feat_id, level_gained: 1, choices: choices)
          end
        end

        # Per-level ASI feats
        (1..level).each do |lv|
          row = per_level[lv.to_s] || per_level[lv] || {}
          asi = row['asi'] || row[:asi]
          next unless asi.is_a?(Hash)
          mode = asi['mode'] || asi[:mode]
          next unless mode.to_s == 'feat'
          feat_id = asi['featId'] || asi[:featId] || asi['featName'] || asi[:featName]
          next unless feat_id.present?
          choices = asi['choices'] || asi[:choices] || {}
          FeatAssignmentService.call(sheet: sheet, feat_id: feat_id, level_gained: lv, choices: choices)
        end
      rescue => _e
        # do not fail entire provision for feat apply issues
      end

      # Aggregate spells once to reuse for known and prepared sets
      agg = begin
        KnownSpellsAggregator.new(sheet).call
      rescue => _e
        { known_by_level: {}, prepared_by_level: {} }
      end

      # Persist known spells from metadata (all levels) with batch insert
      begin
        primary_sk = sheet.sheet_klasses.order(level: :desc, id: :asc).first
        if primary_sk
          present_known = SheetKnownSpell.where(sheet_klass_id: primary_sk.id).pluck(:spell_id).map(&:to_i).to_set
          rows = []
          (agg[:known_by_level] || {}).each_value do |arr|
            Array(arr).each do |sp|
              sid = sp[:id].to_i
              next if sid <= 0
              next if present_known.include?(sid)
              present_known.add(sid)
              rows << { sheet_klass_id: primary_sk.id, spell_id: sid, source: 'class', created_at: Time.current, updated_at: Time.current }
            end
          end
          SheetKnownSpell.insert_all(rows) if rows.any?
        end
      rescue => _e
      end

      # Auto-prepared spells from class/subclass and terrain (Druid Circle) — batch insert
      begin
        present_prep = SheetPreparedSpell.where(sheet_id: sheet.id).pluck(:spell_id).map(&:to_i).to_set
        rows = []
        (agg[:prepared_by_level] || {}).each_value do |arr|
          Array(arr).each do |sp|
            sid = sp[:id].to_i
            next if sid <= 0
            next if present_prep.include?(sid)
            present_prep.add(sid)
            rows << { sheet_id: sheet.id, spell_id: sid, auto: true, source: 'class', created_at: Time.current, updated_at: Time.current }
          end
        end
        SheetPreparedSpell.insert_all(rows) if rows.any?
      rescue => _e
      end

      # Persist user-chosen prepared spells (non-auto) from per_level within limit — batch insert
      begin
        primary_sk = sheet.sheet_klasses.order(level: :desc, id: :asc).first
        if primary_sk
          klass = primary_sk.klass
          prepared_mode = begin
            rules = ClassRules.find(klass.api_index) || {}
            (rules.dig(:feature_rules, :spellcasting, :mode) || rules.dig(:spellcasting, :preparation)).to_s == 'prepared'
          rescue
            false
          end
          if prepared_mode
            limit = SpellRules.prepared_limit_for(sheet, klass).to_i rescue nil
            present = SheetPreparedSpell.where(sheet_id: sheet.id).pluck(:spell_id).map(&:to_i).to_set
            non_auto_count = SheetPreparedSpell.where(sheet_id: sheet.id, auto: false).count
            rows = []
            resolve_prep_spell_id = lambda do |entry|
              raw_id = entry.is_a?(Hash) ? (entry['id'] || entry[:id]) : entry
              nm = entry.is_a?(Hash) ? (entry['name'] || entry[:name]) : nil
              sid = raw_id.to_i
              if sid > 0
                sid
              elsif nm.present?
                sp = Spell.find_by(name: nm) || Spell.where('LOWER(name) = ?', nm.to_s.downcase).first
                sp&.id.to_i
              elsif raw_id.present?
                sp = Spell.find_by(api_index: raw_id.to_s)
                sp&.id.to_i
              else
                0
              end
            end

            (1..level).each do |lv|
              row = per_level[lv.to_s] || per_level[lv] || {}
              Array(row['prepared'] || row[:prepared]).each do |entry|
                sid = resolve_prep_spell_id.call(entry)
                next if sid <= 0
                next if present.include?(sid)
                if limit && non_auto_count >= limit
                  next
                end
                present.add(sid)
                non_auto_count += 1
                rows << { sheet_id: sheet.id, spell_id: sid, auto: false, source: 'class', created_at: Time.current, updated_at: Time.current }
              end
            end
            SheetPreparedSpell.insert_all(rows) if rows.any?
          end
        end
      rescue => _e
      end

      # Persist equipment picks from wizard — IDEMPOTENTE via `provisioning_run_id`.
      # Mesma justificativa do bloco 'background' (ver `reprovision_items!`):
      # tolera troca de classe e reset manual, preserva equipped/slot/notes.
      # Para mudar equipamento depois é via os endpoints `/sheet_items`
      # (CRUD do inventário ao vivo) — esses items NUNCA carregam o run_id,
      # logo nunca são tocados por re-provision.
      begin
        picks = equip['equipmentPicks'] || equip[:equipmentPicks] || []
        now = Time.current

        reprovision_items!(sheet: sheet, source: 'class') do
          Array(picks).map do |it|
            attrs = it.is_a?(Hash) ? it : {}
            {
              sheet_id: sheet.id,
              item_index: attrs['item_index'] || attrs[:item_index] || attrs['index'] || attrs[:index],
              item_name: (attrs['item_name'] || attrs[:item_name] || attrs['name'] || attrs[:name]).to_s,
              category: attrs['category'] || attrs[:category],
              quantity: (attrs['quantity'] || attrs[:quantity] || 1).to_i,
              equipped: !!(attrs['equipped'] || attrs[:equipped]),
              slot: attrs['slot'] || attrs[:slot],
              source: attrs['source'] || attrs[:source] || 'class',
              props_json: attrs['props'] || attrs[:props] || attrs['props_json'] || attrs[:props_json] || {},
              notes: nil,
              created_at: now,
              updated_at: now
            }
          end
        end
      rescue => e
        Rails.logger.warn "CharacterProvisioningService: class equipment persistence failed: #{e.class} — #{e.message}"
      end

      # Atributos nas colunas da ficha = mesmo resultado que o resumo (inclui ASI/metadata)
      begin
        sheet.reload
        CharacterSheetSummaryService.sync_ability_columns_from_metadata!(sheet)
        finalize_sheet_hp_after_provision!(sheet)
      rescue => e
        Rails.logger.warn "CharacterProvisioningService: ability column sync skipped: #{e.message}"
      end

      # Clear draft data after successful provision
      char.update_columns(draft_data: {}, current_step: nil, status: Character.statuses[:active])

      { character: char }
    end
  rescue StandardError => e
    errors.add(:base, e.message)
    nil
  end

  private

  def ensure_playable_race_allowed!(race_id:, sub_race_id:, wizard:)
    return if allow_non_playable_race?(wizard)

    race_record = race_id.present? ? Race.find_by(id: race_id) : nil
    if race_record.present? && !race_record.playable?
      raise StandardError, 'Raça indisponível para personagens de jogador. Apenas mestres podem usá-la em NPCs.'
    end

    sub_race_record = sub_race_id.present? ? SubRace.find_by(id: sub_race_id) : nil
    return unless sub_race_record.present? && !sub_race_record.playable?

    raise StandardError, 'Sub-raça indisponível para personagens de jogador. Apenas mestres podem usá-la em NPCs.'
  end

  # Espelha `ensure_playable_race_allowed!`: bloqueia jogador de provisionar
  # personagem com Classe/Subclasse marcada como indisponível (`playable=false`).
  # Mestres podem usá-las em NPCs (mesma exceção da raça).
  def ensure_playable_klass_allowed!(klass_id:, subclass_id:, wizard:)
    return if allow_non_playable_race?(wizard)

    klass_record = klass_id.present? ? Klass.find_by(id: klass_id) : nil
    if klass_record.present? && !klass_record.playable?
      raise StandardError, 'Classe indisponível para personagens de jogador. Apenas mestres podem usá-la em NPCs.'
    end

    return if subclass_id.blank?

    sub_klass_record =
      SubKlass.find_by(id: subclass_id) ||
      SubKlass.find_by(api_index: subclass_id.to_s)
    return unless sub_klass_record.present? && !sub_klass_record.playable?

    raise StandardError, 'Subclasse indisponível para personagens de jogador. Apenas mestres podem usá-la em NPCs.'
  end

  def allow_non_playable_race?(wizard)
    Group.user_is_dm?(@actor_user) && wizard_npc?(wizard)
  end

  def wizard_npc?(wizard)
    general = wizard['general'] || wizard[:general]
    return false unless general.is_a?(Hash)

    ActiveModel::Type::Boolean.new.cast(general['isNPC'] || general[:isNPC])
  end

  # Alinha com CharacterSheetEdits::GeneralEditService — `sheet.metadata['general']`.
  def merge_wizard_general_into_metadata!(metadata, wizard)
    raw = wizard['general'] || wizard[:general]
    return unless raw.is_a?(Hash) && raw.present?

    gen = {}
    %w[playerName isNPC npcRole npcFaction npcLocation npcStatus dmNotes].each do |k|
      next unless raw.key?(k) || raw.key?(k.to_sym)

      v = raw[k] || raw[k.to_sym]
      if k == 'isNPC'
        gen[k] = ActiveModel::Type::Boolean.new.cast(v)
        next
      end
      next if v.nil?

      gen[k] = v
    end
    metadata['general'] = gen if gen.present?
  end

  # Reprovisão idempotente de itens "automáticos" (source ∈ ['class','background']).
  #
  # Estratégia (substitui o antigo guard `existing_count.zero?`, que era idempotente
  # mas não tolerava troca de classe nem reset manual):
  #   1. Cada lote inserido é etiquetado com `props_json['provisioning_run_id']`.
  #   2. Em re-provision, deletamos APENAS os SheetItems que carregam esse marcador
  #      (preservando itens que o usuário comprou/adicionou via UI, que não têm a key).
  #   3. Antes de deletar, indexamos `equipped`/`slot`/`notes` por `(item_index, item_name)`
  #      para preservar essas customizações no novo lote — o usuário não perde
  #      "Bordão equipado" só porque clicou em Concluir Edição de novo.
  #   4. Inserimos o novo lote já com o run_id em `props_json`, fechando o ciclo.
  #
  # Args:
  #   sheet:   Sheet ativa
  #   source:  'class' ou 'background'
  #   build_rows: Proc que retorna Array<Hash> com as colunas do SheetItem (sem
  #               provisioning_run_id; este helper injeta).
  def reprovision_items!(sheet:, source:, &build_rows)
    run_id = SecureRandom.uuid

    prior_provisioned = SheetItem
                          .where(sheet_id: sheet.id, source: source)
                          .where("props_json ? 'provisioning_run_id'")
                          .to_a
    overrides = prior_provisioned.each_with_object({}) do |it, h|
      h[[it.item_index, it.item_name]] = {
        equipped: it.equipped,
        slot: it.slot,
        notes: it.notes
      }
    end

    # Deleta apenas o lote provisionado (manuais permanecem)
    SheetItem
      .where(sheet_id: sheet.id, source: source)
      .where("props_json ? 'provisioning_run_id'")
      .delete_all

    rows = Array(build_rows.call)
    return 0 if rows.empty?

    enriched = rows.map do |row|
      key = [row[:item_index], row[:item_name]]
      ovr = overrides[key]
      props = (row[:props_json].is_a?(Hash) ? row[:props_json] : {}).merge(
        'provisioning_run_id' => run_id
      )
      row.merge(
        equipped: ovr ? ovr[:equipped] : row[:equipped],
        slot:     ovr&.dig(:slot) || row[:slot],
        notes:    ovr&.dig(:notes) || row[:notes],
        props_json: props
      )
    end

    SheetItem.insert_all(enriched)
    Rails.logger.info(
      "CharacterProvisioningService: reprovisioned #{enriched.size} '#{source}' items " \
      "for sheet #{sheet.id} (run=#{run_id}, prior=#{prior_provisioned.size}, " \
      "preserved=#{overrides.size})"
    )
    enriched.size
  end

  # Resolve uma escolha de subclasse vinda do payload (numérica ou slug PT/EN) para um id de
  # SubKlass. Loga warning explícito quando não encontra — antes ficava num rescue silencioso e
  # criava SheetKlass com sub_klass_id NULL (causa do "card de Faculdade vazio" no front).
  # Aliases legados expostos pela API pública que divergem do `api_index` real
  # gravado em `sub_klasses`. Mantidos para não invalidar drafts antigos / payloads
  # já em trânsito quando corrigimos a inconsistência na fonte (ClassRules).
  SUBCLASS_ID_LEGACY_ALIASES = {
    'warlock' => { 'goo' => 'great_old_one' }
  }.freeze

  def resolve_subclass_id(subclass_id, klass_record:, sheet_id: nil)
    return nil if subclass_id.blank?

    sid = subclass_id.to_s
    sub =
      if sid.match?(/\A\d+\z/)
        SubKlass.find_by(id: sid.to_i)
      else
        slug = SubklassSlugResolver.normalize(sid)
        ascii = SubklassSlugResolver.ascii_slug(sid)
        aliased = klass_record ? SUBCLASS_ID_LEGACY_ALIASES.dig(klass_record.api_index, sid.downcase) : nil
        scope = klass_record ? SubKlass.where(klass_id: klass_record.id) : SubKlass.all
        # Tenta nessa ordem: alias legado conhecido, slug normalizado, slug ASCII puro,
        # api_index cru, nome exibido (case-insensitive). Os dois últimos cobrem o caso
        # do front salvar `selectedSubclass` como o NOME PT-BR exibido no wizard
        # (ex.: "Círculo da Vida"), e o api_index no overrides é "circulo-vida".
        (aliased && scope.find_by(api_index: aliased)) ||
          scope.find_by(api_index: slug) ||
          scope.find_by(api_index: ascii) ||
          scope.find_by(api_index: sid) ||
          scope.where('LOWER(name) = ?', sid.downcase).first
      end

    if sub.nil?
      Rails.logger.warn(
        "CharacterProvisioningService: subclasse '#{subclass_id.inspect}' (klass=#{klass_record&.api_index}, sheet=#{sheet_id}) " \
          'não resolveu para nenhum SubKlass — provisionando sem subclasse. Verifique o STATIC mapping no front ou rode dnd:audit_missing_subclass.'
      )
      return nil
    end

    if klass_record && sub.klass_id != klass_record.id
      Rails.logger.warn(
        "CharacterProvisioningService: SubKlass id=#{sub.id} (api_index=#{sub.api_index}) pertence a klass_id=#{sub.klass_id} " \
          "mas o personagem é klass_id=#{klass_record.id} (#{klass_record.api_index}) — ignorando."
      )
      return nil
    end

    sub.id
  rescue StandardError => e
    Rails.logger.warn("CharacterProvisioningService: erro resolvendo subclasse #{subclass_id.inspect}: #{e.class}: #{e.message}")
    nil
  end

  # Corrige fichas antigas: nível de classe já = nível do personagem, mas hp_max ainda só o do 1º nível.
  # Operações: após deploy, reprovisionar o personagem; log: "reconciled hp_max X -> Y (sheet Z)".
  def reconcile_sheet_hp_if_stuck_at_level_one!(sheet, klass, sk, character_level, per_level)
    return unless sk && sk.level.to_i == character_level.to_i && character_level.to_i > 1

    floor = SheetHpFromProgression.level_one_floor(sheet, klass)
    return unless sheet.hp_max.to_i <= floor

    expected = SheetHpFromProgression.expected_max(sheet, klass, character_level, per_level)
    return if expected <= sheet.hp_max.to_i

    prev_max = sheet.hp_max.to_i
    new_max = expected
    cur = sheet.hp_current.to_i
    # DB default 0 or "full at wrong max" should become full at new max; otherwise cap at new max
    new_current = if cur <= 0 || cur == prev_max
                    new_max
                  else
                    [cur, new_max].min
                  end
    sheet.update!(hp_max: new_max, hp_current: new_current)
    Rails.logger.info "CharacterProvisioningService: reconciled hp_max #{prev_max} -> #{new_max} (sheet #{sheet.id})"
  rescue StandardError => e
    Rails.logger.warn "CharacterProvisioningService: HP reconcile failed: #{e.message}"
  end

  # Garante hp_max/hp_current = soma canónica de `per_level` + racial após todo o pipeline
  # (corrige drift quando LevelUpService não somou Robustez Anã por slug PT na sub-raça, etc.).
  def finalize_sheet_hp_after_provision!(sheet)
    sk = sheet.sheet_klasses.order(level: :desc).first
    return unless sk&.klass

    character_level = sheet.sheet_klasses.sum(&:level).to_i
    character_level = sk.level.to_i if character_level <= 0
    per_level = (sheet.metadata || {}).dig('class_choices', 'per_level') || {}
    expected = SheetHpFromProgression.expected_max(sheet, sk.klass, character_level, per_level)
    return if expected <= 0
    return if sheet.hp_max.to_i == expected

    prev_max = sheet.hp_max.to_i
    cur = sheet.hp_current.to_i
    new_cur = if prev_max <= 0 || cur <= 0 || cur == prev_max
                expected
              else
                [(expected * (cur.to_f / [prev_max, 1].max)).round, expected].min
              end
    sheet.update!(hp_max: expected, hp_current: new_cur)
    Rails.logger.info "CharacterProvisioningService: finalized hp_max #{prev_max} -> #{expected} (sheet #{sheet.id})"
  rescue StandardError => e
    Rails.logger.warn "CharacterProvisioningService: HP finalize failed: #{e.message}"
  end

  # Preenche armor/weapon/tool/skills em class_summary delegando ao ClassSummaryRebuilder
  # (mesma fonte usada pelos SheetEditServices e pela rake `sheets:rebuild_class_summary`).
  def persist_class_summary_proficiencies!(sheet, klass_record, sheet_klass, character_level, per_level, wizard_klass)
    unless klass_record
      Rails.logger.warn("CharacterProvisioningService: persist_class_summary_proficiencies skipped sheet=#{sheet.id} (no klass_record)")
      return
    end

    # Hidrata per_level['1'].instruments a partir do wizard_klass (ainda nao
    # persistido pelo ClassStepService) ANTES do rebuilder ler a fonte canonica.
    wiz = wizard_klass.is_a?(Hash) ? wizard_klass.stringify_keys : {}
    wizard_instruments = Array(wiz['instrumentsSelected'] || wiz['instruments_selected'] || wiz['instruments'])

    if wizard_instruments.any?
      meta = (sheet.metadata || {}).deep_stringify_keys
      meta['class_choices'] ||= {}
      meta['class_choices']['per_level'] ||= {}
      row1 = (meta['class_choices']['per_level']['1'] || {}).deep_dup
      existing = Array(row1['instruments'])
      if existing.empty?
        row1['instruments'] = wizard_instruments
        meta['class_choices']['per_level']['1'] = row1
        sheet.update_columns(metadata: meta)
        sheet.reload
      end
    end

    ClassSummaryRebuilder.call(sheet, wizard_klass: wizard_klass)
  end

  def flatten_tool_proficiencies_for_summary(tool_profs)
    out = []
    Array(tool_profs).each do |t|
      case t
      when String
        out << t.to_s.strip if t.present?
      when Hash
        h = t.stringify_keys
        ins = h['instruments']
        if ins.is_a?(Array)
          ins.each do |x|
            out << (x.is_a?(Hash) ? (x.stringify_keys['name'] || x.stringify_keys['id']) : x).to_s.strip
          end
        end
      end
    end
    out.compact.map(&:strip).reject(&:blank?).uniq
  end

  def persist_aggregated_known_spells!(sheet)
    sheet.reload
    agg = begin
      KnownSpellsAggregator.new(sheet).call
    rescue StandardError => _e
      { known_by_level: {}, prepared_by_level: {} }
    end
    primary_sk = sheet.sheet_klasses.order(level: :desc, id: :asc).first
    return unless primary_sk

    present_known = SheetKnownSpell.where(sheet_klass_id: primary_sk.id).pluck(:spell_id).map(&:to_i).to_set
    rows = []
    (agg[:known_by_level] || {}).each_value do |arr|
      Array(arr).each do |sp|
        sid = sp[:id].to_i
        next if sid <= 0
        next if present_known.include?(sid)
        present_known.add(sid)
        rows << { sheet_klass_id: primary_sk.id, spell_id: sid, source: 'class', created_at: Time.current, updated_at: Time.current }
      end
    end
    SheetKnownSpell.insert_all(rows) if rows.any?
  end

  # Replace semantics para magia de classe em reprovision:
  # remove picks antigos de classe e re-materializa a partir do payload atual.
  # Mantém intactos grants de feat/race/background.
  def reset_current_class_spell_state!(sheet:, klass_id:)
    sk = sheet.sheet_klasses.find_by(klass_id: klass_id)
    return unless sk
    # `sheet_prepared_spells` é por sheet (não por klass). Em ficha multiclasse,
    # limpar "source class" globalmente pode apagar picks válidos de outra classe.
    return if sheet.sheet_klasses.where.not(klass_id: klass_id).exists?

    class_sources = [nil, 'class', 'subclass']
    SheetKnownSpell.where(sheet_klass_id: sk.id, source: class_sources).delete_all
    SheetPreparedSpell.where(sheet_id: sheet.id, source: class_sources).delete_all
  end

  def cleanup_non_feat_asi_levels!(sheet:, per_level:, max_level:)
    levels = []
    (1..max_level.to_i).each do |lv|
      row = per_level[lv.to_s] || per_level[lv]
      next unless row.is_a?(Hash)

      asi = row['asi'] || row[:asi]
      next unless asi.is_a?(Hash)

      mode = (asi['mode'] || asi[:mode]).to_s
      feat_id = asi['featId'] || asi[:featId] || asi['featName'] || asi[:featName]
      levels << lv unless mode == 'feat' && feat_id.present?
    end
    SheetFeatLevelCleaner.call(sheet: sheet, levels: levels)
  end

  # Chaves de metadata ligadas à classe que não devem sobreviver a uma troca de classe.
  STALE_CLASS_METADATA_KEYS = %w[
    class_choices class_summary fighting_style skills_selected instruments_selected
  ].freeze

  # Ao reprovisionar com outra classe, o código antigo criava um segundo SheetKlass e somava
  # features/magias. Remove stack de classe anterior e grants ligados a Klass/SubKlass.
  def reset_stale_class_for_sheet!(sheet:, character:, new_klass:)
    return unless sheet.persisted?
    return unless new_klass

    unless sheet.sheet_klasses.exists? && sheet.sheet_klasses.where.not(klass_id: new_klass.id).exists?
      return
    end

    sk_ids = sheet.sheet_klasses.pluck(:id)
    SheetKnownSpell.where(sheet_klass_id: sk_ids).delete_all if sk_ids.any?
    # delete_all na associação sem dependent: nullifica sheet_id (NOT NULL) — usar DELETE direto.
    SheetKlass.where(sheet_id: sheet.id).delete_all
    SheetPreparedSpell.where(sheet_id: sheet.id).delete_all
    CharactersFeature.where(character_id: character.id, source_type: %w[Klass SubKlass]).delete_all

    meta = (sheet.metadata || {}).stringify_keys
    cleaned_meta = meta.except(*STALE_CLASS_METADATA_KEYS)

    sheet.update_columns(
      features_by_level: {},
      class_summary: {},
      class_choices: {},
      metadata: cleaned_meta
    )
  end
end
