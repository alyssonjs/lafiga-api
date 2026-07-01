# frozen_string_literal: true

require 'rails_helper'

# Cobre os fixes B2.2 e B2.3 do relatorio de auditoria de steps:
#   B2.2: recompute_race_summary! perdia traits/darkvision (so name/speed/langs/profs).
#   B2.3: apply! nao atualizava `race_bonuses_applied` nem ressincronizava as
#         colunas str/dex/... apos trocar raca — entao trocar Anao (CON+2) por
#         Halfling (DES+2) deixava o CON antigo e o DES novo nao aparecia.
#
# Strategy: stubbar `RaceRules.apply` para isolar a logica do service do YAML
# real (que pode mudar). Specs de integracao mais profundos vivem em
# character_provisioning_service_*_spec.rb.
RSpec.describe CharacterSheetEdits::RaceEditService do
  let(:user) { create(:user) }
  let(:character) { create(:character, user: user, status: :active) }
  let(:dwarf) { create(:race) }
  let(:halfling) { create(:race) }
  # Sheet exige sub_race da mesma race; criamos uma vazia so para passar a validacao.
  let(:dwarf_sub) { create(:sub_race, race: dwarf) }
  let!(:sheet) do
    create(:sheet, character: character, race: dwarf, sub_race: dwarf_sub,
                   str: 12, dex: 10, con: 16, int: 10, wis: 10, cha: 10,
                   hp_max: 12, hp_current: 12, current_level: 1,
                   metadata: {
                     'base_ability_scores' => { 'str' => 12, 'dex' => 10, 'con' => 14, 'int' => 10, 'wis' => 10, 'cha' => 10 },
                     'race_bonuses_applied' => { 'con' => 2 },
                     'ability_scores_include_all_increments' => true
                   })
  end
  let!(:sheet_klass) { create(:sheet_klass, sheet: sheet, level: 1) }

  describe 'B2.2 — preserve traits/darkvision' do
    before do
      allow(RaceRules).to receive(:apply).and_return(
        speed: 30,
        languages: %w[Comum Anao],
        proficiencies: { 'tools' => { 'fixed' => ['Ferramentas de ferreiro'] } },
        darkvision: 60,
        # Shape REAL de RaceRules.apply (antes o stub usava {con:2} plano, que
        # mascarava o bug R7: a iteração antiga só funcionava com hash plano).
        ability: { type: 'fixed', increases: [{ ability: 'CON', amount: 2 }] },
        traits: [], innate_spells: [], requires: []
      )
      # Stub traits via association (factory padrao nao popula base_traits/sub_race traits).
      allow(dwarf).to receive(:base_traits).and_return([
        double(id: 1, name: 'Visao no Escuro', description: '60 ft de darkvision.'),
        double(id: 2, name: 'Resiliencia Anao', description: 'Vantagem contra veneno.')
      ])
      allow(Race).to receive(:find_by).with(id: sheet.race_id).and_return(dwarf)
    end

    it 'persiste traits, darkvision e proficiencies em race_summary' do
      svc = described_class.new(character: character, data: { 'raceChoices' => {} })
      svc.call
      sheet.reload

      summary = sheet.race_summary
      expect(summary['name']).to eq(dwarf.name)
      expect(summary['speed_ft']).to eq(30)
      expect(summary['darkvision']).to eq(60)
      expect(summary['languages']).to eq(%w[Comum Anao])
      expect(summary['proficiencies']).to eq('tools' => { 'fixed' => ['Ferramentas de ferreiro'] })
      expect(summary['traits']).to contain_exactly(
        { 'name' => 'Visao no Escuro', 'description' => '60 ft de darkvision.' },
        { 'name' => 'Resiliencia Anao', 'description' => 'Vantagem contra veneno.' }
      )
    end
  end

  describe 'B2.3 — sync ability columns when race changes' do
    before do
      # Stub: Anao da CON+2, Halfling da DEX+1.
      allow(RaceRules).to receive(:apply) do |args|
        if args[:race_id].to_s.include?('halfling')
          { speed: 25, languages: %w[Comum], proficiencies: {}, darkvision: 0, ability: { type: 'fixed', increases: [{ ability: 'DEX', amount: 1 }] }, traits: [], innate_spells: [], requires: [] }
        else
          { speed: 25, languages: %w[Comum Anao], proficiencies: {}, darkvision: 60, ability: { type: 'fixed', increases: [{ ability: 'CON', amount: 2 }] }, traits: [], innate_spells: [], requires: [] }
        end
      end
      allow(dwarf).to receive(:base_traits).and_return([])
      allow(halfling).to receive(:base_traits).and_return([])
      allow(halfling).to receive(:api_index).and_return('halfling')
      allow(Race).to receive(:find_by).and_call_original
      allow(Race).to receive(:find_by).with(id: halfling.id).and_return(halfling)
    end

    it 'atualiza race_bonuses_applied e re-sincroniza colunas apos troca de raca (force=true)' do
      svc = described_class.new(character: character,
                                data: { 'raceId' => halfling.id.to_s },
                                force: true)
      svc.call
      sheet.reload

      expect(sheet.race_id).to eq(halfling.id)
      expect(sheet.metadata['race_bonuses_applied']).to eq('dex' => 1)

      # base era con=14, dex=10. Agora aplica halfling (dex+1):
      #   con = 14 (sem +2 antigo do anao)
      #   dex = 10 + 1 = 11
      expect(sheet.con).to eq(14)
      expect(sheet.dex).to eq(11)
    end

    it 'preserva ratio HP_current quando CON muda por delta racial' do
      svc = described_class.new(character: character,
                                data: { 'raceId' => halfling.id.to_s },
                                force: true)
      svc.call
      sheet.reload

      # Ratio inicial era 1.0 (12/12); deve manter mesmo se hp_max for recomputado.
      ratio = sheet.hp_current.to_f / sheet.hp_max
      expect(ratio).to be_within(0.05).of(1.0)
    end

    it 'sem trocar raca, so atualiza summary mas mantem race_bonuses estaveis' do
      sheet.update!(metadata: sheet.metadata.merge('race_bonuses_applied' => { 'con' => 2 }))
      old_str = sheet.str
      svc = described_class.new(character: character, data: { 'raceChoices' => {} })
      svc.call
      sheet.reload
      expect(sheet.str).to eq(old_str)
    end
  end

  describe 'ZE2 — recompute hp_max em troca de sub-raca com delta CON' do
    let(:sub_mountain) { create(:sub_race, race: dwarf, name: 'Anao da Montanha', api_index: 'mountain_dwarf') }
    let(:sub_hill) { create(:sub_race, race: dwarf, name: 'Anao da Colina', api_index: 'hill_dwarf') }

    before do
      sheet.update!(sub_race: sub_mountain)
      # Setup: dwarf base + sub_mountain dao CON+2 (totalizando con=16 nas colunas).
      # Trocar para sub_hill (sem CON, mas com SAB+1) deve:
      #   1. sync_ability_columns_from_metadata! recalcular CON = base 14 + race 0 = 14
      #   2. ZE2 detectar sheet.con (14) != old_con (16) e disparar recompute_hp_max!
      allow(RaceRules).to receive(:apply) do |args|
        if args[:subrace_id].to_s.include?('hill') || args[:subrace_id].to_s.include?('colina')
          { speed: 25, languages: %w[Comum Anao], proficiencies: {}, darkvision: 60, ability: { type: 'fixed', increases: [{ ability: 'WIS', amount: 1 }] }, traits: [], innate_spells: [], requires: [] }
        else
          { speed: 25, languages: %w[Comum Anao], proficiencies: {}, darkvision: 60, ability: { type: 'fixed', increases: [{ ability: 'CON', amount: 2 }] }, traits: [], innate_spells: [], requires: [] }
        end
      end
      allow(dwarf).to receive(:base_traits).and_return([])
      allow(Race).to receive(:find_by).and_call_original
      allow(Race).to receive(:find_by).with(id: dwarf.id).and_return(dwarf)
    end

    it 'recomputa hp_max quando troca SUB-RACE muda CON (mesma race)' do
      old_hp_max = sheet.hp_max
      old_con = sheet.con

      svc = described_class.new(character: character.reload,
                                data: { 'subraceId' => sub_hill.id.to_s })
      svc.call
      sheet.reload

      expect(sheet.sub_race_id).to eq(sub_hill.id)
      expect(sheet.con).not_to eq(old_con) # CON realmente mudou
      # hp_max recomputado refletindo novo CON. Como CON caiu (16->14 -> mod 3->2),
      # o hp_max nivel 1 cai de (8+3)=11 para (8+2)=10 (factory hit_die=8 default).
      expect(sheet.hp_max).not_to eq(old_hp_max)
    end

    it 'preserva ratio HP_current ao recomputar via sub-race' do
      sheet.update!(hp_current: sheet.hp_max / 2)
      old_ratio = sheet.hp_current.to_f / sheet.hp_max

      svc = described_class.new(character: character.reload,
                                data: { 'subraceId' => sub_hill.id.to_s })
      svc.call
      sheet.reload

      new_ratio = sheet.hp_current.to_f / sheet.hp_max
      expect(new_ratio).to be_within(0.1).of(old_ratio)
    end
  end

  describe '#read featId (B2.1 complementar)' do
    it 'devolve featId do Variant Human persistido em race_choices' do
      sheet.update!(metadata: sheet.metadata.merge('race_choices' => {
        'variantHumanASI' => { 'mode' => 'feat', 'featId' => 'observador' }
      }))
      out = described_class.new(character: character.reload, data: {}).read
      expect(out['featId']).to eq('observador')
    end

    it 'devolve nil quando nao ha feat racial' do
      out = described_class.new(character: character.reload, data: {}).read
      expect(out['featId']).to be_nil
    end
  end
end
