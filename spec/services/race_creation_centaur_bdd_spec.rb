# frozen_string_literal: true

require 'rails_helper'

# BDD: Criação de personagem com a raça Centauro (HOUSERULES Lafiga)
# -------------------------------------------------------------------
# FONTE CANÔNICA: `~/Documents/MF/Atualizacao_das_Racas.pdf` (campanha Lafiga, p. 1).
# Não é PHB puro — é uma extensão local. Sem sub-raças.
#
# Regras (PDF Lafiga, p. 1):
#   - Médio (~2,50m), 12 m (40 ft), sem darkvision
#   - ASI: +2 STR, +1 WIS
#   - Idiomas: Comum, Silvestre
#   - Sobrevivente: proficiência em Sobrevivência (fixa)
#   - Carga: 1x SR/LR — dobra o dado da arma após mover-se 6m em linha reta
#   - Cascos: 1d6 contundente + STR (arma natural)
#   - Corpo Equino: categoria de carga maior, vantagem em STR(Atletismo) p/
#     puxar/empurrar, escalada com mãos é difícil (+6m por 1,5m), pode ser
#     montado por uma criatura Média ou menor
#   - Natureza Híbrida: Humanoide e Monstruosidade
#
# YAML (`api/config/race_rules.yml:59-78`):
#   - speed 40, ASI [STR+2, WIS+1], langs always [Comum, Silvestre]
#   - skills.fixed: [Sobrevivência]
#   - traits: centaur_charge, hooves_1d6_strike, equine_build, hybrid_nature_hum_monstr
RSpec.describe 'Criação de Personagem Centauro (Houserules Lafiga)', type: :service do
  let(:user) { create(:user) }

  let!(:centaur_race) do
    Race.find_or_create_by!(api_index: 'centaur') { |r| r.name = 'Centauro' }
  end

  let!(:klass) do
    Klass.find_or_create_by!(api_index: 'ranger') do |k|
      k.name = 'Patrulheiro'; k.hit_die = 10; k.subclass_level = 3
    end
  end

  let!(:bg) do
    Background.find_or_create_by!(api_index: 'outlander') do |b|
      b.name = 'Forasteiro'; b.feature_name = 'Errante'; b.feature_desc = 'Spec'
    end
  end

  let!(:align) do
    Alignment.find_or_create_by!(api_index: 'n') { |a| a.name = 'Neutro' }
  end

  # Base 13/12/12/10/13/10. Centauro = +STR 2, +WIS 1 → 15/12/12/10/14/10.
  def base_attrs
    { str: 13, dex: 12, con: 12, int: 10, wis: 13, cha: 10 }
  end

  def post_racial
    base_attrs.merge(str: base_attrs[:str] + 2, wis: base_attrs[:wis] + 1)
  end

  def build_payload
    {
      character: { name: "Spec Centaur #{SecureRandom.hex(3)}", background: bg.name },
      wizard: {
        meta: { name: 'Spec Centaur', alignmentKey: align.api_index },
        race: {
          raceId: centaur_race.id,
          subRaceId: nil,
          ruleId: 'centaur',
          subRuleId: nil,
          attributes: post_racial,
          raceChoices: {}
        },
        klass: {
          klassId: klass.id,
          level: 1,
          classSkillPicks: %w[Percepção Natureza],
          classPicksByLevel: { '1' => { 'hp' => { 'dieResult' => 10, 'total' => 11, 'method' => 'average' } } }
        },
        background: { backgroundName: bg.name, backgroundKey: bg.api_index },
        equipment: {},
        avatar: { customization: {} }
      }
    }
  end

  before { RaceRules.reload! }

  # =====================================================================
  #  Provisioning
  # =====================================================================
  describe 'CharacterProvisioningService — Centauro' do
    let(:payload) { build_payload }

    it 'persiste race_id, speed=40 (12 m) e idiomas Comum/Silvestre' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true), -> { cmd.errors.full_messages.join('; ') rescue cmd.inspect }
      sheet = Sheet.order(:id).last

      expect(sheet.race_id).to eq(centaur_race.id)
      rs = sheet.race_summary || {}
      expect(rs['speed_ft'].to_i).to eq(40),
        'Centauro: 12 m = 40 ft de deslocamento (PDF Lafiga p. 1).'
      langs = Array(rs['languages']).map(&:to_s)
      expect(langs).to include('Comum', 'Silvestre')
      expect(langs.size).to eq(2)
    end

    it 'reflete +2 STR e +1 WIS nas colunas' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      expect(sheet.str).to eq(base_attrs[:str] + 2)
      expect(sheet.wis).to eq(base_attrs[:wis] + 1)
      # Outros não recebem bônus.
      expect(sheet.dex).to eq(base_attrs[:dex])
      expect(sheet.con).to eq(base_attrs[:con])
      expect(sheet.int).to eq(base_attrs[:int])
      expect(sheet.cha).to eq(base_attrs[:cha])
    end

    it 'persiste perícia Sobrevivência (Sobrevivente, PDF p. 1) em race_summary' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      skills_block = sheet.race_summary.dig('proficiencies', 'skills')
      fixed = skills_block.is_a?(Hash) ? Array(skills_block['fixed']) : Array(skills_block)
      expect(fixed).to include('Sobrevivência')
    end

    it 'CharacterSheetSummaryService inclui Sobrevivência em proficiencies.skills.race' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last

      summary = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false)
      expect(summary.success?).to be(true)
      race_skills = Array(summary.result.dig(:proficiencies, :skills, :race)).map(&:to_s)
      expect(race_skills).to include('Sobrevivência')
    end
  end

  # =====================================================================
  #  RaceProfileService
  # =====================================================================
  describe 'RaceProfileService — leitura derivada' do
    it 'devolve speed=40 (acima da base humana de 30) e SEM darkvision' do
      cmd = CharacterProvisioningService.call(user: user, payload: build_payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last

      profile = RaceProfileService.new(sheet).call
      expect(profile[:speed_ft]).to eq(40)
      expect(profile[:darkvision].to_i).to eq(0),
        'Centauro não tem darkvision no PDF Lafiga.'
    end
  end

  # =====================================================================
  #  RaceRules.apply — contrato canônico
  # =====================================================================
  describe 'RaceRules.apply — contrato canônico do Centauro' do
    it 'speed=40, ASI STR+2/WIS+1, idiomas Comum/Silvestre' do
      applied = RaceRules.apply(race_id: 'centaur', subrace_id: nil, choices: {})
      expect(applied[:speed]).to eq(40)
      expect(applied[:languages]).to include('Comum', 'Silvestre')

      ability = applied[:ability] || {}
      increases = ability[:increases] || ability['increases'] || []
      pairs = increases.map { |e| [(e[:ability] || e['ability']).to_s, (e[:amount] || e['amount']).to_i] }
      expect(pairs).to include(['STR', 2], ['WIS', 1])
    end

    it 'traits incluem centaur_charge, hooves_1d6_strike, equine_build, hybrid_nature' do
      applied = RaceRules.apply(race_id: 'centaur', subrace_id: nil, choices: {})
      keys = Array(applied[:traits]).map { |t| t[:key] || t['key'] }
      expect(keys).to include(
        'centaur_charge',
        'hooves_1d6_strike',
        'equine_build',
        'hybrid_nature_hum_monstr'
      )
    end

    it 'NÃO tem darkvision (PDF Lafiga p. 1 omite explicitamente)' do
      applied = RaceRules.apply(race_id: 'centaur', subrace_id: nil, choices: {})
      expect(applied[:darkvision]).to be_blank
    end
  end
end
