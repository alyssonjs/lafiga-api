# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('spec/support/imported_sheets_seeder')
require Rails.root.join('spec/support/imported_sheets_spell_seeder')
require Rails.root.join('spec/support/imported_sheets_payload_builder')

# Phase 3.0 — Wizard ↔ Ficha (front roundtrip).
#
# Valida o CONTRACT entre `CharacterSheetSummaryService` (servido por
# `GET /api/v1/player/sheets/:id/summary?sync=true`) e o front-lafiga
# (consumido por `mergeSheetSummaryIntoCharacter` em
# `front-lafiga/src/services/mappers/publicCatalogMappers.ts`).
#
# Cada persona representativa é provisionada via wizard payload, depois o
# JSON da summary é checado contra `FRONT_REQUIRED_KEYS`: chaves que o
# front-lafiga assume existir (presença + tipo). Quebrar essa expectativa
# trava a renderização da ficha em /character/:id/sheet.
#
# Nao validamos VALORES numéricos aqui — isso é trabalho da Phase 2.x
# (fidelity). Aqui só garantimos a *forma* do payload.
RSpec.describe 'CharacterSheetSummaryService — front contract (Phase 3.0)' do
  let(:user) { create(:user) }

  before(:all) do
    ImportedSheetsSeeder.seed_all!
    ImportedSheetsSpellSeeder.seed_all!
  end

  # 4 personas que cobrem as cadeias críticas do contract:
  # - rogue L4: Sneak Attack, Expertise, Skills
  # - wizard L5: full caster (slots, prepared, list_api, prepared_limit)
  # - fighter+EK L7: third-caster (subclass spellcasting, INT ability override)
  # - barbarian L5: Rage, Fast Movement (modifiers.speed)
  PERSONAS = [
    { tab: 'p30_rogue',     class_idx: 'rogue',     subclass: 'ladrao',           level: 4, race: 'human', con: 12, int: 14 },
    { tab: 'p30_wizard',    class_idx: 'wizard',    subclass: 'escola-de-evocacao', level: 5, race: 'human', con: 14, int: 16 },
    { tab: 'p30_ekfighter', class_idx: 'fighter',   subclass: 'cavaleiro-arcano', level: 7, race: 'human', con: 14, int: 16 },
    { tab: 'p30_barbarian', class_idx: 'barbarian', subclass: 'berserker',            level: 5, race: 'human', con: 16, int: 10 }
  ].freeze

  # Contract: cada chave que o front lê em mergeSheetSummaryIntoCharacter,
  # ClassSections, SpellcastingPanel, etc. Tupla [path, ruby_class].
  # `path` é array de chaves (suportando arrays — usar :first p/ pegar o
  # primeiro elemento). `ruby_class` aceita um array (qualquer um casa).
  FRONT_REQUIRED_KEYS = [
    # Header / sheet block
    [%i[sheet name],                [String, NilClass]],
    [%i[sheet hp_max],               Integer],
    [%i[sheet experience_points],    Integer],
    [%i[sheet alignment_index],     [String, NilClass]],
    [%i[sheet race name],           [String, NilClass]],
    # Abilities
    [%i[abilities scores str], Integer],
    [%i[abilities scores dex], Integer],
    [%i[abilities scores con], Integer],
    [%i[abilities scores int], Integer],
    [%i[abilities scores wis], Integer],
    [%i[abilities scores cha], Integer],
    [%i[abilities sources],    Hash],
    # Movement (Phase 2.4.A: speed_m derivado)
    [%i[movement speed_ft], Integer],
    [%i[movement speed_m],  [Numeric, NilClass]],
    # Proficiency bonus
    [[:prof_bonus], Integer],
    # Klasses (front lê klasses[0].{name,level,subclass.name})
    [[:klasses],          Array],
    # Proficiencies
    [%i[proficiencies skills],     Hash],
    [%i[proficiencies languages],  Array],
    [%i[proficiencies armor],      Array],
    [%i[proficiencies weapons],    Array],
    [%i[proficiencies tools],      Array],
    # Saving throws
    [[:saving_throws], Array],
    # Equipment
    [%i[equipment ac ac],     Integer],
    [%i[equipment inventory], Array],
    [%i[equipment equipped],  Hash],
    # Spellcasting (conjuration)
    [%i[conjuration ability],            [String, NilClass]],
    [%i[conjuration spell_save_dc],      [Integer, NilClass]],
    [%i[conjuration spell_attack_bonus], [Integer, NilClass]],
    # Spells
    [%i[spells known_by_level],    [Hash, NilClass]],
    # Features e feats
    [[:features], Array],
    [[:feats],    Array],
    # Traits
    [[:traits], Array],
    # Background
    [[:background], Hash],
    # Runtime state
    [[:runtime_state], Hash],
    # Avatar customization
    [[:avatar_customization], Hash]
  ].freeze

  PERSONAS.each do |persona|
    it "[#{persona[:tab]}] #{persona[:class_idx]}/#{persona[:subclass]} L#{persona[:level]} satisfaz o contract do front" do
      sheet_payload = build_persona_sheet(persona)
      payload = ImportedSheetsPayloadBuilder.build(
        sheet_payload,
        user: user,
        background: Background.first || Background.create!(api_index: 'soldado', name: 'Soldado'),
        alignment: Alignment.first || Alignment.create!(api_index: 'leal-bom', name: 'Leal e Bom')
      )

      cmd = CharacterProvisioningService.call(user: user, payload: payload)
      expect(cmd.success?).to be(true), -> { cmd.errors.full_messages.join('; ') }

      sheet_record = Sheet.order(:id).last
      result = CharacterSheetSummaryService.call(sheet_id: sheet_record.id).result
      expect(result).to be_a(Hash), 'CharacterSheetSummaryService devolveu nil'

      # Normaliza chaves p/ string OR symbol (HashWithIndifferentAccess)
      summary = result.respond_to?(:with_indifferent_access) ? result.with_indifferent_access : result.deep_symbolize_keys

      missing = []
      mistyped = []
      FRONT_REQUIRED_KEYS.each do |path, expected_type|
        node = dig_summary(summary, path)
        if node.nil? && !Array(expected_type).include?(NilClass)
          missing << path.join('.')
          next
        end
        next if node.nil? && Array(expected_type).include?(NilClass)
        ok = Array(expected_type).any? { |t| node.is_a?(t) }
        mistyped << "#{path.join('.')}: esperado=#{Array(expected_type).join('/')} got=#{node.class}" unless ok
      end

      aggregate_failures "contract[#{persona[:tab]}]" do
        expect(missing).to eq([]), "Chaves AUSENTES no summary (front quebra):\n  - #{missing.join("\n  - ")}"
        expect(mistyped).to eq([]), "Chaves com TIPO errado:\n  - #{mistyped.join("\n  - ")}"

        # Validações estruturais extra que o front faz com defensiveness mínimo:
        klasses = summary['klasses'] || summary[:klasses]
        expect(klasses.first).to be_a(Hash), 'klasses[0] precisa ser Hash p/ ClassSections'
        expect(klasses.first['name'] || klasses.first[:name]).to be_a(String)
        expect(klasses.first['level'] || klasses.first[:level]).to be_a(Integer)

        # proficiencies.skills.{class,background,race} — front itera essas 3
        skills = summary['proficiencies']['skills'] rescue summary[:proficiencies][:skills]
        %w[class background race].each do |k|
          expect(skills.key?(k) || skills.key?(k.to_sym)).to be(true), "proficiencies.skills falta a chave '#{k}'"
        end
      end
    end
  end

  # ---- helpers --------------------------------------------------------------

  def build_persona_sheet(persona)
    {
      'tab_name' => persona[:tab],
      'meta' => {
        'name' => persona[:tab].titleize,
        'level' => persona[:level],
        'race'  => { 'race_api_index' => persona[:race], 'subrace_api_index' => nil },
        'klass' => { 'class_api_index' => persona[:class_idx], 'subclass_api_index' => persona[:subclass] }
      },
      'abilities' => {
        'strength'     => { 'score' => 10 },
        'dexterity'    => { 'score' => 14 },
        'constitution' => { 'score' => persona[:con] },
        'intelligence' => { 'score' => persona[:int] },
        'wisdom'       => { 'score' => 12 },
        'charisma'     => { 'score' => 10 }
      },
      'feats' => []
    }
  end

  def dig_summary(summary, path)
    node = summary
    path.each do |key|
      return nil unless node.is_a?(Hash)
      node = node[key.to_s] || node[key.to_sym]
    end
    node
  end
end
