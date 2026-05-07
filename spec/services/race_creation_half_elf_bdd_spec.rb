# frozen_string_literal: true

require 'rails_helper'

# BDD: Criação de personagem com a raça Meio-Elfo (Half-Elf, PHB)
# ----------------------------------------------------------------
# Regras (`api/config/race_rules.yml`):
#
#   Meio-Elfo (sem sub-raças no YAML):
#     - Médio, 30 ft, darkvision 60
#     - Idiomas: Comum, Élfico + 1 idioma extra à escolha (choiceCount: 1)
#     - ASI tipo "halfElf":
#         * +2 CHA fixo
#         * +1 em DOIS atributos diferentes à escolha (que NÃO sejam CHA)
#     - Perícias: 2 à escolha entre TODAS as perícias do PHB (Skill Versatility)
#     - Traits: fey_ancestry, darkvision, skill_versatility
#
# Meio-Elfo é a raça PHB MAIS RICA em escolhas: 1 idioma + 2 perícias + 2
# atributos (+1 cada), além do +2 CHA fixo. O front envia tudo no `attributes`
# já totalizado e usa `raceChoices.chosenLanguages` / `raceChoices.chosenSkills`
# para auditoria/persistência.
RSpec.describe 'Criação de Personagem Meio-Elfo (BDD PHB)', type: :service do
  let(:user) { create(:user) }

  let!(:half_elf_race) do
    Race.find_or_create_by!(api_index: 'half_elf') { |r| r.name = 'Meio-Elfo' }
  end

  # YAML não declara sub-raças para Meio-Elfo, mas o factory de Sheet exige
  # `sub_race` da mesma race do sheet (validação do model). Para o teste do
  # provisioning isso não importa porque CPS aceita sub_race_id nil. Para o
  # StepRace, o sub_race_id pode ser nil também.

  let!(:klass) do
    Klass.find_or_create_by!(api_index: 'bard') do |k|
      k.name = 'Bardo'; k.hit_die = 8; k.subclass_level = 3
    end
  end

  let!(:bg) do
    Background.find_or_create_by!(api_index: 'entertainer') do |b|
      b.name = 'Artista'; b.feature_name = 'Por Demanda Popular'; b.feature_desc = 'Spec'
    end
  end

  let!(:align) do
    Alignment.find_or_create_by!(api_index: 'cg') { |a| a.name = 'Caótico e Bom' }
  end

  # Base 8/13/12/10/12/13.
  # Meio-Elfo: +2 CHA + +1 em 2 escolhidos (digamos DEX e WIS) →
  # 8 / 14 / 12 / 10 / 13 / 15.
  def base_attrs
    { str: 8, dex: 13, con: 12, int: 10, wis: 12, cha: 13 }
  end

  def post_racial(extra_picks: %i[dex wis])
    h = base_attrs.merge(cha: base_attrs[:cha] + 2)
    extra_picks.each { |k| h[k] = h[k] + 1 }
    h
  end

  def build_payload(race_choices: {}, attributes: nil)
    {
      character: { name: "Spec HalfElf #{SecureRandom.hex(3)}", background: bg.name },
      wizard: {
        meta: { name: 'Spec HalfElf', alignmentKey: align.api_index },
        race: {
          raceId: half_elf_race.id,
          subRaceId: nil,
          ruleId: 'half_elf',
          subRuleId: nil,
          attributes: attributes || post_racial,
          raceChoices: race_choices
        },
        klass: {
          klassId: klass.id,
          level: 1,
          classSkillPicks: %w[Atuação Persuasão],
          classPicksByLevel: { '1' => { 'hp' => { 'dieResult' => 8, 'total' => 9, 'method' => 'average' } } }
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
  describe 'CharacterProvisioningService — Meio-Elfo' do
    let(:payload) do
      build_payload(
        race_choices: {
          'chosenLanguages' => ['Anão'],
          'chosenSkills' => %w[Furtividade Investigação]
        }
      )
    end

    it 'persiste race_id, speed=30, e idiomas Comum/Élfico/<extra>' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true), -> { cmd.errors.full_messages.join('; ') rescue cmd.inspect }
      sheet = Sheet.order(:id).last

      expect(sheet.race_id).to eq(half_elf_race.id)
      rs = sheet.race_summary || {}
      expect(rs['speed_ft'].to_i).to eq(30)
      langs = Array(rs['languages']).map(&:to_s)
      expect(langs).to include('Comum', 'Élfico', 'Anão'),
        "Meio-Elfo: idiomas always (Comum, Élfico) + 1 extra (Anão escolhido); veio #{langs.inspect}"
    end

    it 'reflete +2 CHA + +1 em DEX/WIS (escolhidos) nas colunas' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last

      expect(sheet.cha).to eq(base_attrs[:cha] + 2),
        '+2 CHA é fixo do Meio-Elfo (não muda com escolha do jogador).'
      expect(sheet.dex).to eq(base_attrs[:dex] + 1)
      expect(sheet.wis).to eq(base_attrs[:wis] + 1)
      # STR/CON/INT NÃO escolhidos: ficam na base.
      expect(sheet.str).to eq(base_attrs[:str])
      expect(sheet.con).to eq(base_attrs[:con])
      expect(sheet.int).to eq(base_attrs[:int])
    end

    it 'persiste raceChoices.chosenLanguages e chosenSkills em metadata' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last

      rc = (sheet.metadata || {})['race_choices'] || {}
      expect(Array(rc['chosenLanguages'])).to include('Anão')
      expect(Array(rc['chosenSkills'])).to include('Furtividade', 'Investigação')
    end

    it 'CharacterSheetSummaryService inclui as 2 perícias escolhidas em proficiencies.skills.race' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last

      summary = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false)
      expect(summary.success?).to be(true)
      race_skills = Array(summary.result.dig(:proficiencies, :skills, :race)).map(&:to_s)
      expect(race_skills).to include('Furtividade', 'Investigação'),
        'Skill Versatility: as 2 perícias escolhidas pelo Meio-Elfo entram em proficiencies.skills.race.'
    end

    it 'aceita escolha alternativa (STR e CON em vez de DEX/WIS) — flexibilidade do ASI Meio-Elfo' do
      attrs = post_racial(extra_picks: %i[str con])
      cmd = CharacterProvisioningService.call(
        user: user,
        payload: build_payload(
          attributes: attrs,
          race_choices: { 'chosenLanguages' => ['Halfling'], 'chosenSkills' => %w[Atletismo Sobrevivência] }
        )
      )
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last

      expect(sheet.cha).to eq(base_attrs[:cha] + 2)
      expect(sheet.str).to eq(base_attrs[:str] + 1),
        'Jogador escolheu STR como um dos +1; coluna deve refletir.'
      expect(sheet.con).to eq(base_attrs[:con] + 1)
      expect(sheet.dex).to eq(base_attrs[:dex])
    end
  end

  # =====================================================================
  #  RaceRules.apply — contrato canônico do YAML
  # =====================================================================
  describe 'RaceRules.apply — contrato canônico do Meio-Elfo' do
    it 'tipo halfElf: +2 CHA fixo + escolha de 2 atributos para +1' do
      applied = RaceRules.apply(race_id: 'half_elf', subrace_id: nil, choices: {})
      expect(applied[:speed]).to eq(30)
      expect(applied[:darkvision]).to be_present

      ability = applied[:ability] || {}
      type = ability[:type] || ability['type']
      expect(type.to_s).to eq('halfElf')

      fixed = ability[:fixed] || ability['fixed'] || []
      cha_entry = Array(fixed).find { |e| (e[:ability] || e['ability']).to_s.upcase == 'CHA' }
      expect(cha_entry).to be_present
      expect((cha_entry[:amount] || cha_entry['amount']).to_i).to eq(2)

      choose = ability[:choose] || ability['choose'] || {}
      expect((choose[:count] || choose['count']).to_i).to eq(2)
      expect((choose[:amount] || choose['amount']).to_i).to eq(1)
    end

    it 'declara skill choice count=2 entre TODAS as perícias (Skill Versatility)' do
      applied = RaceRules.apply(race_id: 'half_elf', subrace_id: nil, choices: {})
      profs = applied[:proficiencies] || {}
      skills = profs[:skills] || profs['skills'] || {}
      count = skills[:choiceCount] || skills['choiceCount']
      choices = skills[:choices] || skills['choices'] || []

      expect(count.to_i).to eq(2)
      expect(Array(choices).size).to be >= 17,
        "Skill Versatility deve aceitar entre todas as 18 perícias do PHB; veio #{Array(choices).size}"
    end

    it 'idioma always: Comum + Élfico, choiceCount 1' do
      applied = RaceRules.apply(race_id: 'half_elf', subrace_id: nil, choices: {})
      expect(applied[:languages]).to include('Comum', 'Élfico')
    end

    it 'traits incluem fey_ancestry, darkvision, skill_versatility' do
      applied = RaceRules.apply(race_id: 'half_elf', subrace_id: nil, choices: {})
      keys = Array(applied[:traits]).map { |t| t[:key] || t['key'] }
      expect(keys).to include('fey_ancestry', 'darkvision', 'skill_versatility')
    end
  end

  # =====================================================================
  #  GAPs do sistema
  # =====================================================================
  describe 'CPS persiste darkvision em race_summary' do
    it 'darkvision=60 para Meio-Elfo' do
      cmd = CharacterProvisioningService.call(
        user: user,
        payload: build_payload(race_choices: { 'chosenLanguages' => ['Anão'] })
      )
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      expect((sheet.race_summary || {})['darkvision'].to_i).to eq(60)
    end
  end
end
