# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SessionFeed::Retention do
  let(:schedule) { create(:schedule) }

  describe '.call' do
    it 'preserva tudo quando volume está abaixo de KEEP_LATEST mesmo se velho' do
      create(:session_feed_item, schedule: schedule, posted_at: 6.months.ago, client_id: 'old-1')
      create(:session_feed_item, schedule: schedule, posted_at: 1.day.ago,    client_id: 'new-1')

      expect { described_class.call(schedule_id: schedule.id) }
        .not_to change(SessionFeedItem, :count)
    end

    it 'deleta items >1 mês que NÃO estão entre os 1000 mais recentes' do
      stub_const("#{described_class}::KEEP_LATEST", 3)

      newest = 5.times.map do |i|
        create(:session_feed_item,
               schedule: schedule,
               posted_at: i.days.ago,
               client_id: "fresh-#{i}")
      end
      old_to_drop = create(:session_feed_item,
                            schedule: schedule,
                            posted_at: 2.months.ago,
                            client_id: 'old-drop')

      deleted = described_class.call(schedule_id: schedule.id)
      expect(deleted).to eq(1)
      expect(SessionFeedItem.exists?(old_to_drop.id)).to be(false)
      newest.each { |n| expect(SessionFeedItem.exists?(n.id)).to be(true) }
    end

    it 'remove roll_pending órfãos com mais de 5 minutos' do
      stale = create(:session_feed_item, :roll_pending,
                     schedule: schedule, posted_at: 10.minutes.ago, client_id: 'pend-stale')
      fresh = create(:session_feed_item, :roll_pending,
                     schedule: schedule, posted_at: 1.minute.ago,   client_id: 'pend-fresh')

      described_class.call(schedule_id: schedule.id)
      expect(SessionFeedItem.exists?(stale.id)).to be(false)
      expect(SessionFeedItem.exists?(fresh.id)).to be(true)
    end
  end

  describe '.run_all' do
    it 'roda em todos os schedules com items' do
      s1 = create(:schedule); s2 = create(:schedule)
      stub_const("#{described_class}::KEEP_LATEST", 1)

      create(:session_feed_item, schedule: s1, posted_at: 2.months.ago, client_id: 's1-old')
      create(:session_feed_item, schedule: s1, posted_at: 1.day.ago,    client_id: 's1-new')
      create(:session_feed_item, schedule: s2, posted_at: 2.months.ago, client_id: 's2-old')
      create(:session_feed_item, schedule: s2, posted_at: 1.day.ago,    client_id: 's2-new')

      total = described_class.run_all
      expect(total).to eq(2)
      expect(SessionFeedItem.where(schedule: schedule).count).to eq(0)
      expect(SessionFeedItem.count).to eq(2)
    end
  end
end
