# frozen_string_literal: true

# ----------------------------------------------------------------------------
# Helpers + shared_examples para propagação de talentos (feats) na ficha.
#
# **Por que existe?**
# Cada feat pode ser concedido por 3+ entry-points distintos (Variant Human L1
# via provisionamento novo, Variant Human L1 via edit de raça, ASI no
# level-up). Todos terminam em `FeatAssignmentService`, mas se um caminho
# bypassar a resolução de `proficiency_bonuses` (caso histórico do bug Perito
# 2026-04-28 a 2026-05-08), só os specs daquele caminho específico pegam.
#
# Este módulo concentra:
#   1. Builders de cenário por entry-point (`build_*`).
#   2. `shared_examples 'feat propaga proficiencies para a ficha'` que
#      asserta o invariante final: `metadata.feats[].proficiency_bonuses`
#      resolvido + `summary.proficiencies.{skills.feat,tools,armor,weapons}`
#      refletindo o feat.
#
# Uso típico (`spec/services/feats_propagation_matrix_spec.rb`):
# ```ruby
# include_examples 'feat propaga proficiencies para a ficha',
#   feat_id: 'perito',
#   choices: { 'skillsAndTools' => ['Arcanismo', 'Investigação', 'Utensílios de Cozinheiro'] },
#   expects: { skills: %w[Arcanismo Investigação], tools: ['Utensílios de Cozinheiro'] },
#   entry_points: %i[provisioning race_edit level_up_asi legacy_metadata]
# ```
#
# Cada feat só precisa declarar `feat_id`, `choices` e o que espera ver na
# ficha — e o spec roda automaticamente os 4 caminhos. Adicionar feat novo
# = adicionar 1 bloco no matrix spec.
# ----------------------------------------------------------------------------
module FeatPropagationHelpers
  ABILITY_KEYS = %i[str dex con int wis cha].freeze

  # ---- DB scaffolding -------------------------------------------------------
  # Catálogo mínimo necessário em cada cenário. Idempotente (find_or_create_by).
  def fp_role
    Role.find_or_create_by!(name: 'player')
  end

  def fp_user
    suffix = SecureRandom.hex(4)
    User.create!(
      email: "fp_#{suffix}@example.com",
      username: "fp#{suffix}",
      password: 'password1', password_confirmation: 'password1',
      role_id: fp_role.id
    )
  end

  def fp_human_race
    Race.find_or_create_by!(api_index: 'human') { |r| r.name = 'Humano' }
  end

  def fp_variant_subrace
    SubRace.find_or_create_by!(race_id: fp_human_race.id, api_index: 'variant') { |s| s.name = 'Humano Variante' }
  end

  def fp_standard_subrace
    SubRace.find_or_create_by!(race_id: fp_human_race.id, api_index: 'standard') { |s| s.name = 'Humano Padrão' }
  end

  def fp_klass
    # Wizard (mago) é a classe canónica usada por specs de level-up por já ter
    # subclass_level=2 e funcionar com todos os specs existentes.
    Klass.find_or_create_by!(api_index: 'wizard') do |k|
      k.name = 'Mago'; k.hit_die = 6; k.subclass_level = 2
    end
  end

  def fp_sub_klass
    SubKlass.find_or_create_by!(klass_id: fp_klass.id, api_index: 'evocacao') { |s| s.name = 'Escola de Evocação' }
  end

  def fp_background
    Background.find_or_create_by!(api_index: 'soldier') do |b|
      b.name = 'Soldado'; b.feature_name = 'Patente Militar'; b.feature_desc = 'spec'
    end
  end

  def fp_alignment
    Alignment.find_or_create_by!(api_index: 'lg') { |a| a.name = 'Leal e Bom' }
  end

  # Garante que o Feat existe no DB com a estrutura canônica do
  # `config/feats_improved.yml`. Sem isso, `FeatRules.find` ainda funciona via
  # static rules, mas alguns specs validam o roundtrip via DB.
  def fp_ensure_feat_in_db!(feat_id)
    rule = FeatRules.find(feat_id)
    return Feat.find_by(api_index: feat_id) if rule.nil?

    Feat.find_or_create_by!(api_index: feat_id) do |f|
      f.name                = rule[:name]
      f.description         = rule[:description].to_s
      f.prerequisites       = (rule[:prerequisites]       || {}).to_json
      f.ability_bonuses     = (rule[:ability_bonuses]     || {}).to_json
      f.proficiency_bonuses = (rule[:proficiency_bonuses] || {}).to_json
      f.features            = (rule[:features]            || {}).to_json
      f.cantrips            = (rule[:cantrips]            || {}).to_json
      f.spells              = (rule[:spells]              || {}).to_json
      f.special_rules       = (rule[:special_rules]       || {}).to_json
    end
  end

  # ---- entry-point builders ------------------------------------------------
  #
  # Cada builder devolve a `Sheet` resultante. Os payloads são minimalistas
  # mas suficientes para `CharacterProvisioningService` / `*EditService` não
  # falharem (HP, atributos, magia, equipamento mínimo).

  # ENTRY 1: criação nova de personagem Humano Variante L1 com feat racial.
  # Caminho: front → /api/v1/.../provision → CharacterProvisioningService.
  def fp_build_via_provisioning(feat_id:, choices:, user: nil)
    user ||= fp_user
    fp_ensure_feat_in_db!(feat_id)

    payload = {
      character: { name: "FP #{feat_id} #{SecureRandom.hex(2)}", background: fp_background.name },
      wizard: {
        meta: { name: "FP-#{feat_id}", alignmentKey: fp_alignment.api_index },
        race: {
          raceId: fp_human_race.id,
          subRaceId: fp_variant_subrace.id,
          ruleId: 'human',
          subRuleId: 'variant',
          # Atributos ≥13 em todos os scores: garante que feats com prereqs
          # típicos (Observador wis≥13, Atalhão dex≥13, Atirador dex≥13) sejam
          # válidos sem precisar do spec sobrescrever cada vez. Variant Human
          # adiciona +1 DES +1 CAR (chosenAbilities=[DEX,CHA] abaixo).
          attributes: { str: 14, dex: 14, con: 14, int: 14, wis: 14, cha: 14 },
          baseAttributes: { str: 14, dex: 13, con: 14, int: 14, wis: 14, cha: 13 },
          abilityBonuses: { dex: 1, cha: 1 },
          raceChoices: {
            'chosenLanguages' => [],
            'chosenSkills' => [],
            'chosenAbilities' => %w[DEX CHA],
            'variantHumanASI' => {
              'mode' => 'feat',
              'featId' => feat_id,
              'choices' => choices
            }
          }
        },
        klass: {
          klassId: fp_klass.id, level: 1,
          classSkillPicks: %w[Arcanismo História],
          classPicksByLevel: { '1' => { 'hp' => { 'dieResult' => 6, 'total' => 8, 'method' => 'average' } } }
        },
        background: { backgroundName: fp_background.name, backgroundKey: fp_background.api_index },
        equipment: {},
        avatar: { customization: {} }
      }
    }

    cmd = CharacterProvisioningService.call(user: user, payload: payload)
    raise "provisionamento falhou: #{cmd.errors.full_messages.inspect}" unless cmd.success?

    Sheet.order(:id).last
  end

  # ENTRY 2: edit de raça em personagem ATIVO (não-draft) trocando o feat.
  # Caminho: front → PATCH /character/:id/draft → CharacterSheetEdits::RaceEditService.
  def fp_build_via_race_edit(feat_id:, choices:, user: nil)
    user ||= fp_user
    fp_ensure_feat_in_db!(feat_id)

    # Provisiona PRIMEIRO sem feat racial, para depois editar. (Variant Human
    # exige um feat — usamos `observador` como placeholder neutro, depois
    # trocamos pelo feat alvo via RaceEditService.)
    fp_ensure_feat_in_db!('observador')
    placeholder_choices = { 'ability' => 'wis' }
    sheet = fp_build_via_provisioning(
      feat_id: 'observador',
      choices: placeholder_choices,
      user: user
    )

    CharacterSheetEdits::RaceEditService.new(
      character: sheet.character,
      data: {
        'raceChoices' => {
          'chosenLanguages' => [],
          'chosenSkills' => [],
          'chosenAbilities' => %w[DEX CHA],
          'variantHumanASI' => {
            'mode' => 'feat',
            'featId' => feat_id,
            'choices' => choices
          }
        }
      },
      current_user: user
    ).call

    sheet.reload
  end

  # ENTRY 3: ASI no level-up (nível 4 default) escolhendo o feat.
  # Caminho: front → PATCH /character/:id/draft (step=progression) →
  # CharacterSheetEdits::ProgressionEditService.
  def fp_build_via_level_up_asi(feat_id:, choices:, user: nil, level: 4)
    user ||= fp_user
    fp_ensure_feat_in_db!(feat_id)

    # Cria personagem com Humano Padrão (não-Variant, sem feat racial) no nível
    # equivalente, com a slot de ASI vazia esperando o feat.
    character = Character.create!(user: user, name: "FP-LU-#{feat_id} #{SecureRandom.hex(2)}", background: 'Sage')
    sheet = Sheet.create!(
      character: character,
      race: fp_human_race, sub_race: fp_standard_subrace,
      # Atributos ≥13 (mesma lógica do provisioning helper) para satisfazer
      # prereqs comuns como Observador wis≥13.
      str: 13, dex: 14, con: 14, int: 16, wis: 14, cha: 13,
      hp_max: 20 + (level - 1) * 4, hp_current: 20 + (level - 1) * 4,
      current_level: level,
      metadata: {
        'base_ability_scores' => { 'str' => 13, 'dex' => 14, 'con' => 14, 'int' => 16, 'wis' => 14, 'cha' => 13 },
        'class_choices' => {
          'per_level' => (1..level).each_with_object({}) { |lv, h| h[lv.to_s] = {} },
          'skills_selected' => %w[Arcanismo História]
        },
        'class_summary' => {
          'spellcasting' => { 'ability' => 'INT', 'preparation' => 'prepared' },
          'armor_proficiencies' => []
        }
      }
    )
    SheetKlass.create!(sheet: sheet, klass: fp_klass, sub_klass: fp_sub_klass, level: level)

    CharacterSheetEdits::ProgressionEditService.new(
      character: character,
      level: level,
      data: {
        'levelChoice' => {
          'level' => level,
          'asiChoice' => {
            'mode' => 'feat',
            'featId' => feat_id,
            'featGrantChoices' => choices
          }
        }
      },
      current_user: user
    ).call

    sheet.reload
  end

  # ENTRY 4: Cenário LEGADO. Provisiona normalmente, depois corrompe
  # `metadata.feats[i].proficiency_bonuses` para o formato RAW pré-2026-04-28
  # (`{skills_or_tools: {choose: ...}}`) preservando `choices`. Usado para
  # validar o fallback in-memory do aggregator.
  def fp_build_via_legacy_metadata(feat_id:, choices:, user: nil)
    sheet = fp_build_via_provisioning(feat_id: feat_id, choices: choices, user: user)
    rule = FeatRules.find(feat_id)
    raw_pb = rule[:proficiency_bonuses].to_h.deep_stringify_keys

    meta = sheet.metadata.deep_dup
    feats = Array(meta['feats'])
    feat_entry = feats.find { |f| (f['feat_id'] || f[:feat_id]).to_s == feat_id }
    feat_entry['proficiency_bonuses'] = raw_pb
    meta['feats'] = feats
    sheet.update!(metadata: meta)
    sheet.reload
  end

  # ---- assertion helpers ---------------------------------------------------

  # Lê metadata.feats[i].proficiency_bonuses para o feat alvo. Útil para asserts
  # que checam a forma resolvida (sem `skills_or_tools`).
  def fp_pb_for(sheet, feat_id)
    feat_entry = Array(sheet.metadata['feats']).find { |f| (f['feat_id'] || f[:feat_id]).to_s == feat_id }
    return {} unless feat_entry
    feat_entry['proficiency_bonuses'] || feat_entry[:proficiency_bonuses] || {}
  end

  def fp_summary_for(sheet)
    cmd = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false)
    return {} unless cmd&.success?
    cmd.respond_to?(:result) ? cmd.result : cmd
  end
