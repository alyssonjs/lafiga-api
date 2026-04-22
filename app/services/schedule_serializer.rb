# Serializa um Schedule no formato canônico que o frontend (Hub + SessionManager
# + WebSocket) consome. Único ponto de verdade — usado pelo controller, pelo
# broadcast e pelos endpoints de timeline.
class ScheduleSerializer
  # @param include_dm_notes [Boolean] quando false, omite notas do mestre (leitores
  #   sem vínculo com a mesa — ver SchedulesController + for_hub_player).
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

  # @param viewer [User, nil] se presente e não for DM site-wide, redige `dm_notes`
  #   nas sessões fora do escopo `Schedule.for_hub_player(viewer)`.
  def self.serialize_collection(schedules, viewer: nil)
    privileged_ids =
      if viewer.nil? || Group.user_is_dm?(viewer)
        nil
      else
        Schedule.for_hub_player(viewer).pluck(:id).to_set
      end

    schedules.map do |s|
      include_dm = privileged_ids.nil? || privileged_ids.include?(s.id)
      serialize(s, include_dm_notes: include_dm)
    end
  end
end
