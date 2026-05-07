# frozen_string_literal: true

require 'rails_helper'

# DIAGNÓSTICO de 2 bugs reportados pelo usuário em Humano Variante:
#
# Bug A — "Lidar com Animais" escolhida no step de raça aparece em
#         "Perícias da Raça (Já adquiridas)" no step de skills, mas
#         NÃO aparece marcada na ficha final do personagem.
#
# Bug B — Aba do Humano Variante na seção de raças mostra UI para feat
#         e perícia, mas NÃO mostra a opção de escolher o idioma extra
#         (que é da raça Humano base, choiceCount: 1).
#
# Estes specs documentam o estado atual e devem evidenciar onde o bug
# acontece. Após o fix, eles devem virar verde.
#
# IMPORTANT: Nome canônico da perícia em `config/skills.yml` é
# "Lidar com Animais" (não "Adestrar Animais"). Se o front usar o
# segundo nome em algum lugar, há divergência de naming a corrigir.
RSpec.describe 'Bugs Humano Variante (DIAGNÓSTICO)', type: :service do
  let(:user) { create(:user) }

  let!(:human_race) do
    Race.find_or_create_by!(api_index: 'human') { |r| r.name = 'Humano' }
  end

  let!(:variant_subrace) do
    SubRace.find_or_create_by!(race_id: human_race.id, api_index: 'variant') do |s|
      s.name = 'Humano Variante'
    end
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

  let!(:align) { Alignment.find_or_create_by!(api_index: 'lg') { |a| a.name = 'Leal e Bom' } }

  before { RaceRules.reload! }

  # =====================================================================
  #  Bug A — "Lidar com Animais" não aparece na ficha
  # =====================================================================
  describe 'Bug A — perícia "Lidar com Animais" escolhida pela raça' do
    let(:payload) do
      {
        character: { name: "DiagBugA #{SecureRandom.hex(3)}", background: bg.name },
        wizard: {
          meta: { name: 'DiagBugA', alignmentKey: align.api_index },
          race: {
            raceId: human_race.id,
            subRaceId: variant_subrace.id,
            ruleId: 'human',
            subRuleId: 'variant',
            attributes: { str: 14, dex: 13, con: 14, int: 8, wis: 13, cha: 9 },
            raceChoices: {
              'chosenLanguages' => ['Élfico'],
              'chosenSkills' => ['Lidar com Animais'],
              'variantHumanASI' => { 'mode' => 'feat', 'featId' => 'observador', 'choices' => {} }
            }
          },
          klass: {
            klassId: klass.id, level: 1,
            classSkillPicks: %w[Atletismo Percepção],
            classPicksByLevel: { '1' => { 'hp' => { 'dieResult' => 10, 'total' => 13, 'method' => 'average' } } }
          },
          background: { backgroundName: bg.name, backgroundKey: bg.api_index },
          equipment: {},
          avatar: { customization: {} }
        }
      }
    end

    it 'AUDIT: nome canônico em config/skills.yml é "Lidar com Animais" (não "Adestrar Animais")' do
      yaml_path = Rails.root.join('config', 'skills.yml')
      raw = YAML.safe_load(yaml_path.read, aliases: true)
      names = Array(raw['skills']).map { |s| s['name'] }
      expect(names).to include('Lidar com Animais'),
        "skills.yml deve declarar 'Lidar com Animais' como nome canônico (PHB)."
      expect(names).not_to include('Adestrar Animais'),
        "skills.yml NÃO deve usar 'Adestrar Animais' (nome alternativo). " \
        "Atual: #{names.inspect}"
    end

    it 'metadata.race_choices.chosenSkills preserva o nome exato escolhido' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true), -> { cmd.errors.full_messages.join('; ') rescue cmd.inspect }
      sheet = Sheet.order(:id).last

      rc = (sheet.metadata || {})['race_choices'] || {}
      expect(Array(rc['chosenSkills'])).to eq(['Lidar com Animais']),
        "metadata deve persistir EXATAMENTE 'Lidar com Animais', sem transformação. " \
        "Veio: #{rc['chosenSkills'].inspect}"
    end

    it 'CharacterSheetSummaryService inclui "Lidar com Animais" em proficiencies.skills.race' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last

      summary = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false)
      expect(summary.success?).to be(true)
      race_skills = Array(summary.result.dig(:proficiencies, :skills, :race)).map(&:to_s)
      expect(race_skills).to include('Lidar com Animais'),
        "Summary deve expor 'Lidar com Animais' em proficiencies.skills.race. " \
        "Veio: race=#{race_skills.inspect}"
    end

    # Se este spec falhar, há transformação backend que está renomeando
    # 'Lidar com Animais' → 'Adestrar Animais' (ou vice-versa) em algum lugar.
    it 'NÃO há transformação Lidar↔Adestrar — naming preservado em todo o pipeline' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last

      summary = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false)
      race_skills = Array(summary.result.dig(:proficiencies, :skills, :race)).map(&:to_s)

      expect(race_skills).not_to include('Adestrar Animais'),
        "Backend não deve normalizar 'Lidar com Animais' para 'Adestrar Animais'. " \
        "Veio: #{race_skills.inspect}"
    end
  end

  # =====================================================================
  #  Bug B — Idioma extra do Humano Variante ausente na UI
  # =====================================================================
  describe 'Bug B — idioma extra do Humano Variante' do
    it 'YAML race.languages declara choiceCount=1 e choiceList no NÍVEL DA RAÇA BASE' do
      human = RaceRules.find('human')
      langs = human[:languages] || human['languages']

      expect(langs[:choiceCount] || langs['choiceCount']).to eq(1),
        "Humano base deve declarar choiceCount=1 (PHB: 'Idiomas. Comum + 1 extra à escolha')."

      choice_list = Array(langs[:choiceList] || langs['choiceList']).map(&:to_s)
      expect(choice_list).to include('Anão', 'Élfico', 'Halfling', 'Dracônico', 'Gnômico', 'Orc', 'Infernal'),
        'choiceList deve cobrir os 7 idiomas comuns do PHB.'
    end

    it 'YAML subraces.variant NÃO sobrescreve languages (herda da raça base)' do
      human = RaceRules.find('human')
      variant = human.dig(:subraces, :variant) || human.dig('subraces', 'variant')
      expect(variant).to be_present
      # Sub-raça `variant` no YAML não declara `languages:` — herda da base via deep_merge.
      expect(variant[:languages] || variant['languages']).to be_nil,
        "Sub-raça 'variant' deve NÃO declarar languages própria; o merge com a " \
        "raça base aplica choiceCount=1 automaticamente. Atual: #{(variant[:languages] || variant['languages']).inspect}"
    end

    it 'RaceRules.apply expõe language_choices_required quando há pick pendente' do
      applied = RaceRules.apply(race_id: 'human', subrace_id: 'variant', choices: {})

      # `apply[:languages]` é o array final (resolvido). Sem extraLanguages,
      # retorna ['Comum'] — mas agora o `language_choices_required` declara
      # explicitamente que falta 1 pick e quais são as opções.
      expect(applied[:languages]).to eq(['Comum'])

      lcr = applied[:language_choices_required]
      expect(lcr).to be_present,
        'apply deve expor language_choices_required para o Variant Human quando ' \
        'extraLanguages está vazio. Sem isso, a UI do front fica cega.'
      expect(lcr[:count]).to eq(1)
      expect(lcr[:options]).to include('Anão', 'Élfico', 'Halfling', 'Dracônico', 'Gnômico', 'Orc', 'Infernal')
      expect(lcr[:chosen]).to eq([])
      expect(lcr[:remaining]).to eq(1)
    end

    it 'language_choices_required reflete pick parcial (1 escolhido / 1 ainda pendente quando count for maior)' do
      # Cenário hipotético: count=2, escolheu 1 ainda. Em humano é só 1, mas
      # o contrato vale para qualquer raça (Meio-Elfo também tem choiceCount=1).
      applied = RaceRules.apply(
        race_id: 'human', subrace_id: 'variant',
        choices: { extraLanguages: ['Élfico'] }
      )
      expect(applied[:languages]).to include('Comum', 'Élfico')

      lcr = applied[:language_choices_required]
      expect(lcr[:count]).to eq(1)
      expect(lcr[:chosen]).to eq(['Élfico'])
      expect(lcr[:remaining]).to eq(0)
    end

    it 'NÃO expõe language_choices_required quando raça não tem choice (ex.: Anão, choiceCount=0)' do
      applied = RaceRules.apply(race_id: 'dwarf', subrace_id: 'hill', choices: {})
      expect(applied[:language_choices_required]).to be_nil,
        'Anão tem languages.choiceCount=0; não deve expor language_choices_required.'
    end
  end
end
