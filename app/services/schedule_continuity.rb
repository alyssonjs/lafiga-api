# frozen_string_literal: true

# Ao criar uma nova sessão (Schedule) para o mesmo grupo, retoma o estado jogável
# da sessão cronologicamente anterior: mapa (por REFERÊNCIA), NPCs de combate,
# estado de combate + combatentes (com HP/iniciativa), e IDs de fichas NPC
# ligadas à mesa (`linked_npc_character_ids`).
#
# ⚠️ O mapa era COPIADO aqui — cópia profunda a cada sessão criada. Isto nasceu
# em abr/2026, quando não havia outro jeito de a mesa retomar de onde parou; a
# VERTENTE (`MapBranch` + `ScheduleBattleMap`, ago/2026) passou a resolver o
# mesmo problema sem duplicar nada, e a cópia ficou para trás sem ninguém a
# remover. Os dois mecanismos conviveram, o antigo ganhou, e a página de mapas
# encheu de duplicatas — oito "Novo Mapa (Copia)" idênticos em produção, uma por
# sessão criada. Agora o vínculo REFERENCIA o mapa e semeia a camada.
class ScheduleContinuity
  def self.copy_from_prior_session!(schedule, current_user:)
    return if schedule.group_id.blank?

    schedule.reload # garante date_dimension / battle_map_id frescos
    source = prior_session_for(schedule)
    return if source.nil?

    link_battle_map(source, schedule, current_user)
    copy_linked_npc_sheet_ids(source, schedule)
    copy_combat_entities(source, schedule)
    schedule.reload
  end

  def self.prior_session_for(schedule)
    new_date = schedule.date_dimension&.date
    return nil if new_date.blank?

    st = schedule.scheduled_time.presence || '00:00'
    Schedule
      .joins(:date_dimension)
      .where(group_id: schedule.group_id)
      .where.not(id: schedule.id)
      .where.not(status: :cancelled)
      .where(
        <<~SQL.squish,
          (date_dimensions.date, COALESCE(schedules.scheduled_time, '00:00'), schedules.id)
          < (?, COALESCE(?, '00:00'), ?)
        SQL
        new_date,
        st,
        schedule.id,
      )
      .order(Arel.sql('date_dimensions.date DESC, schedules.scheduled_time DESC NULLS LAST, schedules.id DESC'))
      .first
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

  def self.copy_combat_entities(source, target)
    npc_id_map = {}
    source.combat_npcs.find_each do |npc|
      n = npc.dup
      n.schedule_id = target.id
      n.save!
      npc_id_map[npc.id] = n.id
    end

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

  def self.normalize_id_array(raw)
    Array(raw).map(&:to_i).reject(&:zero?).uniq
  end
end
