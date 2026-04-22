module CharacterSheetEdits
  class ClassEditService < BaseSheetEditService
    def step_key = 'class'

    def read
      sk = sheet.sheet_klasses.order(level: :asc).first
      pl = (sheet.metadata || {}).dig('class_choices', 'per_level', '1') || {}
      {
        'classId'         => sk&.klass_id&.to_s,
        'subclassId'      => sk&.sub_klass_id&.to_s,
        # Nomes/slugs canônicos — fonte da verdade. Front-end não precisa mais
        # bater id vs catálogo (que tinha ids mock `cl-N`/`sub-Nh` divergentes
        # do DB id). Se vier preenchido, sobrescreve `selectedClass`/`selectedSubclass`.
        'klassName'       => sk&.klass&.name,
        'klassRuleSlug'   => sk&.klass&.api_index,
        'subclassName'    => sk&.sub_klass&.name,
        'subclassRuleSlug'=> sk&.sub_klass&.api_index,
        'classSkillPicks' => Array(pl['skills']),
        'level1Choices'   => pl
      }
    end

    protected

    def apply!
      new_class_id = data['classId']
      sk = sheet.sheet_klasses.order(level: :asc).first

      class_changed = false
      resolved_class_id = resolve_klass_id(new_class_id)

      # Gap G4.5 do relatorio de auditoria de steps: detectar multiclass ANTES
      # da limpeza para reportar com precisao quais classes secundarias serao
      # destruidas. Antes do fix, `clear!('sheet_klasses(level>=2)')` era
      # generico e o jogador via "perde nivel 2+" sem saber que tambem perderia
      # `Bardo 2` (multiclass). Agora enumeramos as classes secundarias na
      # mensagem de confirmacao.
      multiclass_secondaries = []
      if sk
        multiclass_secondaries = sheet.sheet_klasses
                                      .where.not(id: sk.id)
                                      .includes(:klass)
                                      .map { |s| "#{s.klass&.name || 'Classe?'} #{s.level}" }
      end

      if new_class_id.present? && resolved_class_id.present? && (sk.nil? || resolved_class_id != sk.klass_id.to_i)
        # Bug B4.2 do relatorio de auditoria de steps: antes deste fix, troca de
        # classe so destruia `sheet_klasses(level>=2)` e fazia merge raso em
        # `class_choices.per_level['1']` — entao escolhas da classe ANTIGA
        # (instrumentos do Bardo, fighting_style do Guerreiro, etc.) ficavam
        # contaminando o `per_level` da nova classe. Solucao: ao trocar de
        # classe, marcamos as chaves derivadas para limpeza (clear! pede
        # confirmacao) e zeramos `per_level` inteiro (so o que vier no MESMO
        # PATCH em `level1Choices`/`classSkillPicks` permanece).
        # Acumulamos as 3 chaves derivadas SEM disparar rollback nas duas
        # primeiras (clear! com confirm=true levanta ActiveRecord::Rollback se
        # nao houver `force`); a ULTIMA chamada eh quem dispara, ja com a lista
        # completa em @cleared. Sem isso, o requires_confirmation vinha so com
        # 'sheet_klasses(level>=2)' e o front nao sabia que metadata.class_*
        # tambem seria destruido.
        class_changed = true
        # Gap G4.5: razao customizada quando ha multiclass para o jogador
        # entender o impacto real (perde Bardo 2 + sheet_items provisionados
        # do Bardo etc.). Mantem o reason generico se nao ha multiclass.
        change_reason = if multiclass_secondaries.any?
          "#{DESTRUCTIVE_REASONS[:class_changed]} ATENCAO: este personagem possui " \
          "as seguintes classes secundarias que serao DESTRUIDAS: " \
          "#{multiclass_secondaries.join(', ')}."
        else
          DESTRUCTIVE_REASONS[:class_changed]
        end
        if multiclass_secondaries.any?
          clear!('sheet_klasses(multiclass)', reason: change_reason, confirm: false)
        end
        clear!('sheet_klasses(level>=2)', reason: change_reason, confirm: false)
        clear!('metadata.class_summary',  reason: change_reason, confirm: false)
        # Gap G8.2 do relatorio de auditoria de steps: ao trocar classe,
        # `metadata.equipment.{mode,choices,generic}` e os itens
        # `SheetItem source='class'` provisionados ficavam stale (pacote
        # inicial do Bardo aparecia como Mago). Como esses items carregam
        # `provisioning_run_id`, podemos deleta-los com seguranca sem mexer
        # em items que o jogador comprou via CRUD live (esses nao tem o
        # marker — ver `EquipmentEditService` B6).
        clear!('metadata.equipment',      reason: DESTRUCTIVE_REASONS[:class_changed], confirm: false)
        clear!('sheet_items(source=class, provisioned)', reason: DESTRUCTIVE_REASONS[:class_changed], confirm: false)
        clear!('metadata.class_choices', reason: change_reason, confirm: true)
        # Preservamos o sheet_klass primario (sk) e destruimos os multiclasses
        # extras. Antes desta correcao, `where("level >= 2")` deletava o
        # proprio sk quando ele estava em level >=2 (caso comum em personagem
        # ja levelado), e o `sk.update!` que vinha em seguida fazia UPDATE com
        # 0 rows — deixando a sheet sem sheet_klass nenhum (ABLAUTH bug
        # silencioso que so aparecia ao recomputar HP).
        # Gap G4.5: agora destruimos TAMBEM as classes secundarias (multiclass)
        # — antes elas escapavam quando o sk primario era nivel 1, deixando o
        # personagem com a classe nova nivel 1 + multiclass antigo intactos
        # (state inconsistente: hd da classe antiga somava no hp_max recompute).
        if sk
          sheet.sheet_klasses.where.not(id: sk.id).destroy_all
          sk.update!(klass_id: resolved_class_id, sub_klass_id: nil, level: 1)
        else
          sheet.sheet_klasses.destroy_all
          sheet.sheet_klasses.create!(klass_id: resolved_class_id, level: 1)
        end
      elsif data.key?('subclassId') && sk
        # Aceita id numérico do DB (`'145'`), api_index do banco (`'arquearia_arcana'`),
        # ruleSlug do catálogo do front (`'arquearia-arcana'`, kebab) OU id mock do
        # catálogo (`'sub-9h'`). Antes do fix, o front mandava `'sub-5'` e
        # `to_i` virava 0, gravando uma FK órfã — a próxima leitura voltava à
        # subclass anterior (causa raiz de "subclasse volta sozinha").
        resolved_sub_id = resolve_sub_klass_id(data['subclassId'], klass_id: sk.klass_id)
        if data['subclassId'].present? && resolved_sub_id.nil?
          warn!("subclassId '#{data['subclassId']}' não resolveu para nenhum SubKlass de klass_id=#{sk.klass_id}; nada alterado")
        else
          sk.update!(sub_klass_id: resolved_sub_id)
        end
      end

      meta = (sheet.metadata || {}).deep_stringify_keys
      if class_changed
        # Reset total: o `per_level` inteiro era da classe antiga; manter
        # qualquer chave (mesmo `skills`) seria contaminacao. As escolhas
        # validas para a nova classe vem em `data['level1Choices']` /
        # `data['classSkillPicks']` no MESMO PATCH (ver B4.1 de simetria).
        meta['class_choices'] = { 'per_level' => {} }
        meta.delete('class_summary')
        # Gap G8.2: zera as preferencias de equipment do wizard (a UI
        # vai re-rodar o picker de pacote inicial da classe nova). Os
        # SheetItems auto-provisionados com `provisioning_run_id` sao
        # apagados a parte; items manuais do jogador ficam intactos.
        meta.delete('equipment')
        SheetItem
          .where(sheet_id: sheet.id, source: 'class')
          .where("props_json ? 'provisioning_run_id'")
          .delete_all
      end
      meta['class_choices'] ||= {}
      meta['class_choices']['per_level'] ||= {}
      row1 = class_changed ? {} : (meta['class_choices']['per_level']['1'] || {}).deep_dup
      row1.merge!(data['level1Choices']) if data['level1Choices'].is_a?(Hash)
      row1['skills'] = Array(data['classSkillPicks']).map(&:to_s).uniq if data.key?('classSkillPicks')
      meta['class_choices']['per_level']['1'] = row1
      sheet.metadata = meta
      sheet.save!

      # Reidempotente: re-deriva class_summary (armor/weapons/tools) toda vez
      # que classe/subclasse/instrumentos mudam.
      ClassSummaryRebuilder.call(sheet)

      # Bug B4.3 do relatorio de auditoria de steps: trocar de classe (d12 -> d6)
      # nao recomputava `hp_max`. recompute_hp_max! usa o `hit_die` da classe
      # ATUAL via `sheet.sheet_klasses.order(level: :desc).first.klass.hit_die`,
      # entao precisamos recarregar a associacao senao ela vem cacheada com a
      # klass anterior.
      if class_changed
        sheet.sheet_klasses.reload
        recompute_hp_max!(new_con: sheet.con.to_i)
        sheet.save!
      end

      # Gap G4.6 do relatorio de auditoria de steps: ClassEditService nao
      # validava se o `level1Choices` enviado era compativel com a nova
      # classe (skill catalog, fighting_style requerido, instrumentos do
      # Bardo, etc.). Resultado: jogador trocava Mago -> Guerreiro sem
      # escolher fighting_style, e ficha entrava em estado invalido (somente
      # capturado num futuro level-up via LevelUpGuardService). Agora rodamos
      # o guard logo apos o save, com semantica identica ao G7.5 do
      # ProgressionEditService:
      #   - So roda quando classe mudou (edit puro de subclass nao precisa)
      #   - `force: true` pula (mesma semantica de destrutividade ja existente)
      #   - Falha do guard popula requires_confirmation E faz rollback
      enforce_level_up_guard!(class_changed: class_changed)
    end

    private

    def enforce_level_up_guard!(class_changed:)
      return unless class_changed
      return if force?

      sk = sheet.sheet_klasses.order(level: :desc).first
      return unless sk&.klass

      guard = LevelUpGuardService.call(sheet: sheet.reload, klass: sk.klass)
      return if guard.success?

      msgs = guard.errors.full_messages
      msgs.each { |m| warn!(m) }
      @requires_confirmation = {
        reason: "Trocar para #{sk.klass.name} requer escolhas obrigatorias " \
                "ainda nao informadas: #{msgs.join('; ')}",
        cleared: @cleared.dup
      }
      raise ActiveRecord::Rollback
    rescue ActiveRecord::Rollback
      raise
    rescue StandardError => e
      # ZE5 do segundo audit: o rescue antigo apenas logava e CONTINUAVA, o que
      # significava que um erro real (NoMethodError, falha de DB, bug no guard)
      # passava despercebido e a troca de classe era commitada. Agora forcamos
      # rollback e re-lancamos para que o controller responda com 500 (trace_id
      # via ZC4). O usuario nao recebe um estado inconsistente em silencio.
      Rails.logger.error "[ClassEditService] LevelUpGuardService raised: #{e.class}: #{e.message}\n#{e.backtrace&.first(10)&.join("\n")}"
      raise ActiveRecord::Rollback
    end


    # X2: delega ao helper compartilhado em BaseSheetEditService.
    def resolve_klass_id(raw)
      resolve_polymorphic_id(Klass, raw)
    end

    # Resolve uma referência a SubKlass — aceita id numérico OU api_index do
    # banco (kebab/snake) OU ruleSlug do catálogo do front. Quando há
    # ambiguidade (ex.: `arquearia_arcana` e `arquearia-arcana` ambos existem),
    # prioriza a subclasse pertencente à mesma `klass_id`.
    def resolve_sub_klass_id(raw, klass_id:)
      return nil if raw.blank?
      str = raw.to_s.strip
      if str.match?(/\A\d+\z/)
        # já é id numérico — confirma que existe E pertence à classe certa
        sk = SubKlass.find_by(id: str.to_i)
        return sk&.klass_id == klass_id ? sk.id : nil
      end

      slug_kebab = str.downcase.gsub('_', '-')
      slug_snake = slug_kebab.tr('-', '_')

      candidates = SubKlass
                    .where(klass_id: klass_id)
                    .where('LOWER(api_index) IN (?)', [slug_kebab, slug_snake])
                    .pluck(:id)
      return candidates.first if candidates.any?

      # Fallback: id mock do catálogo do front (ex.: 'sub-9h') — sem mapping
      # canônico no backend; deixa explícito que não resolveu.
      nil
    end
  end
end
