# frozen_string_literal: true

require 'rails_helper'

# MembrosProducer (05/10): os efeitos que o Mestre deu ao membro substituído entram no pipeline como os de um item
# mágico — e o summary os soma (CA, deslocamento, resistências, vantagens, passivas). A perna perdida anda pela metade.
RSpec.describe Modifiers::Producers::MembrosProducer, type: :service do
  let(:sheet) { create(:sheet, character: create(:character, user: create(:user))) }

  def com_membros(membros)
    sheet.update!(avatar_customization: { 'gender' => 'masculine', 'membros' => membros })
    sheet
  end

  def substituto(tipo, efeitos)
    { 'estado' => 'substituido', 'substituto' => { 'tipo' => tipo, 'material' => 'metal', 'cor' => 'steel', 'efeitos' => efeitos } }
  end

  it 'sem membros, nada' do
    expect(described_class.new(sheet).produce).to eq([])
  end

  it 'os efeitos do substituto viram modificadores com a origem :membro', :aggregate_failures do
    com_membros('braco_direito' => substituto('protese', [
      { 'kind' => 'ability_bonus', 'ability' => 'str', 'value' => 2 },
      { 'kind' => 'ac_bonus', 'value' => 1 },
      { 'kind' => 'speed_bonus', 'value' => 5 },
      { 'kind' => 'resistance', 'damage_types' => ['fire'] },
      { 'kind' => 'save_advantage', 'abilities' => ['str'] },
      { 'kind' => 'passive_feature', 'name' => 'Punho de Ferro', 'desc' => 'Soco de metal.' },
      { 'kind' => 'attack_bonus', 'value' => 1 },
    ]))
    bag = Modifiers::ModifierResolver.new(sheet, producer_keys: %i[membros]).call
    expect(bag.mods.map(&:source_kind).uniq).to eq([:membro])
    expect(bag.sum_for('ability.str')).to eq(2)
    expect(bag.sum_for('ac')).to eq(1)
    expect(bag.sum_for('speed')).to eq(5)
    expect(bag.granted('resistance')).to eq(['fire'])
    expect(bag.granted('advantage.save')).to eq(['str'])
    expect(bag.matching('passive_feature').map { |m| m.value[:name] }).to eq(['Punho de Ferro'])
    # o ataque é da ARMA natural do membro, não de toda arma
    expect(bag.all_for('weapon.attack')).to be_empty
    expect(bag.all_for('ac').first.note).to include('Prótese (braço direito)')
  end

  it 'a mão marcada dentro do braço trocado não conta (o maior leva os menores)' do
    com_membros(
      'braco_direito' => substituto('protese', [{ 'kind' => 'ac_bonus', 'value' => 1 }]),
      'mao_direito' => substituto('gancho', [{ 'kind' => 'ac_bonus', 'value' => 3 }]),
    )
    bag = Modifiers::ModifierResolver.new(sheet, producer_keys: %i[membros]).call
    expect(bag.sum_for('ac')).to eq(1)
  end

  describe 'no summary' do
    before { RaceRules.reload! }

    # o humano anda 30 ft (RaceRules): a raça de fábrica não tem deslocamento
    let(:sheet) do
      humano = Race.find_or_create_by!(api_index: 'human') { |r| r.name = 'Humano' }
      Sheet.create!(character: create(:character, user: create(:user)), race: humano,
                    str: 10, dex: 12, con: 12, int: 10, wis: 10, cha: 10, hp_max: 8, hp_current: 8, current_level: 1)
    end

    def summary
      CharacterSheetSummaryService.new(sheet_id: sheet.id, sync: false).call.result
    end

    it 'o efeito da prótese chega ao bloco de modificadores (o front lê daqui)', :aggregate_failures do
      com_membros('mao_esquerdo' => substituto('protese', [{ 'kind' => 'resistance', 'damage_types' => ['cold'] }]))
      expect(summary.dig(:modifiers, :resistances)).to include('cold')
    end

    it '⚠️ a perna perdida anda pela METADE; a perna de pau devolve o andar', :aggregate_failures do
      base = summary.dig(:movement, :speed_ft).to_i
      expect(base).to be > 0

      com_membros('pe_direito' => { 'estado' => 'perdido' })
      metade = summary[:movement]
      expect(metade[:speed_ft]).to eq(base / 2)
      expect(metade[:membro_perdido]).to be(true)

      com_membros('pe_direito' => substituto('perna_de_pau', []))
      expect(summary.dig(:movement, :speed_ft)).to eq(base)
    end
  end
end
