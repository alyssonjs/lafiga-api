# frozen_string_literal: true

require 'rails_helper'

# BDD: Criação de personagem com a raça Humano (PHB)
# ----------------------------------------------------
# Regras (ver `.cursor/dnd-rules/races-catalog.md` e `api/config/race_rules.yml`):
#
#   Humano (base):
#     - Médio, 30 ft, sem darkvision
#     - Idiomas: Comum + 1 idioma à escolha (choiceCount: 1)
#     - Sem proficiências/traits raciais base
#     - Sub-raças:
#         * standard:  +1 em STR, DEX, CON, INT, WIS, CHA (todos)
#         * variant :  +1 em DOIS atributos diferentes à escolha
#                      + 1 perícia à escolha
#                      + 1 talento (feat) à escolha
#
# Estes specs cobrem o pipeline END-TO-END:
#
#   RaceStepService (draft_data persistido durante o wizard) →
#   CharacterProvisioningService (cria a Sheet com race_id/sub_race_id,
#     race_summary, metadata.race_choices, metadata.race_bonuses_applied,
#     metadata.feats e SheetFeat para Variante) →
#   RaceProfileService (lê o snapshot e devolve speed/darkvision/languages) →
#   CharacterSheetSummaryService (proficiencies.skills.race inclui o pick
#     do Variante; languages inclui o idioma extra escolhido)
#
# Coberturas pré-existentes que este arquivo COMPLEMENTA:
#   - race_step_service_spec.rb            (genérico; não cobria Humano)
#   - race_profile_service_spec.rb         (Wood Elf / Drow / Hill Dwarf)
#   - character_provisioning_service_race_summary_spec.rb (Wood Elf / Hill Dwarf)
#   - character_sheet_summary_service_proficiencies_spec.rb (chosenSkills:
#       só verifica que aparece em proficiencies.skills.race; este spec testa
#       o caminho completo via payload do wizard, não meta_overrides)
#   - race_edit_service_spec.rb            (apenas read do featId, sem create)
RSpec.describe 'Criação de Personagem Humano (BDD PHB)', type: :service do
  let(:user) { create(:user) }

  # --- Catálogo mínimo (Race/SubRace/Klass/Background/Alignment) ----------
  let!(:human_race) do
    Race.find_or_create_by!(api_index: 'human') { |r| r.name = 'Humano' }
  end

  let!(:standard_subrace) do
    SubRace.find_or_create_by!(race_id: human_race.id, api_index: 'standard') do |s|
      s.name = 'Humano Padrão'
    end
  end

  let!(:variant_subrace) do
    SubRace.find_or_create_by!(race_id: human_race.id, api_index: 'variant') do |s|
      s.name = 'Humano Variante'
    end
  end

  let!(:klass) do
    Klass.find_or_create_by!(api_index: 'fighter') do |k|
      k.name = 'Guerreiro'
      k.hit_die = 10
      k.subclass_level = 3
    end
  end

  let!(:bg) do
    Background.find_or_create_by!(api_index: 'soldier') do |b|
      b.name = 'Soldado'
      b.feature_name = 'Patente Militar'
      b.feature_desc = 'Spec'
    end
  end

  let!(:align) do
    Alignment.find_or_create_by!(api_index: 'lg') { |a| a.name = 'Leal e Bom' }
  end

  # ASI Humano Padrão = +1 em todos (PHB). Atributos pós-racial = 14/16/14/9/12/8 + 1/1/1/1/1/1.
  def base_attrs
    { str: 13, dex: 15, con: 13, int: 8, wis: 11, cha: 7 }
  end

  def standard_post_racial
    base_attrs.transform_values { |v| v + 1 }
  end

  # Para Humano Variante o jogador escolhe 2 atributos para +1. Aqui DEX e CON.
  def variant_post_racial(extra: %i[dex con], wis_bump_to: nil)
    h = base_attrs.dup
    extra.each { |k| h[k] = h[k] + 1 }
    h[:wis] = wis_bump_to if wis_bump_to
    h
  end

  # Frontend envia `attributes` já pós-racial (final). CPS popula
  # `base_ability_scores` = attributes (se não vier `base_attributes` snake_case
  # no payload), e `race_bonuses_applied` fica vazio quando `abilityBonuses`
  # não é enviado — comportamento idempotente do sync. Mesmo padrão usado pelo
  # spec existente `character_provisioning_service_race_summary_spec.rb`.
  def build_payload(sub_rule:, race_choices: {}, attributes: nil)
    attrs = attributes || standard_post_racial
    {
      character: { name: "Spec #{sub_rule} #{SecureRandom.hex(3)}", background: bg.name },
      wizard: {
        meta: { name: "Spec #{sub_rule}", alignmentKey: align.api_index },
        race: {
          raceId: human_race.id,
          subRaceId: (sub_rule == 'standard' ? standard_subrace.id : variant_subrace.id),
          ruleId: 'human',
          subRuleId: sub_rule,
          attributes: attrs,
          raceChoices: race_choices
        },
        klass: {
          klassId: klass.id,
          level: 1,
          classSkillPicks: %w[Atletismo Intimidação],
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
  #  STEP RACE — passo do wizard (draft_data) — Humano padrão e variante
  # =====================================================================
  describe 'StepRace (CharacterDraftSteps::RaceStepService) — wizard draft' do
    let(:character) { create(:character, user: user, status: :draft) }

    context 'Humano Padrão' do
      it 'persiste raceId, subraceId e o idioma extra escolhido em raceChoices' do
        svc = CharacterDraftSteps::RaceStepService.new(
          character: character,
          data: {
            'raceId' => human_race.id.to_s,
            'subraceId' => standard_subrace.id.to_s,
            'raceChoices' => { 'chosenLanguages' => ['Élfico'] }
          }
        )
        result = svc.call

        expect(result.draft_data.dig('selectedRace', 'id')).to eq(human_race.id.to_s)
        expect(result.draft_data.dig('selectedSubrace', 'id')).to eq(standard_subrace.id.to_s)
        expect(result.draft_data['raceChoices']).to eq('chosenLanguages' => ['Élfico'])
      end
    end

    context 'Humano Variante' do
      it 'persiste chosenSkills, chosenLanguages e variantHumanASI no draft' do
        svc = CharacterDraftSteps::RaceStepService.new(
          character: character,
          data: {
            'raceId' => human_race.id.to_s,
            'subraceId' => variant_subrace.id.to_s,
            'raceChoices' => {
              'chosenLanguages' => ['Anão'],
              'chosenSkills' => ['Percepção'],
              'variantHumanASI' => {
                'mode' => 'feat',
                'featId' => 'observador',
                'choices' => {}
              }
            },
            'featId' => 'observador'
          }
        )
        result = svc.call
        rc = result.draft_data['raceChoices']

        expect(rc['chosenLanguages']).to eq(['Anão'])
        expect(rc['chosenSkills']).to eq(['Percepção'])
        expect(rc.dig('variantHumanASI', 'mode')).to eq('feat')
        expect(rc.dig('variantHumanASI', 'featId')).to eq('observador')
        expect(result.draft_data['_featId']).to eq('observador')
        expect(result.draft_data.dig('selectedFeat', 'id')).to eq('observador')
      end
    end

    context 'troca de subraça (standard ↔ variant)' do
      it 'limpa featId quando o usuário sai do Variante (force=true)' do
        character.update!(draft_data: {
          '_raceId' => human_race.id.to_s,
          'selectedRace' => { 'id' => human_race.id.to_s },
          'selectedSubrace' => { 'id' => variant_subrace.id.to_s },
          'raceChoices' => {
            'variantHumanASI' => { 'mode' => 'feat', 'featId' => 'observador' }
          },
          '_featId' => 'observador'
        })

        # Trocar subraça (apenas) NÃO dispara invalidate! (que só aciona quando muda raceId).
        # Mas atualizar raceChoices DEVE substituir o conteúdo antigo.
        svc = CharacterDraftSteps::RaceStepService.new(
          character: character,
          data: {
            'subraceId' => standard_subrace.id.to_s,
            'raceChoices' => { 'chosenLanguages' => ['Halfling'] },
            'featId' => nil
          }
        )
        result = svc.call

        expect(result.draft_data.dig('selectedSubrace', 'id')).to eq(standard_subrace.id.to_s)
        expect(result.draft_data['raceChoices']).to eq('chosenLanguages' => ['Halfling'])
        expect(result.draft_data['_featId']).to be_nil
      end
    end
  end

  # =====================================================================
  #  PROVISIONING — payload do wizard cria Sheet com snapshot completo
  # =====================================================================
  describe 'CharacterProvisioningService — Humano Padrão' do
    let(:payload) do
      build_payload(sub_rule: 'standard', race_choices: { 'chosenLanguages' => ['Élfico'] })
    end

    it 'cria a Sheet com race_id e sub_race_id corretos' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true), -> { cmd.errors.full_messages.join('; ') rescue cmd.inspect }

      sheet = Sheet.order(:id).last
      expect(sheet.race_id).to eq(human_race.id)
      expect(sheet.sub_race_id).to eq(standard_subrace.id)
    end

    it 'persiste race_summary com speed_ft=30 e SEM darkvision (PHB)' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      rs = sheet.race_summary || {}

      expect(rs['speed_ft'].to_i).to eq(30)
      expect(rs['darkvision']).to be_blank,
        "Humano não tem darkvision (PHB), veio: #{rs['darkvision'].inspect}"
      expect(rs['name']).to eq('Humano')
      expect(rs['sub_race_name']).to eq('Humano Padrão')
    end

    it 'inclui Comum + idioma escolhido em race_summary["languages"]' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last
      langs = Array((sheet.race_summary || {})['languages']).map(&:to_s)

      expect(langs).to include('Comum'),
        "Humano sempre fala Comum (idioma sempre concedido)."
      expect(langs).to include('Élfico'),
        "raceChoices.chosenLanguages deve ser persistido em race_summary.languages."
    end

    it 'reflete ASI +1 em TODOS os atributos nas colunas finais (sheet.{str..cha})' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last

      # Humano Padrão concede +1 em cada atributo; o front envia as 6 colunas
      # já pós-racial em `attributes`. Aqui validamos que as colunas batem com
      # base + 1 (PHB), descartando regressões em que o sync recalcularia
      # base errado e voltaria com valores diferentes.
      %i[str dex con int wis cha].each do |k|
        expect(sheet.public_send(k)).to eq(standard_post_racial[k]),
          "Humano Padrão deve resultar em #{k.upcase}=#{standard_post_racial[k]} " \
          "(base #{base_attrs[k]} + 1); veio #{sheet.public_send(k).inspect}"
      end
    end

    it 'persiste raceChoices.chosenLanguages em metadata["race_choices"]' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last

      rc = (sheet.metadata || {})['race_choices'] || {}
      expect(Array(rc['chosenLanguages'])).to include('Élfico')
    end

    it 'NÃO popula chosenSkills/variantHumanASI para Humano Padrão' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last

      rc = (sheet.metadata || {})['race_choices'] || {}
      expect(rc['chosenSkills'].to_s).to be_blank
      expect(rc['variantHumanASI']).to be_blank
      # Humano Padrão NÃO ganha feat racial.
      feats = Array((sheet.metadata || {})['feats'])
      expect(feats).to be_empty
    end
  end

  describe 'CharacterProvisioningService — Humano Variante' do
    # Variante: +1 em 2 atributos diferentes (DEX e CON) + 1 perícia + 1 feat.
    # Pré-requisito do feat 'observador': WIS >= 13. Subimos a WIS base p/ 13
    # (independente do +1 escolhido em DEX/CON) para satisfazer.
    # OBS: o feat Observador concede +1 INT e +1 WIS, então sheet.wis ao final
    # = 13 (post-racial) + 1 (feat) = 14.
    let(:variant_attrs) do
      variant_post_racial(extra: %i[dex con], wis_bump_to: 13)
    end

    let(:payload) do
      build_payload(
        sub_rule: 'variant',
        attributes: variant_attrs,
        race_choices: {
          'chosenLanguages' => ['Anão'],
          'chosenSkills' => ['Percepção'],
          'variantHumanASI' => {
            'mode' => 'feat',
            'featId' => 'observador',
            'choices' => {}
          }
        }
      )
    end

    it 'cria Sheet com sub_race_id = variant' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true), -> { cmd.errors.full_messages.join('; ') rescue cmd.inspect }
      sheet = Sheet.order(:id).last
      expect(sheet.sub_race_id).to eq(variant_subrace.id)
      expect(sheet.race_summary['sub_race_name']).to eq('Humano Variante')
    end

    it 'reflete +1 em DOIS atributos escolhidos (DEX, CON) nas colunas finais — não em todos como Padrão' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last

      expect(sheet.dex).to eq(base_attrs[:dex] + 1),
        "DEX deve receber o +1 do Variant Human ASI"
      expect(sheet.con).to eq(base_attrs[:con] + 1),
        "CON deve receber o +1 do Variant Human ASI"
      # STR/INT/CHA não recebem bônus racial (Variant escolhe só 2):
      expect(sheet.str).to eq(base_attrs[:str])
      expect(sheet.cha).to eq(base_attrs[:cha])
    end

    it 'persiste chosenSkills (perícia extra) em metadata["race_choices"]' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last

      rc = (sheet.metadata || {})['race_choices'] || {}
      expect(Array(rc['chosenSkills'])).to include('Percepção')
    end

    it 'persiste variantHumanASI completo (mode+featId+choices) em metadata["race_choices"]' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last

      hv = (sheet.metadata || {}).dig('race_choices', 'variantHumanASI')
      expect(hv).to be_present
      expect(hv['mode']).to eq('feat')
      expect(hv['featId']).to eq('observador')
    end

    it 'aplica o feat racial ("Observador") via FeatAssignmentService — cria SheetFeat e metadata["feats"]' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last

      sf = sheet.sheet_feats.joins(:feat).where(feats: { api_index: 'observador' }).first
      expect(sf).to be_present,
        'FeatAssignmentService deveria ter criado SheetFeat para Variant Human feat=observador.'
      expect(sf.level_gained).to eq(1)

      # FeatAssignmentService grava em metadata['feats'] uma entrada com
      # `feat_id` (slug api_index), `name`, `ability_bonuses`, `proficiency_bonuses`.
      # NÃO confundir com `id` (DB primary key) ou `api_index` (este último não é setado).
      feats_meta = Array((sheet.metadata || {})['feats'])
      observador = feats_meta.find { |f| f['feat_id'] == 'observador' }
      expect(observador).to be_present, 'metadata["feats"] deve incluir "feat_id=observador" após Variant Human.'
      expect(observador['ability_bonuses']).to include('wis' => 1, 'int' => 1)
      expect(Array(observador.dig('proficiency_bonuses', 'skills'))).to include('Percepção')
    end

    it 'aplica os bônus de atributo do feat (Observador: +1 INT, +1 WIS) sobre as colunas' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last

      # WIS no payload (post-racial) = 13. Observador soma +1 -> 14.
      # INT no payload (post-racial) = 8. Observador soma +1 -> 9.
      expect(sheet.wis).to eq(14),
        'Observador concede +1 WIS; coluna deve refletir após FeatAssignmentService.'
      expect(sheet.int).to eq(base_attrs[:int] + 1),
        'Observador concede +1 INT; coluna deve refletir após FeatAssignmentService.'
    end

    it 'inclui chosenSkills em proficiencies.skills.race no summary final' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last

      summary = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false)
      expect(summary.success?).to be(true), -> { summary.errors.full_messages.join('; ') rescue summary.inspect }

      race_skills = Array(summary.result.dig(:proficiencies, :skills, :race)).map(&:to_s)
      expect(race_skills).to include('Percepção'),
        'Variant Human chosenSkills deve aparecer em proficiencies.skills.race no summary.'
    end

    it 'expõe featId do Variant Human via RaceEditService#read após criação' do
      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last

      character = sheet.character
      out = CharacterSheetEdits::RaceEditService.new(character: character, data: {}).read
      expect(out['featId']).to eq('observador')
      expect(out['raceChoices']).to be_a(Hash)
      expect(out.dig('raceChoices', 'variantHumanASI', 'featId')).to eq('observador')
    end
  end

  # =====================================================================
  #  RACE PROFILE SERVICE — derivação de speed/idiomas/darkvision após salvar
  # =====================================================================
  describe 'RaceProfileService — leitura derivada' do
    it 'devolve speed_ft=30 e darkvision=0 para Humano Padrão (sem visão no escuro)' do
      cmd = CharacterProvisioningService.call(
        user: user,
        payload: build_payload(sub_rule: 'standard', race_choices: { 'chosenLanguages' => ['Élfico'] })
      )
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last

      profile = RaceProfileService.new(sheet).call
      expect(profile[:speed_ft]).to eq(30)
      # Após RaceRules.normalize_range, profile[:darkvision] sempre Integer.
      # 0 = sem darkvision (Humano não tem no PHB).
      expect(profile[:darkvision].to_i).to eq(0)
      expect(profile[:languages]).to include('Comum', 'Élfico')
    end

    it 'devolve mesma estrutura para Humano Variante (speed igual ao base)' do
      cmd = CharacterProvisioningService.call(
        user: user,
        payload: build_payload(
          sub_rule: 'variant',
          attributes: variant_post_racial(extra: %i[dex con], wis_bump_to: 13),
          race_choices: {
            'chosenLanguages' => ['Anão'],
            'chosenSkills' => ['Percepção'],
            'variantHumanASI' => { 'mode' => 'feat', 'featId' => 'observador' }
          }
        )
      )
      expect(cmd.success?).to be(true)
      sheet = Sheet.order(:id).last

      profile = RaceProfileService.new(sheet).call
      expect(profile[:speed_ft]).to eq(30)
      expect(profile[:darkvision].to_i).to eq(0)
      expect(profile[:languages]).to include('Comum', 'Anão')
    end
  end

  # =====================================================================
  #  RACE RULES — contrato canônico (defesa contra regressões no YAML)
  # =====================================================================
  describe 'RaceRules.apply — contrato canônico do Humano' do
    it 'standard: ASI +1 em todos os 6 atributos, speed 30, idioma extra aplicado' do
      applied = RaceRules.apply(
        race_id: 'human',
        subrace_id: 'standard',
        choices: { extraLanguages: ['Anão'] }
      )
      expect(applied[:speed]).to eq(30)
      expect(applied[:darkvision]).to be_blank
      expect(applied[:languages]).to include('Comum', 'Anão')
      # Para standard, applied[:ability] ainda vem do `ability` da raça base
      # (type: fixed, increases: lista com 1 em cada). Sub-raça `standard` não
      # sobrescreve ability — apenas registra o nome. O CPS converte isso em
      # race_bonuses_applied via `abilityBonuses` enviado pelo front.
      ability = applied[:ability] || {}
      type = ability[:type] || ability['type']
      expect(type.to_s).to eq('fixed'),
        'Sub-raça "standard" deve herdar a regra base (+1 em todos), tipo fixed.'
    end

    it 'variant: ASI flexível (chooseAbilities count=2 amount=1), 1 perícia, 1 feat' do
      applied = RaceRules.apply(
        race_id: 'human',
        subrace_id: 'variant',
        choices: { extraLanguages: ['Halfling'] }
      )
      expect(applied[:speed]).to eq(30)
      expect(applied[:languages]).to include('Comum', 'Halfling')

      ability = applied[:ability] || {}
      type = ability[:type] || ability['type']
      expect(type.to_s).to eq('variantHuman'),
        'Variant Human deve usar tipo "variantHuman" para sinalizar escolha de 2 atributos.'

      choose = ability[:chooseAbilities] || ability['chooseAbilities'] || {}
      expect((choose[:count] || choose['count']).to_i).to eq(2)
      expect((choose[:amount] || choose['amount']).to_i).to eq(1)
      expect(ability[:skillChoices] || ability['skillChoices']).to eq(1)
      expect(ability[:feat] || ability['feat']).to eq(true)
    end
  end
end
