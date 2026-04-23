# Serializa um Schedule no formato canônico que o frontend (Hub + SessionManager
# + WebSocket) consome. Único ponto de verdade — usado pelo controller, pelo
# broadcast e pelos endpoints de timeline.
class ScheduleSerializer
  # Notas do mestre (`dm_notes`): apenas usuário com papel site-wide DM/Admin ou
  # o dono da campanha (`groups.dm_user_id`). Jogadores nunca recebem o texto,
  # mesmo com personagem na sessão (evita vazamento via JSON ou ActionCable).
  def self.dm_notes_visible_to_user?(user, schedule)
    return false if user.nil? || schedule.nil?
    return true if Group.user_is_dm?(user)

    schedule.group&.owned_by?(user)
  end

  # @param include_dm_notes [Boolean] quando false, omite notas do mestre (leitores
  #   sem privilégio — ver #dm_notes_visible_to_user?).
  def self.serialize(schedule, include_dm_notes: true)
    return nil unless schedule

    {
      id: schedule.id,
      title: schedule.title,
      status: schedule.status,
      description: schedule.description,
      dm_notes: include_dm_notes ? schedule.dm_notes.to_s : '',
      summary: schedule.summary,
      campaign_name: schedule.campaign_name,
      scheduled_time: schedule.scheduled_time,
      xp_awarded: schedule.xp_awarded.to_i,
      started_at: schedule.started_at,
      ended_at: schedule.ended_at,
      highlights: Array(schedule.highlights),
      created_at: schedule.created_at,
      updated_at: schedule.updated_at,
      group_id: schedule.group_id,
      group: schedule.group&.as_json(only: [:id, :name]),
      battle_map_id: schedule.battle_map_id,
      date_dimension_id: schedule.date_dimension_id,
      date_dimension: schedule.date_dimension&.as_json,
      character_ids: schedule.schedule_characters.loaded? ?
        schedule.schedule_characters.map(&:character_id) :
        schedule.schedule_characters.pluck(:character_id),
    }
  end

  # @param viewer [User, nil] usuário atual; `dm_notes` só entram no JSON se
  #   #dm_notes_visible_to_user?(viewer, schedule). Com viewer nil, tudo redigido.
  def self.serialize_collection(schedules, viewer: nil)
    schedules.map do |s|
      serialize(s, include_dm_notes: dm_notes_visible_to_user?(viewer, s))
    end
  end
end
