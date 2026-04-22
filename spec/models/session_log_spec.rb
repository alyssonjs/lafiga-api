require 'rails_helper'

RSpec.describe SessionLog, type: :model do
  let(:schedule) { create(:schedule) }

  describe 'enum kind' do
    it 'maps every LogEntryType from the frontend' do
      expect(SessionLog.kinds).to eq(
        'narrative' => 0, 'combat' => 1, 'roll' => 2, 'rest' => 3, 'note' => 4, 'xp' => 5
      )
    end
  end

  describe 'validations' do
    it 'requires message and kind' do
      log = SessionLog.new(schedule: schedule, message: '')
      expect(log).not_to be_valid
      expect(log.errors[:message]).to be_present
    end

    it 'auto-fills posted_at when missing' do
      log = create(:session_log, schedule: schedule, posted_at: nil)
      expect(log.posted_at).to be_present
    end

    it 'allows nil roll_result' do
      log = build(:session_log, schedule: schedule, roll_result: nil)
      expect(log).to be_valid
    end

    it 'requires expression and integer total when roll_result is present' do
      log = build(:session_log, schedule: schedule, kind: :roll, roll_result: { 'expression' => '', 'total' => 'oops' })
      expect(log).not_to be_valid
      expect(log.errors[:roll_result]).to be_present
    end

    it 'accepts a well-formed roll_result' do
      log = build(:session_log, schedule: schedule, kind: :roll,
                  roll_result: { 'expression' => '1d20+3', 'total' => 17, 'breakdown' => '14 + 3' })
      expect(log).to be_valid
    end
  end

  describe 'scopes' do
    it 'recent_first orders by posted_at DESC' do
      old   = create(:session_log, schedule: schedule, posted_at: 2.hours.ago)
      newer = create(:session_log, schedule: schedule, posted_at: 1.minute.ago)
      expect(SessionLog.recent_first.to_a).to eq([newer, old])
    end
  end
end
