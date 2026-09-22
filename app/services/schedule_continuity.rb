# frozen_string_literal: true

# Sessão nova da mesma mesa RETOMA a anterior: o mapa (por REFERÊNCIA, com a
# camada da vertente), as fichas NPC ligadas à mesa e — ao INICIAR — os NPCs de
# combate e o estado de combate.
#
# ⚠️ O mapa era COPIADO aqui — cópia profunda a cada sessão criada. Isto nasceu
# em abr/2026, quando não havia outro jeito de a mesa retomar de onde parou; a
# VERTENTE (`MapBranch` + `ScheduleBattleMap`, ago/2026) passou a resolver o
# mesmo problema sem duplicar nada, e a cópia ficou para trás sem ninguém a
# remover. Os dois mecanismos conviveram, o antigo ganhou, e a página de mapas
# encheu de duplicatas — oito "Novo Mapa (Copia)" idênticos em produção, uma por
# sessão criada. Agora o vínculo REFERENCIA o mapa e semeia a camada.
#
# ⚠️ Os NPCs eram copiados na CRIAÇÃO — e sessão se cria com antecedência. Em
# 21/09 a #104 foi criada às 11:50, o Mestre montou o exército na sessão
# anterior à noite e iniciou a #104 às 21:26: nada veio, e ele recriou 109 NPCs
# à mão. A anterior só termina de verdade quando a próxima COMEÇA — é aí que a
# cópia acontece agora.
class ScheduleContinuity
  ORDEM_CRONOLOGICA_DESC = 'date_dimensions.date DESC, schedules.scheduled_time DESC NULLS LAST, schedules.id DESC'

  def self.copy_from_prior_session!(schedule, current_user:)
    return if schedule.group_id.blank?

    schedule.reload # garante date_dimension / battle_map_id frescos
    source = prior_session_for(schedule)
    return if source.nil?

    link_battle_map(source, schedule, current_user)
    copy_linked_npc_sheet_ids(source, schedule)
    # Sessão que já nasce em andamento (a de teste do Mestre) não passa pelo
    # `start!`: começa aqui mesmo.
    continue_on_start!(schedule) if schedule.in_progress?
    schedule.reload
  end

  # Sessões da mesma mesa que vieram ANTES desta — as candidatas a "anterior".
  #
  # ⚠️ A MESMA régua para os NPCs e para a camada do mapa. A camada usava outra
  # (a data mais recente entre TODAS as irmãs) e herdava de sessão FUTURA ou
  # CANCELADA: a #104 (21/09) nasceu com o mapa vazio herdado da #98 (23/09,
  # cancelada). Sessão de teste do Mestre também não é "anterior" de ninguém.
  def self.earlier_sessions(schedule)
    new_date = schedule.date_dimension&.date
    return Schedule.none if schedule.group_id.blank? || new_date.blank?

    st = schedule.scheduled_time.presence || '00:00'
    Schedule
      .joins(:date_dimension)
      .where(group_id: schedule.group_id)
      .where.not(id: schedule.id)
      .where.not(status: :cancelled)
      .non_sandbox
      .where(
        <<~SQL.squish,
          (date_dimensions.date, COALESCE(schedules.scheduled_time, '00:00'), schedules.id)
          < (?, COALESCE(?, '00:00'), ?)
        SQL
        new_date,
        st,
        schedule.id,
      )
  end

  def self.prior_session_for(schedule)
    earlier_sessions(schedule).order(Arel.sql(ORDEM_CRONOLOGICA_DESC)).first
  end

  # A sessão acabou de COMEÇAR: traz os NPCs de combate da anterior (e o estado
  # de combate, se ela não tem um), com os tokens deles acompanhando.
  #
  # Só se a sessão ainda não tem NPCs dela — se o Mestre já montou o elenco
  # desta mesa, misturar os dois seria decidir por ele.
  def self.continue_on_start!(schedule)
    return if schedule.group_id.blank?

    source = prior_session_for(schedule)
    return if source.nil?

    ActiveRecord::Base.transaction do
      npc_id_map = schedule.combat_npcs.exists? ? {} : copy_npcs(source, schedule)
      copy_combat_state(source, schedule, npc_id_map) if schedule.combat_state.nil?
      bring_npc_tokens!(source, schedule, npc_id_map)
    end
  end

  # O MESMO mapa da sessão anterior, mais a camada desta sessão.
  #
  # O tabuleiro (fundo, paredes, terreno, cenário) é compartilhado de propósito:
  # editar no Map Builder vale para todas as mesas. O que é DAQUELA mesa —
  # tokens, névoa, medições, desenhos, áreas e projéteis — vive na camada, e
  # `MapBranch.ensure!` a semeia herdando a da sessão anterior.
  #
  # ⚠️ `previous_layer` casa por (grupo, MAPA). Enquanto cada sessão ganhava a
  # própria cópia, essa busca nunca achava nada e a herança vinha de carona no
  # conteúdo duplicado; apontando para o mesmo mapa, ela passa a funcionar como
  # foi desenhada.
  def self.link_battle_map(source, target, current_user)
    return if target.battle_map_id.present?
    return if source.battle_map_id.blank?

    map = BattleMap.find_by(id: source.battle_map_id)
    return unless map&.readable_by?(current_user)

    target.update!(battle_map_id: map.id)
    MapBranch.ensure!(schedule: target, map: map)
  end

  def self.copy_linked_npc_sheet_ids(source, target)
    return unless Schedule.supports_linked_npc_sheet_ids?

    ids = normalize_id_array(source.linked_npc_sheet_ids_normalized)
    return if ids.empty?

    target.update!(linked_npc_character_ids: ids)
  end

  # Cópias dos NPCs, cada uma sabendo de qual veio (`source_npc_id`) — é o que
  # deixa o token herdado achar o NPC certo nesta sessão. Devolve {antigo => novo}.
  def self.copy_npcs(source, target)
    npc_id_map = {}
    source.combat_npcs.find_each do |npc|
      n = npc.dup
      n.schedule_id = target.id
      n.source_npc_id = npc.id
      n.save!
      npc_id_map[npc.id] = n.id
    end
    npc_id_map
  end

  def self.copy_combat_state(source, target, npc_id_map)
    src_cs = source.combat_state
    return if src_cs.nil?

    new_cs = src_cs.dup
    new_cs.schedule_id = target.id
    new_cs.save!

    src_cs.combat_combatants.order(:position).each do |cc|
      new_cc = cc.dup
      new_cc.combat_state_id = new_cs.id
      case new_cc.combatable_type
      when CombatNpc.name
        new_id = npc_id_map[cc.combatable_id]
        next if new_id.nil?

        new_cc.combatable_id = new_id
      when Character.name
        ch = Character.find_by(id: new_cc.combatable_id)
        next if ch.nil? || ch.group_id != target.group_id
      else
        next
      end
      new_cc.save!
    end
  end

  # Os tokens dos NPCs acompanham as cópias: em cada mapa que esta sessão tem
  # em comum com a anterior, os tokens de NPC passam a ser os da anterior
  # AGORA, apontando para as cópias desta sessão.
  #
  # ⚠️ A camada foi semeada quando a sessão foi CRIADA — com os tokens de NPC
  # daquele momento. O que o Mestre pôs na anterior depois precisa entrar, o
  # que ele tirou precisa sair (senão fica um token órfão, de um NPC que não
  # existe mais), e o que ficou precisa achar a cópia. Espelhar faz os três.
  # Esta sessão não tinha NPCs (é a condição para copiar), então nenhum token
  # de NPC dela é do Mestre. PCs, tokens avulsos, névoa e desenhos: intactos.
  def self.bring_npc_tokens!(source, target, npc_id_map)
    return if npc_id_map.empty?

    target.schedule_battle_maps.each do |camada|
      origem = ScheduleBattleMap.find_by(schedule_id: source.id, battle_map_id: camada.battle_map_id)
      tokens =
        if origem
          Array(camada.tokens).reject { |t| npc_token?(t) } +
            remap_npc_tokens(Array(origem.tokens).select { |t| npc_token?(t) }, npc_id_map)
        else
          remap_npc_tokens(camada.tokens, npc_id_map)
        end
      camada.update!(tokens: tokens) unless tokens == Array(camada.tokens)
    end
  end

  def self.npc_token?(token)
    token.is_a?(Hash) && token['npcId'].present?
  end

  # `npcId: "npc-<antigo>"` → `"npc-<novo>"`. O resto do token fica intacto.
  def self.remap_npc_tokens(tokens, npc_id_map)
    Array(tokens).map do |t|
      next t unless t.is_a?(Hash)

      antigo = t['npcId'].to_s[/\Anpc-(\d+)\z/, 1]
      novo = antigo && npc_id_map[antigo.to_i]
      novo ? t.merge('npcId' => "npc-#{novo}") : t
    end
  end

  # {id do NPC na sessão anterior => id da cópia nesta sessão}.
  def self.npc_id_map_for(schedule)
    schedule.combat_npcs.where.not(source_npc_id: nil).pluck(:source_npc_id, :id).to_h
  end

  def self.normalize_id_array(raw)
    Array(raw).map(&:to_i).reject(&:zero?).uniq
  end
end
