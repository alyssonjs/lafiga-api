# frozen_string_literal: true

require 'rails_helper'

# BDD: Bug "Perito + Humano Variante não propaga perícias para a ficha".
# ---------------------------------------------------------------------------
# Reportado: usuário cria personagem Humano Variante, escolhe o talento
# `Perito` no slot da raça e seleciona 3 perícias/ferramentas (ex.: Arcanismo,
# Investigação, Utensílios de Cozinheiro). Na ficha completa, Arcanismo e
# Investigação aparecem SEM o check de proficiência (mesmo nível de não-prof).
#
# Hipótese: provisionamento chama `FeatAssignmentService` mas o
# `metadata['feats'][i]['proficiency_bonuses']` termina com a estrutura RAW
# (`{skills_or_tools: {choose: {...}}}`) em vez do resolvido
# (`{skills: [...], tools: [...]}`). O `CharacterSheetSummaryService` então
# lê `pb['skills']` (vazio) e nada vai para `proficiencies.skills.feat`.
#
# Estes specs reproduzem o cenário ponta-a-ponta. Após o fix, devem ficar
# todos verdes — incluindo o agregador.
RSpec.describe 'Perito + Humano Variante: propagação de perícias para a ficha', type: :service do
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

  # Garante o feat `perito` no DB com a estrutura canônica
  # (skills_or_tools.choose.amount=3). Sem isso, FeatRules.find via DB pode
  # devolver hash sem o nó esperado.
  let!(:perito_feat) do
    Feat.find_or_create_by!(api_index: 'perito') do |f|
      f.name = 'Perito'
      f.description = 'Versatilidade em perícias e ferramentas.'
      f.prerequisites = '{}'
      f.ability_bonuses = '{}'
      f.proficiency_bonuses = {
        'skills_or_tools' => {
          'choose' => {
            'amount' => 3,
            'options' => ['qualquer perícia ou ferramenta']
          }
        }
      }.to_json
      f.features = { name: 'Treinamento Amplo', desc: 'Proficiência em três perícias e/ou ferramentas à escolha.' }.to_json
    end
  end

  before { RaceRules.reload! }

  # Payload idêntico ao que o front envia: `wizard.race.raceChoices.variantHumanASI`
  # carrega { mode: 'feat', featId: 'perito', choices: { skillsAndTools: [...], ability: '...' } }.
  let(:payload) do
    {
      character: { name: "PeritoBug #{SecureRandom.hex(3)}", background: bg.name },
      wizard: {
        meta: { name: 'PeritoBug', alignmentKey: align.api_index },
        race: {
          raceId: human_race.id,
          subRaceId: variant_subrace.id,
          ruleId: 'human',
          subRuleId: 'variant',
          attributes: { str: 14, dex: 14, con: 14, int: 13, wis: 12, cha: 10 },
          baseAttributes: { str: 14, dex: 13, con: 14, int: 13, wis: 12, cha: 10 },
          abilityBonuses: { dex: 1, cha: 1 },
          raceChoices: {
            'chosenLanguages' => ['Élfico'],
            'chosenSkills' => ['Sobrevivência'], # perícia extra do Variant Human
            'chosenAbilities' => ['DEX', 'CHA'],
            'variantHumanASI' => {
              'mode' => 'feat',
              'featId' => 'perito',
              'choices' => {
                'skillsAndTools' => ['Arcanismo', 'Investigação', 'Utensílios de Cozinheiro']
              }
            }
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

  describe 'metadata.feats[].proficiency_bonuses depois do provisionamento' do
    it 'PROVA do bug: pb deve estar resolvido em {skills:[…], tools:[…]} e não no formato RAW' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true), -> { cmd.errors.full_messages.join('; ') rescue cmd.inspect }

      sheet = Sheet.order(:id).last
      feats = Array(sheet.metadata['feats'])
      perito = feats.find { |f| f['feat_id'] == 'perito' }

      expect(perito).to be_present, "metadata.feats deveria conter entrada do Perito. Veio: #{feats.inspect}"

      pb = perito['proficiency_bonuses'] || {}

      # Estrutura ESPERADA pós-resolução:
      expect(pb['skills']).to eq(['Arcanismo', 'Investigação']),
        "proficiency_bonuses.skills deveria ter ['Arcanismo','Investigação']. " \
        "Veio: #{pb.inspect}"
      expect(pb['tools']).to eq(['Utensílios de Cozinheiro']),
        "proficiency_bonuses.tools deveria ter ['Utensílios de Cozinheiro']. " \
        "Veio: #{pb.inspect}"

      # E NUNCA deve manter a forma RAW da regra (que é o sintoma do bug).
      expect(pb).not_to have_key('skills_or_tools'),
        "proficiency_bonuses não pode manter o nó RAW 'skills_or_tools'. " \
        "Veio: #{pb.inspect}"
    end
  end

  describe 'CharacterSheetSummaryService — proficiencies.skills.feat' do
    it 'inclui as 2 perícias escolhidas no Perito (Arcanismo, Investigação)' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last

      summary = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false)
      expect(summary.success?).to be(true)

      feat_skills = Array(summary.result.dig(:proficiencies, :skills, :feat)).map(&:to_s)
      expect(feat_skills).to include('Arcanismo', 'Investigação'),
        "Summary deve expor as 2 perícias do Perito em proficiencies.skills.feat. " \
        "Veio: #{feat_skills.inspect}"
    end

    it 'inclui a ferramenta escolhida no Perito (Utensílios de Cozinheiro) em proficiencies.tools' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last

      summary = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false)
      tools = Array(summary.result.dig(:proficiencies, :tools)).map(&:to_s)
      expect(tools).to include('Utensílios de Cozinheiro'),
        "Summary deve expor 'Utensílios de Cozinheiro' em proficiencies.tools. " \
        "Veio: #{tools.inspect}"
    end
  end

  # =====================================================================
  # CENÁRIO LEGADO: personagens provisionados ANTES do commit 6e046c5
  # (2026-04-28) têm `metadata.feats[i].proficiency_bonuses` no formato RAW
  # (`{skills_or_tools: {choose: ...}}`) porque `FeatRules.apply` antigo
  # não resolvia esse nó. Forçar re-provisionamento de todas as fichas é
  # custoso — então o aggregator agora tem fallback que lê
  # `f.choices.skillsAndTools` quando detecta pb raw.
  # =====================================================================
  describe 'CharacterSheetSummaryService — fallback para metadata.feats LEGADO' do
    it 'agrega Arcanismo/Investigação mesmo com pb RAW (skills_or_tools), lendo choices.skillsAndTools' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last

      # Simula metadata legado: pb no formato raw, choices preenchidos.
      meta = sheet.metadata.deep_dup
      feats = Array(meta['feats'])
      perito = feats.find { |f| f['feat_id'] == 'perito' }
      expect(perito).to be_present
      perito['proficiency_bonuses'] = {
        'skills_or_tools' => {
          'choose' => { 'amount' => 3, 'options' => ['qualquer perícia ou ferramenta'] }
        }
      }
      meta['feats'] = feats
      sheet.update!(metadata: meta)

      summary = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false)
      expect(summary.success?).to be(true)

      feat_skills = Array(summary.result.dig(:proficiencies, :skills, :feat)).map(&:to_s)
      expect(feat_skills).to include('Arcanismo', 'Investigação'),
        "Aggregator deve fazer fallback para choices.skillsAndTools quando pb está em formato raw legacy. " \
        "Veio: #{feat_skills.inspect}"

      tools = Array(summary.result.dig(:proficiencies, :tools)).map(&:to_s)
      expect(tools).to include('Utensílios de Cozinheiro'),
        "Tools fallback também. Veio: #{tools.inspect}"
    end
  end

  describe 'AUDIT: FeatRules.apply isolado (sanity check)' do
    it 'resolve skills_or_tools quando proficiency_bonuses tem chaves STRING (formato DB)' do
      # Garante que a resolução funcione mesmo com hash de chaves string,
      # que é como o YAML/DB chega via parse_jsonish.
      rule = FeatRules.find('perito')
      expect(rule[:proficiency_bonuses]).to be_present

      result = FeatRules.apply('perito', { 'skillsAndTools' => ['Arcanismo', 'Investigação', 'Utensílios de Cozinheiro'] })
      pb = result[:proficiency_bonuses]
      expect(pb['skills'] || pb[:skills]).to eq(['Arcanismo', 'Investigação'])
      expect(pb['tools']  || pb[:tools]).to eq(['Utensílios de Cozinheiro'])
    end
  end
end
