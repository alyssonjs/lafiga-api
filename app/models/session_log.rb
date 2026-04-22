# Feed cronológico da sessão. Distinto do chat (Channel/Message) — veja
# migration para o racional.
#
# `kind` mapeia 1:1 com o `LogEntryType` do front (sessionData.ts):
#   narrative=0, combat=1, roll=2, rest=3, note=4, xp=5
class SessionLog < ApplicationRecord
  enum kind: { narrative: 0, combat: 1, roll: 2, rest: 3, note: 4, xp: 5 }

  belongs_to :schedule

  validates :message, presence: true
  validates :kind, presence: true
  validate  :roll_result_well_formed

  before_validation :ensure_posted_at

  scope :recent_first, -> { order(posted_at: :desc) }

  private

  def ensure_posted_at
    self.posted_at ||= Time.current
  end

  def roll_result_well_formed
    return if roll_result.nil?
    return errors.add(:roll_result, 'deve ser um Hash') unless roll_result.is_a?(Hash)

    expression = roll_result['expression']
    total      = roll_result['total']
    breakdown  = roll_result['breakdown']

    errors.add(:roll_result, 'expression obrigatória')          unless expression.is_a?(String) && expression.strip.present?
    errors.add(:roll_result, 'total deve ser inteiro')          unless total.is_a?(Integer)
    errors.add(:roll_result, 'breakdown deve ser string') if breakdown && !breakdown.is_a?(String)
  end
end
