# frozen_string_literal: true

require 'rails_helper'

# BDD: Criação de personagem com a raça Minotauro (HOUSERULES Lafiga)
# --------------------------------------------------------------------
# FONTE CANÔNICA: `~/Documents/MF/Atualizacao_das_Racas.pdf` (campanha Lafiga, p. 1-2).
# Não é PHB puro — é uma extensão local. Sem sub-raças.
#
# Regras (PDF Lafiga, p. 1-2):
#   - Médio (~2,70m, "limite para o Médio"), 9 m (30 ft), sem darkvision
#   - ASI: +2 STR, +1 CON
#   - Idiomas: Comum, Minotauro
#   - Chifres: 1d6 perfurante + STR (arma natural)
#   - Arremetida Escornada: após Disparar, ataque bônus com chifres + ST de
#     STR (CD = 8 + Mod STR + Prof) — alvo cai
#   - Batedura de Chifres: reação após acertar c-a-c na ação Atacar — empurra
#     1,5m (ST de STR, mesma CD)
#   - Ameaçador: proficiência em Intimidação (fixa)
#   - Natureza Híbrida: Humanoide + Monstruosidade
#
# YAML (`api/config/race_rules.yml:510-530`):
#   - speed 30, ASI [STR+2, CON+1], langs always [Comum, Minotauro]
#   - skills.fixed: [Intimidação]   ← alinhado ao PDF Lafiga ("Ameaçador" fixo)
#   - traits: minotaur_horns_1d6, goring_rush, hammering_horns, hybrid_nature
RSpec.describe 'Criação de Personagem Minotauro (Houserules Lafiga)', type: :service do
  let(:user) { create(:user) }

  let!(:minotaur_race) do
    Race.find_or_create_by!(api_index: 'minotaur') { |r| r.name = 'Minotauro' }
  end

  let!(:klass) do
    Klass.find_or_create_by!(api_index: 'fighter') do |k|
      k.name = 'Guerreiro'; k.hit_die = 10; k.subclass_level = 3
    end
  end

  let!(:bg) do
    Background.find_or_create_by!(api_index: 'soldier') do |b|
      b.name = 'Soldado'; b.feature_name = 'Patente Militar'; b.feature_desc = 'Spec'
    end
  end

  let!(:align) do
    Alignment.find_or_create_by!(api_index: 'lg') { |a| a.name = 'Leal e Bom' }
  end

  # Base 13/12/13/10/10/8. Minotauro = +STR 2, +CON 1 → 15/12/14/10/10/8.
  def base_attrs
    { str: 13, dex: 12, con: 13, int: 10, wis: 10, cha: 8 }
  end

  def post_racial
    base_attrs.merge(str: base_attrs[:str] + 2, con: base_attrs[:con] + 1)
  end

  def build_payload(race_choices: {})
    {
      character: { name: "Spec Mino #{SecureRandom.hex(3)}", background: bg.name },
      wizard: {
        meta: { name: 'Spec Mino', alignmentKey: align.api_index },
        race: {
          raceId: minotaur_race.id,
          subRaceId: nil,
          ruleId: 'minotaur',
          subRuleId: nil,
          attributes: post_racial,
          raceChoices: race_choices
        },
        klass: {
          klassId: klass.id,
          level: 1,
          classSkillPicks: %w[Atletismo Percepção],
          classPicksByLevel: { '1' => { 'hp' => { 'dieResult' => 10, 'total' => 13, 'method' => 'average' } } }
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
  describe 'CharacterProvisioningService — Minotauro' do
    let(:payload) { build_payload }

    it 'persiste race_id, speed=30 e idiomas Comum/Minotauro' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true), -> { cmd.errors.full_messages.join('; ') rescue cmd.inspect }
      sheet = Sheet.order(:id).last

      expect(sheet.race_id).to eq(minotaur_race.id)
      rs = sheet.race_summary || {}
      expect(rs['speed_ft'].to_i).to eq(30),
        'Minotauro: 9 m = 30 ft (PDF Lafiga p. 1).'
      langs = Array(rs['languages']).map(&:to_s)
      expect(langs).to include('Comum', 'Minotauro')
    end

    it 'reflete +2 STR e +1 CON nas colunas (PDF Lafiga p. 1)' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      expect(sheet.str).to eq(base_attrs[:str] + 2)
      expect(sheet.con).to eq(base_attrs[:con] + 1)
    end

    it 'persiste perícia Intimidação fixa (Ameaçador) em race_summary' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      skills_block = sheet.race_summary.dig('proficiencies', 'skills')
      fixed = skills_block.is_a?(Hash) ? Array(skills_block['fixed']) : Array(skills_block)
      expect(fixed).to include('Intimidação'),
        '"Ameaçador" do PDF Lafiga p. 2: proficiência fixa em Intimidação.'
    end

    it 'CharacterSheetSummaryService inclui Intimidação em proficiencies.skills.race' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last

      summary = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false)
      expect(summary.success?).to be(true)
      race_skills = Array(summary.result.dig(:proficiencies, :skills, :race)).map(&:to_s)
      expect(race_skills).to include('Intimidação')
    end
  end

  # =====================================================================
  #  RaceProfileService
  # =====================================================================
  describe 'RaceProfileService — leitura derivada' do
    it 'devolve speed=30 e SEM darkvision' do
      cmd = CharacterProvisioningService.call(user: user, payload: build_payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      profile = RaceProfileService.new(sheet).call
      expect(profile[:speed_ft]).to eq(30)
      expect(profile[:darkvision].to_i).to eq(0),
        'Minotauro não tem darkvision no PDF Lafiga.'
    end
  end

  # =====================================================================
  #  RaceRules.apply — contrato canônico
  # =====================================================================
  describe 'RaceRules.apply — contrato canônico do Minotauro' do
    it 'speed=30, ASI STR+2/CON+1, langs Comum/Minotauro' do
      applied = RaceRules.apply(race_id: 'minotaur', subrace_id: nil, choices: {})
      expect(applied[:speed]).to eq(30)
      expect(applied[:languages]).to include('Comum', 'Minotauro')

      ability = applied[:ability] || {}
      increases = ability[:increases] || ability['increases'] || []
      pairs = increases.map { |e| [(e[:ability] || e['ability']).to_s, (e[:amount] || e['amount']).to_i] }
      expect(pairs).to include(['STR', 2], ['CON', 1])
    end

    it 'traits incluem chifres, arremetida, batedura e natureza híbrida' do
      applied = RaceRules.apply(race_id: 'minotaur', subrace_id: nil, choices: {})
      keys = Array(applied[:traits]).map { |t| t[:key] || t['key'] }
      expect(keys).to include(
        'minotaur_horns_1d6',
        'goring_rush',
        'hammering_horns',
        'hybrid_nature_hum_monstr'
      )
    end

    it 'YAML expõe skill como FIXA (Intimidação), alinhado ao PDF Lafiga' do
      applied = RaceRules.apply(race_id: 'minotaur', subrace_id: nil, choices: {})
      skills = applied.dig(:proficiencies, :skills) || applied.dig('proficiencies', 'skills') || {}
      fixed = skills[:fixed] || skills['fixed'] || []
      expect(Array(fixed)).to include('Intimidação'),
        'YAML deve ter skills.fixed: [Intimidação] — alinhamento total com "Ameaçador" do PDF Lafiga.'
      # Não deve mais expor como choiceCount/choices:
      expect(skills[:choiceCount] || skills['choiceCount']).to be_nil
    end
  end
end
