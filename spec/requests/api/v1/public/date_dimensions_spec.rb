# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Public::DateDimensionsController', type: :request do
  let(:group) { create(:group, name: 'Campanha Pública') }
  let(:user) { create(:user) }
  let(:klass) { create(:klass, name: 'Lutador', api_index: "fighter_roster_#{SecureRandom.hex(4)}") }
  let(:character) { create(:character, user: user, name: 'Herói Teste', group: group) }
  let(:sheet) { create(:sheet, character: character) }
  let!(:_sk) { create(:sheet_klass, sheet: sheet, klass: klass, level: 3) }
  let(:dd) do
    d = Date.new(2026, 4, 23)
    DateDimension.find_or_create_by!(date: d) do |row|
      row.assign_attributes(
        year: 2026, month: 4, day: 23, day_of_week: d.wday, day_name: d.strftime('%A'),
        is_weekend: [0, 6].include?(d.wday), available: true
      )
    end
  end
  let!(:schedule) do
    s = create(:schedule, group: group, date_dimension: dd, title: 'Mesa 1', scheduled_time: '20:00')
    ScheduleCharacter.create!(schedule: s, character: character)
    s
  end

  it 'GET /api/v1/public/date_dimensions embeleza schedule com group.members (roster) e character_ids' do
    get '/api/v1/public/date_dimensions', params: { year: 2026, month: 4 }

    expect(response).to have_http_status(:ok)
    rows = response.parsed_body
    expect(rows).to be_a(Array)
    row = rows.find { |r| r['id'] == dd.id }
    expect(row).to be_present, 'esperava uma linha de date_dimension para 2026-04'

    sched = row['schedule']
    expect(sched).to be_a(Hash)
    expect(sched['id']).to eq(schedule.id)
    expect(sched['character_ids']).to eq([character.id])
    g = sched['group']
    expect(g).to be_a(Hash)
    expect(g['name']).to eq('Campanha Pública')
    members = g['members']
    expect(members).to be_an(Array)
    expect(members.length).to eq(1)
    m = members[0]
    expect(m['id']).to eq(character.id)
    expect(m['name']).to include('Herói')
    expect(m['class_name']).to include('Lutador')
  end
end
