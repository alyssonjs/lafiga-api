class Schedule < ApplicationRecord
  enum status: { reserved: 0, waiting: 1 }

  belongs_to :date_dimension
  belongs_to :group

  has_many :schedule_characters, dependent: :destroy

  validates :status, :date_dimension_id, :title, presence: true
  validates :date_dimension_id, uniqueness: true
  before_save :check_date_availability
  after_destroy :reopen_day
  after_update :sync_days_if_date_changed, if: :saved_change_to_date_dimension_id?
  after_commit :broadcast_created, on: :create
  after_commit :broadcast_updated, on: :update
  after_commit :broadcast_destroyed, on: :destroy

  private

  def check_date_availability
    if !date_dimension.available
      errors.add(:base, "A data selecionada não está disponível.")
      throw(:abort)
    end
  end

  def reopen_day
    dd = date_dimension
    return unless dd
    dd.update_column(:available, true)
  end

  def sync_days_if_date_changed
    old_id, new_id = saved_change_to_date_dimension_id
    old_dd = DateDimension.find_by(id: old_id)
    new_dd = DateDimension.find_by(id: new_id)
    old_dd&.update_column(:available, true)
    new_dd&.update_column(:available, false)
  end

  def broadcast_created
    payload = as_json(include: [:group, :date_dimension])
    ActionCable.server.broadcast("group_#{group_id}_schedules", { event: 'created', schedule: payload })
    Rails.logger.info({ event: 'schedule.created', schedule_id: id, group_id: group_id, date_dimension_id: date_dimension_id }.to_json)
  end

  def broadcast_updated
    payload = as_json(include: [:group, :date_dimension])
    ActionCable.server.broadcast("group_#{group_id}_schedules", { event: 'updated', schedule: payload })
    Rails.logger.info({ event: 'schedule.updated', schedule_id: id, group_id: group_id, date_dimension_id: date_dimension_id }.to_json)
  end

  def broadcast_destroyed
    ActionCable.server.broadcast("group_#{group_id}_schedules", { event: 'destroyed', schedule_id: id })
    Rails.logger.info({ event: 'schedule.destroyed', schedule_id: id, group_id: group_id, date_dimension_id: date_dimension_id }.to_json)
  end
end
