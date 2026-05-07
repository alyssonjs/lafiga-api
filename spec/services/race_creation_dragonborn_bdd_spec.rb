# frozen_string_literal: true

require 'rails_helper'

# BDD: Criação de personagem com a raça Draconato (Dragonborn, PHB)
# ------------------------------------------------------------------
# Regras (`api/config/race_rules.yml`):
#
#   Draconato (base):
#     - Médio, 30 ft, SEM darkvision
#     - Idiomas: Comum, Dracônico (sem extra)
#     - ASI: +2 STR, +1 CHA
#     - Sem proficiências raciais base
#     - Sem traits base; cada sub-raça (ancestralidade) define os seus
#
#   Sub-raças = ANCESTRALIDADES dracônicas (definem tipo de dano + sopro):
#     | Cor      | Dano        | Forma               |
#     |----------|-------------|---------------------|
#     | black    | Ácido       | Linha 1,5m × 9m     |
#     | blue     | Relâmpago   | Linha 1,5m × 9m     |
#     | brass    | Fogo        | Linha 1,5m × 9m     |
#     | bronze   | Relâmpago   | Linha 1,5m × 9m     |
#     | copper   | Ácido       | Linha 1,5m × 9m     |
#     | gold     | Fogo        | Cone 4,5m           |
#     | green    | Veneno      | Cone 4,5m           |
#     | red      | Fogo        | Cone 4,5m           |
#     | silver   | Frio        | Cone 4,5m           |
#     | white    | Frio        | Cone 4,5m           |
#
#   Cada ancestralidade concede:
#     - breath_weapon (com damage e breath form do quadro acima)
#     - damage_resistance_from_ancestry (resistência ao mesmo tipo de dano)
#
# Foco deste arquivo: ASI consistente entre todas as 10 ancestralidades,
# tipo de dano correto por cor, e ausência de extras (idioma extra, perícia,
# darkvision) — Draconato é uma raça MAIS SIMPLES em ASI/idiomas, com toda
# a riqueza nas ancestralidades.
RSpec.describe 'Criação de Personagem Draconato (BDD PHB)', type: :service do
  let(:user) { create(:user) }

  let!(:dragonborn_race) do
    Race.find_or_create_by!(api_index: 'dragonborn') { |r| r.name = 'Draconato' }
  end

  ANCESTRIES = {
    'black'  => { name: 'Preto (Ácido)',         damage: 'Ácido',     form: 'linha' },
    'blue'   => { name: 'Azul (Relâmpago)',      damage: 'Relâmpago', form: 'linha' },
    'brass'  => { name: 'Latão (Fogo)',          damage: 'Fogo',      form: 'linha' },
    'bronze' => { name: 'Bronze (Relâmpago)',    damage: 'Relâmpago', form: 'linha' },
    'copper' => { name: 'Cobre (Ácido)',         damage: 'Ácido',     form: 'linha' },
    'gold'   => { name: 'Ouro (Fogo)',           damage: 'Fogo',      form: 'cone'  },
    'green'  => { name: 'Verde (Veneno)',        damage: 'Veneno',    form: 'cone'  },
    'red'    => { name: 'Vermelho (Fogo)',       damage: 'Fogo',      form: 'cone'  },
    'silver' => { name: 'Prata (Frio)',          damage: 'Frio',      form: 'cone'  },
    'white'  => { name: 'Branco (Frio)',         damage: 'Frio',      form: 'cone'  }
  }.freeze

  before(:all) do
    @subraces = {}
    dragonborn = Race.find_or_create_by!(api_index: 'dragonborn') { |r| r.name = 'Draconato' }
    ANCESTRIES.each do |key, info|
      @subraces[key] = SubRace.find_or_create_by!(race_id: dragonborn.id, api_index: key) do |s|
        s.name = info[:name]
      end
    end
  end

  let!(:klass) do
    Klass.find_or_create_by!(api_index: 'paladin') do |k|
      k.name = 'Paladino'; k.hit_die = 10; k.subclass_level = 3
    end
  end

  let!(:bg) do
    Background.find_or_create_by!(api_index: 'noble') do |b|
      b.name = 'Nobre'; b.feature_name = 'Posição de Privilégio'; b.feature_desc = 'Spec'
    end
  end

  let!(:align) do
    Alignment.find_or_create_by!(api_index: 'lg') { |a| a.name = 'Leal e Bom' }
  end

  # Base 13/10/13/10/10/13. Draconato = +2 STR, +1 CHA → 15/10/13/10/10/14.
  def base_attrs
    { str: 13, dex: 10, con: 13, int: 10, wis: 10, cha: 13 }
  end

  def post_racial
    base_attrs.merge(str: base_attrs[:str] + 2, cha: base_attrs[:cha] + 1)
  end

  def build_payload(ancestry:)
    {
      character: { name: "Spec Drac #{ancestry} #{SecureRandom.hex(3)}", background: bg.name },
      wizard: {
        meta: { name: "Spec Drac #{ancestry}", alignmentKey: align.api_index },
        race: {
          raceId: dragonborn_race.id,
          subRaceId: @subraces[ancestry].id,
          ruleId: 'dragonborn',
          subRuleId: ancestry,
          attributes: post_racial,
          raceChoices: {}
        },
        klass: {
          klassId: klass.id,
          level: 1,
          classSkillPicks: %w[Atletismo Persuasão],
          classPicksByLevel: { '1' => { 'hp' => { 'dieResult' => 10, 'total' => 12, 'method' => 'average' } } }
        },
        background: { backgroundName: bg.name, backgroundKey: bg.api_index },
        equipment: {},
        avatar: { customization: {} }
      }
    }
  end

  before { RaceRules.reload! }

  # =====================================================================
  #  StepRace
  # =====================================================================
  describe 'StepRace — wizard draft (uma cor de exemplo: red)' do
    let(:character) { create(:character, user: user, status: :draft) }

    it 'persiste raceId e subraceId Vermelho' do
      svc = CharacterDraftSteps::RaceStepService.new(
        character: character,
        data: { 'raceId' => dragonborn_race.id.to_s, 'subraceId' => @subraces['red'].id.to_s }
      )
      result = svc.call
      expect(result.draft_data.dig('selectedRace', 'id')).to eq(dragonborn_race.id.to_s)
      expect(result.draft_data.dig('selectedSubrace', 'id')).to eq(@subraces['red'].id.to_s)
    end
  end

  # =====================================================================
  #  Provisioning — base do Draconato (verifica via red)
  # =====================================================================
  describe 'CharacterProvisioningService — Draconato (base; verifica via Vermelho)' do
    let(:payload) { build_payload(ancestry: 'red') }

    it 'persiste race_id, sub_race_id, speed=30 e idiomas Comum/Dracônico' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true), -> { cmd.errors.full_messages.join('; ') rescue cmd.inspect }
      sheet = Sheet.order(:id).last

      expect(sheet.race_id).to eq(dragonborn_race.id)
      expect(sheet.sub_race_id).to eq(@subraces['red'].id)
      rs = sheet.race_summary || {}
      expect(rs['speed_ft'].to_i).to eq(30)
      langs = Array(rs['languages']).map(&:to_s)
      expect(langs).to include('Comum', 'Dracônico')
    end

    it 'reflete +2 STR e +1 CHA nas colunas (constante para todas as ancestralidades)' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      expect(sheet.str).to eq(base_attrs[:str] + 2)
      expect(sheet.cha).to eq(base_attrs[:cha] + 1)
      # Outros não recebem bônus.
      expect(sheet.dex).to eq(base_attrs[:dex])
      expect(sheet.con).to eq(base_attrs[:con])
    end

    it 'NÃO concede idioma extra à escolha (Draconato base, choiceCount=0)' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      langs = Array((sheet.race_summary || {})['languages']).map(&:to_s)
      # Apenas os 2 idiomas always: Comum + Dracônico. Sem 3º.
      expect(langs.size).to eq(2)
    end

    it 'race_summary não inclui darkvision (Draconato não tem)' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      expect((sheet.race_summary || {})['darkvision']).to be_blank
    end
  end

  # =====================================================================
  #  Ancestralidades — tabela de damage por cor (RaceRules.apply, fonte canônica)
  # =====================================================================
  describe 'Ancestralidades dracônicas — tipo de dano por cor (PHB)' do
    ANCESTRIES.each do |ancestry, info|
      it "#{ancestry} (#{info[:name]}) → sopro de #{info[:damage]} (#{info[:form]})" do
        applied = RaceRules.apply(race_id: 'dragonborn', subrace_id: ancestry, choices: {})
        traits = Array(applied[:traits])

        breath = traits.find { |t| (t[:key] || t['key']) == 'breath_weapon' }
        expect(breath).to be_present, "Sub-raça #{ancestry} deve definir trait breath_weapon."

        damage = breath[:damage] || breath['damage']
        expect(damage.to_s).to eq(info[:damage]),
          "#{ancestry} deveria ter dano de sopro #{info[:damage]}; veio #{damage.inspect}"

        # Resistência ao mesmo tipo de dano da ancestralidade.
        resist = traits.find { |t| (t[:key] || t['key']) == 'damage_resistance_from_ancestry' }
        expect(resist).to be_present
        expect((resist[:damage] || resist['damage']).to_s).to eq(info[:damage])
      end
    end
  end

  # =====================================================================
  #  Provisioning — verificações por ancestralidade (subset: black/red/green/silver)
  # =====================================================================
  describe 'CharacterProvisioningService — ancestralidades por DB persistido' do
    %w[black red green silver].each do |ancestry|
      info = ANCESTRIES[ancestry]
      it "#{ancestry} (#{info[:name]}): persiste sub_race correto + ASI fixo da raça" do
        cmd = CharacterProvisioningService.call(user: user, payload: build_payload(ancestry: ancestry))
        expect(cmd.success?).to be(true)
        sheet = Sheet.order(:id).last
        expect(sheet.sub_race_id).to eq(@subraces[ancestry].id)
        expect(sheet.race_summary['sub_race_name']).to eq(info[:name])
        # ASI da raça é o mesmo para todas as cores (+2 STR, +1 CHA):
        expect(sheet.str).to eq(base_attrs[:str] + 2)
        expect(sheet.cha).to eq(base_attrs[:cha] + 1)
      end
    end
  end

  # =====================================================================
  #  RaceRules.apply — base (sem ancestralidade) deveria falhar/avisar
  # =====================================================================
  describe 'RaceRules.apply — base canônica do Draconato' do
    it 'base (sem ancestralidade) ainda devolve speed/idiomas/ASI corretos' do
      applied = RaceRules.apply(race_id: 'dragonborn', subrace_id: nil, choices: {})
      expect(applied[:speed]).to eq(30)
      expect(applied[:languages]).to include('Comum', 'Dracônico')
      # `traits: []` na base + nada da sub-raça = traits vazio.
      expect(Array(applied[:traits])).to be_empty
    end
  end
end