end

RSpec.configure do |config|
  config.include FeatPropagationHelpers, type: :service
end

# ─────────────────────────────────────────────────────────────────────────────
# Shared examples — invariante de propagação de proficiencies por feat
# ─────────────────────────────────────────────────────────────────────────────
#
# Parâmetros (passados via `include_examples`):
#   - feat_id (String): api_index do feat (ex.: 'perito').
#   - choices (Hash):   payload de _grantChoices que o front envia.
#   - expects (Hash):
#       skills:  Array<String>  — perícias esperadas em proficiencies.skills.feat.
#       tools:   Array<String>  — ferramentas esperadas em proficiencies.tools.
#       armor:   Array<String>  — categorias de armadura.
#       weapons: Array<String>  — categorias/armas individuais.
#       shields: Boolean        — se 'escudos' deve aparecer em proficiencies.armor.
#   - entry_points (Array<Symbol>): subconjunto de
#       [:provisioning, :race_edit, :level_up_asi, :legacy_metadata].
#       Default: todos os 4. Específicos podem omitir caminhos quando o feat
#       só faz sentido em um (ex.: feats que não dão proficiencias só rodam
#       o caminho `:provisioning`).
#
# A cada entry-point a suite roda 2 `it` blocks:
#   1. metadata.feats[].proficiency_bonuses contém a forma RESOLVIDA esperada.
#   2. CharacterSheetSummaryService.proficiencies surfaca os valores.
#
# O caminho `:legacy_metadata` força pb RAW e valida que o aggregator faz
# fallback via choices (cobre o bug histórico do Perito).
RSpec.shared_examples 'feat propaga proficiencies para a ficha' do |feat_id:, choices:, expects:, entry_points: %i[provisioning race_edit level_up_asi legacy_metadata]|
  entry_points.each do |entry|
    context "via :#{entry}" do
      let(:sheet) do
        case entry
        when :provisioning      then fp_build_via_provisioning(feat_id: feat_id, choices: choices)
        when :race_edit         then fp_build_via_race_edit(feat_id: feat_id, choices: choices)
        when :level_up_asi      then fp_build_via_level_up_asi(feat_id: feat_id, choices: choices)
        when :legacy_metadata   then fp_build_via_legacy_metadata(feat_id: feat_id, choices: choices)
        else raise ArgumentError, "entry_point desconhecido: #{entry}"
        end
      end

      # No caminho legacy_metadata, pb FICA RAW de propósito (é o que estamos
      # testando o fallback contra). Os outros caminhos devem resolver.
      unless entry == :legacy_metadata
        it "metadata.feats[#{feat_id}].proficiency_bonuses está RESOLVIDO (sem nó RAW skills_or_tools)" do
          pb = fp_pb_for(sheet, feat_id)
          expect(pb).not_to have_key('skills_or_tools'),
            "proficiency_bonuses ainda está RAW em #{entry}. Veio: #{pb.inspect}"
          expect(pb).not_to have_key('choose'),
            "proficiency_bonuses ainda contém top-level :choose em #{entry}. Veio: #{pb.inspect}"
        end
      end

      it 'CharacterSheetSummaryService.proficiencies reflete o feat' do
        summary = fp_summary_for(sheet)
        profs = summary[:proficiencies] || {}

        if expects[:skills].present?
          feat_skills = Array(profs.dig(:skills, :feat)).map(&:to_s)
          expects[:skills].each do |skill|
            expect(feat_skills).to include(skill),
              "skills.feat deveria conter '#{skill}' (entry=#{entry}). Veio: #{feat_skills.inspect}"
          end
        end

        if expects[:tools].present?
          tools = Array(profs[:tools]).map(&:to_s)
          expects[:tools].each do |tool|
            expect(tools).to include(tool),
              "proficiencies.tools deveria conter '#{tool}' (entry=#{entry}). Veio: #{tools.inspect}"
          end
        end

        if expects[:armor].present?
          arm = Array(profs[:armor]).map(&:to_s)
          expects[:armor].each do |a|
            expect(arm).to include(a),
              "proficiencies.armor deveria conter '#{a}' (entry=#{entry}). Veio: #{arm.inspect}"
          end
        end

        if expects[:shields] == true
          arm = Array(profs[:armor]).map(&:to_s)
          expect(arm).to include('escudos'),
            "proficiencies.armor deveria incluir 'escudos' (entry=#{entry}). Veio: #{arm.inspect}"
        end

        if expects[:weapons].present?
          wp = Array(profs[:weapons]).map(&:to_s)
          expects[:weapons].each do |w|
            expect(wp).to include(w),
              "proficiencies.weapons deveria conter '#{w}' (entry=#{entry}). Veio: #{wp.inspect}"
          end
        end
      end
    end
  end
end
