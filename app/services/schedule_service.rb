class ScheduleService
  prepend SimpleCommand

  # Aceita os parâmetros canônicos do form (`schedule_params` do controller).
  # Em vez de exigir `date_dimension_id` pré-existente, aceita também `date`
  # (string ISO) e auto-cria o registro de DateDimension on-demand. Isso evita
  # depender de seed manual cobrir todos os anos futuros.
  def initialize(schedule_params, current_user: nil)
    @schedule_params = schedule_params.respond_to?(:to_h) ? schedule_params.to_h : schedule_params.dup
    @current_user = current_user
  end

  def call
    create_schedule
  end

  # Versão de classe do helper, exposta para reuso no controller (update),
  # onde só precisamos do auto-create de DateDimension sem rodar o flow
  # completo de SimpleCommand.
  def self.ensure_date_dimension(iso_date)
    new({}).send(:ensure_date_dimension, iso_date)
  end

  # Validação compartilhada: criação (e mudança de data) não pode ser no passado
  # nem em dia vetado (`date_dimensions.available == false`).
  def self.assert_bookable_date_dimension!(date_dimension_id)
    dd = DateDimension.find_by(id: date_dimension_id)
    raise ArgumentError, 'data inválida (date_dimension)' if dd.nil?
    if dd.date < Date.current
      raise ArgumentError, 'não é permitido agendar sessões em datas passadas'
    end
    if dd.available == false
      raise ArgumentError, 'este dia está indisponível para agendamentos'
    end

    dd
  end

  private

  def create_schedule
    ActiveRecord::Base.transaction do
      attrs = @schedule_params.deep_dup
      iso_date = attrs.delete(:date) || attrs.delete('date')
      raw_character_ids = attrs.delete(:character_ids) || attrs.delete('character_ids')

      if iso_date.present?
        d = Date.parse(iso_date.to_s)
        raise ArgumentError, 'não é permitido agendar sessões em datas passadas' if d < Date.current
        attrs[:date_dimension_id] ||= ensure_date_dimension(iso_date)
      elsif (dd_id = attrs[:date_dimension_id] || attrs['date_dimension_id']).present?
        attrs[:date_dimension_id] = dd_id
      else
        raise ArgumentError, 'data é obrigatória (use date em ISO ou date_dimension_id)'
      end

      self.class.assert_bookable_date_dimension!(attrs[:date_dimension_id] || attrs['date_dimension_id'])

      unless Schedule.supports_linked_npc_sheet_ids?
        attrs.delete(:linked_npc_character_ids)
        attrs.delete('linked_npc_character_ids')
      end
      unless Schedule.supports_dm_temp_npc_character_ids?
        attrs.delete(:dm_temp_npc_character_ids)
        attrs.delete('dm_temp_npc_character_ids')
      end

      schedule = Schedule.new(attrs)
      schedule.save!

      attach_characters(schedule, raw_character_ids)
      ScheduleContinuity.copy_from_prior_session!(schedule, current_user: @current_user)

      schedule
    end
  end

  # Cria os ScheduleCharacter de forma idempotente. Se `character_ids` foi
  # explicitamente informado pelo cliente, restringe a esse subset (validando
  # que cada um pertence ao grupo da sessão); caso contrário, anexa todos os
  # personagens do grupo (comportamento histórico — mantém compat com o front
  # antigo que não envia o subset).
  def attach_characters(schedule, raw_character_ids)
    group = schedule.group
    return if group.nil?

    group_character_ids = group.characters.pluck(:id).to_set

    target_ids =
      if raw_character_ids.is_a?(Array) && raw_character_ids.any?
        normalized = raw_character_ids.map { |id| id.to_i }.reject(&:zero?).uniq
        invalid = normalized - group_character_ids.to_a
        if invalid.any?
          raise ArgumentError, "personagens fora do grupo: #{invalid.join(',')}"
        end
        normalized
      else
        group_character_ids.to_a
      end

    target_ids.each do |character_id|
      ScheduleCharacter.find_or_create_by!(character_id: character_id, schedule_id: schedule.id)
    end
  end

  # Encontra (ou cria) uma DateDimension pela data ISO. Mantém os campos de
  # apoio (year/month/day_of_week) preenchidos para não quebrar consultas
  # legadas que filtram por eles.
  def ensure_date_dimension(iso_date)
    date = iso_date.is_a?(Date) ? iso_date : Date.parse(iso_date.to_s)
    dd = DateDimension.find_or_initialize_by(date: date)
    dd.year       = date.year
    dd.month      = date.month
    dd.day        = date.day
    dd.day_of_week = date.wday
    dd.day_name   = date.strftime('%A')
    dd.is_weekend = date.saturday? || date.sunday?
    dd.available  = true if dd.available.nil?
    dd.save!
    dd.id
  rescue ArgumentError
    raise ArgumentError, "data inválida: #{iso_date.inspect}"
  end
end
