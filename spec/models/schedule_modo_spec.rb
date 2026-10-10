# frozen_string_literal: true

require 'rails_helper'

# O MODO da mesa (L0.8; plano B3): só a sessão de campanha ocupa o "slot único" do grupo e do criador. A mesa da vila
# convive com ela, na validação e no índice do banco.
RSpec.describe Schedule, type: :model do
  let(:mestre) { create(:user) }
  let(:group) { create(:group, dm_user_id: mestre.id) }
  let(:dia) { DateDimension.find_by(date: Date.new(2031, 3, 10)) || create(:date_dimension, date: Date.new(2031, 3, 10)) }
  let!(:campanha) { create(:schedule, group: group, date_dimension: dia, status: :waiting, created_by_user_id: mestre.id) }

  def mesa(modo, **extra)
    build(:schedule, group: group, date_dimension: dia, status: :waiting, created_by_user_id: mestre.id, modo: modo, **extra)
  end

  it 'nasce de campanha, e só aceita os modos conhecidos' do
    expect(campanha.modo).to eq('campanha')
    expect(campanha).to be_de_campanha
    expect(mesa('torneio')).not_to be_valid
  end

  it 'a mesa da vila convive com a sessão de campanha aberta, no mesmo grupo e no mesmo dia' do
    vila = mesa('vila')

    expect(vila).to be_valid
    expect { vila.save! }.not_to raise_error
    expect(mesa('missao')).to be_valid
  end

  it 'duas sessões de CAMPANHA abertas no mesmo grupo continuam proibidas' do
    expect(mesa('campanha')).not_to be_valid
  end

  it 'o índice do banco também segura a campanha, e deixa a vila passar' do
    expect { mesa('campanha').save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    expect { mesa('vila').save!(validate: false) }.not_to raise_error
  end

  it 'o escopo do slot único só vê a campanha' do
    mesa('vila').save!

    expect(described_class.blocking_new_schedule.where(group_id: group.id)).to eq([campanha])
    expect(described_class.de_campanha.where(group_id: group.id)).to eq([campanha])
  end

  it 'o serializador diz o modo' do
    vila = mesa('vila')
    vila.save!

    expect(ScheduleSerializer.serialize(vila, include_dm_notes: false)).to include(modo: 'vila')
  end
end
