# frozen_string_literal: true

require 'rails_helper'

# O canal precisa ser por (mapa, sessao): duas mesas no MESMO mapa nao podem
# receber os eventos uma da outra — senao o token movido numa aparece na outra.
RSpec.describe MapChannel, type: :channel do
  let(:dm)     { create(:user, role: Role.find_by(name: 'DM') || create(:role, name: 'DM')) }
  let(:group)  { create(:group, dm_user: dm) }
  let(:map)    { create(:battle_map, user: dm) }
  let(:sessao_a) { create(:schedule, group: group, created_by_user: dm) }

  describe '.stream_name' do
    it 'sem sessao usa o canal base (Map Builder)' do
      expect(described_class.stream_name(map)).to eq("map_#{map.id}")
    end

    it 'com sessao isola por mesa' do
      expect(described_class.stream_name(map, 42)).to eq("map_#{map.id}_s42")
    end

    it 'REGRESSAO: duas mesas no mesmo mapa caem em canais DIFERENTES' do
      expect(described_class.stream_name(map, 1)).not_to eq(described_class.stream_name(map, 2))
    end

    it 'le a sessao da INSTANCIA do mapa — e assim que o broadcast acerta o canal' do
      map.session_scope_schedule_id = sessao_a.id

      expect(described_class.stream_name(map)).to eq("map_#{map.id}_s#{sessao_a.id}")
    end

    it 'o argumento explicito vence o da instancia' do
      map.session_scope_schedule_id = 999

      expect(described_class.stream_name(map, 7)).to eq("map_#{map.id}_s7")
    end
  end

  describe 'broadcast usa o canal da mesa' do
    it 'publica no canal da sessao quando a instancia esta marcada' do
      map.session_scope_schedule_id = sessao_a.id

      expect {
        MapRealtime::Broadcaster.fog_changed(map, [], actor: dm)
      }.to have_broadcasted_to("map_#{map.id}_s#{sessao_a.id}")
    end

    it 'sem sessao publica no canal base' do
      expect {
        MapRealtime::Broadcaster.fog_changed(map, [], actor: dm)
      }.to have_broadcasted_to("map_#{map.id}")
    end
  end
end
