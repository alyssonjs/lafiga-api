class Api::V1::Public::DateDimensionsController < ApplicationController
  # Pré-carga: folhas de ficha (nível, classe, chibi) usadas em `GroupSerializer#serialize_member_for_roster`
  CHARACTER_SHEET_INCLUDES = { characters: { sheet: [:race, { sheet_klasses: %i[klass sub_klass] }] } }.freeze

  def index
    year  = params.require(:year).to_i
    month = params.require(:month).to_i

    @calendar_group_payload_cache = {}

    prev_month_date = Date.new(year, month, 1).prev_month
    next_month_date = Date.new(year, month, 1).next_month

    start_date = prev_month_date.beginning_of_month
    end_date   = next_month_date.end_of_month

    date_dimensions = DateDimension
                        .where(date: start_date..end_date)
                        .includes(
                          { schedule: [:schedule_characters, { group: CHARACTER_SHEET_INCLUDES }] },
                          { schedules:  [:schedule_characters, { group: CHARACTER_SHEET_INCLUDES }] },
                        )
                        .order(:date)

    rows = date_dimensions.map { |dd| build_calendar_row_json(dd) }
    # Hash[] + top-level Array: não usar `render json:` puro — o AMS 0.10 tenta
    # `CollectionSerializer` e loga "No serializer found" para cada Hash, além de custo extra.
    render body: rows.to_json, content_type: 'application/json; charset=utf-8', status: :ok
  end

  private

  def build_calendar_row_json(date_dimension)
    h = {
      id: date_dimension.id,
      date: date_dimension.date,
      year: date_dimension.year,
      month: date_dimension.month,
      day: date_dimension.day,
      day_of_week: date_dimension.day_of_week,
      day_name: date_dimension.day_name,
      is_weekend: date_dimension.is_weekend,
      available: date_dimension.available,
    }
    if date_dimension.association(:schedule).loaded? && date_dimension.schedule
      h[:schedule] = serialize_public_calendar_schedule(date_dimension.schedule)
    else
      h[:schedule] = nil
    end

    if date_dimension.association(:schedules).loaded?
      h[:schedules] = date_dimension.schedules.map { |s| serialize_public_calendar_schedule(s) }
    else
      h[:schedules] = nil
    end
    h
  end

  # Mesmo tronco de `ScheduleSerializer` + grupo com `GroupSerializer` (nomes, nível, chibi).
  def serialize_public_calendar_schedule(schedule)
    return nil unless schedule

    include_dm_notes = false
    base = ScheduleSerializer.serialize(schedule, include_dm_notes: include_dm_notes)
    g = schedule.group
    group_payload =
      if g
        @calendar_group_payload_cache[g.id] ||= GroupSerializer.serialize(g)
      else
        nil
      end
    base.merge(group: group_payload)
  end
end
