# frozen_string_literal: true

require 'rails_helper'

# Um lugar por personagem (L0.8; plano B3): entrar numa mesa tira o personagem de onde ele estava.
RSpec.describe Presencas do
  let(:mestre) { create(:user) }
  let(:group) { create(:group, dm_user_id: mestre.id) }
  let(:personagem) { create(:character, user: create(:user), group: group) }
  let(:dia) { DateDimension.find_by(date: Date.new(2031, 3, 10)) || create(:date_dimension, date: Date.new(2031, 3, 10)) }
  let(:campanha) { create(:schedule, group: group, date_dimension: dia, status: :in_progress) }
  let(:vila) { create(:schedule, group: group, date_dimension: dia, status: :in_progress, modo: 'vila') }
  let(:agora) { Time.utc(2031, 3, 10, 21) }

  it 'o personagem não fica em dois lugares: entrar na vila o tira da campanha' do
    described_class.entra(personagem, schedule: campanha, agora: agora)
    described_class.entra(personagem, schedule: vila, agora: agora + 1.minute)

    expect(Presenca.where(character: personagem).count).to eq(1)
    expect(described_class.onde(personagem)).to have_attributes(schedule_id: vila.id, batimento_em: agora + 1.minute)
  end

  it 'trocar de mesa zera a pilha de retorno; ficar na mesma a mantém' do
    p = described_class.entra(personagem, schedule: vila, agora: agora)
    p.update!(pilha: [{ 'battle_map_id' => 1 }])

    expect(described_class.entra(personagem, schedule: vila, agora: agora).pilha).to eq([{ 'battle_map_id' => 1 }])
    expect(described_class.entra(personagem, schedule: campanha, agora: agora).pilha).to eq([])
  end

  it 'o batimento renova o sinal de vida; sair tira o personagem de todo lugar' do
    described_class.entra(personagem, schedule: vila, agora: agora)

    expect(described_class.batimento(personagem, agora: agora + 5.minutes)).to be(true)
    expect(described_class.onde(personagem).batimento_em).to eq(agora + 5.minutes)
    expect(described_class.sai(personagem)).to be(true)
    expect(described_class.onde(personagem)).to be_nil
    expect(described_class.batimento(personagem, agora: agora)).to be(false)
  end

  it 'o banco também segura: duas linhas do mesmo personagem não entram' do
    described_class.entra(personagem, schedule: vila, agora: agora)
    duplicada = Presenca.new(character: personagem, schedule: campanha, batimento_em: agora)

    expect(duplicada).not_to be_valid
    expect { duplicada.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
