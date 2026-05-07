# frozen_string_literal: true

require 'rails_helper'

# RaceProfileService precisa devolver speed/darkvision/etc corretos mesmo quando
# `metadata['race_summary']` esta vazio (caminho de fallback). Esse caminho era
# importante para fichas legadas onde o CharacterProvisioningService nao
# populava race_summary completo (ex.: ficha do Adimael Neverdie, Wood Elf,
# que voltava 30 ft em vez de 35 ft).
#
# Causa raiz original: o fallback derivava `subrace_id` via
# `sheet.sub_race.name.parameterize.underscore` ("Elfo da Floresta" ->
# "elfo_da_floresta"), que nao existia no `sub_map_by_race`. Como sub_race ja
# tem `api_index` canonico ('wood'), o fallback deve usar isso direto.
RSpec.describe RaceProfileService, type: :service do
  let(:user) do
    User.create!(
      email: "race_profile_#{SecureRandom.hex(4)}@example.com",
      username: "rps#{SecureRandom.hex(4)}",
      password: 'password1',
      password_confirmation: 'password1',
      role_id: Role.find_or_create_by!(name: 'player').id
    )
  end

  let(:character) { Character.create!(user: user, name: "Spec #{SecureRandom.hex(2)}", background: 'Sage') }

  def build_sheet(race_api_index:, race_name:, sub_api_index:, sub_name:, metadata: {})
    race = Race.find_or_create_by!(api_index: race_api_index) { |r| r.name = race_name }
    sub  = SubRace.find_or_create_by!(race_id: race.id, api_index: sub_api_index) { |s| s.name = sub_name }
    Sheet.create!(
      character: character,
      race: race,
      sub_race: sub,
      str: 10, dex: 14, con: 12, int: 10, wis: 12, cha: 10,
      hp_max: 10, hp_current: 10,
      current_level: 1,
      metadata: metadata
    )
  end

  describe 'fallback (race_summary vazio) — Wood Elf' do
    it 'devolve speed_ft = 35 (Fleet of Foot)', :aggregate_failures do
      sheet = build_sheet(
        race_api_index: 'elf',
        race_name: 'Elfo',
        sub_api_index: 'wood',
        sub_name: 'Elfo da Floresta',
        metadata: {}
      )

      profile = described_class.new(sheet).call

      expect(profile[:speed_ft]).to eq(35),
        "esperado 35 ft (Wood Elf PHB), veio #{profile[:speed_ft].inspect}.\n" \
        "  Causa provavel: fallback derivou subrace_id de sub_race.name " \
        "('Elfo da Floresta' -> 'elfo_da_floresta') em vez de usar " \
        "sub_race.api_index ('wood'). Bug do Adimael Neverdie."
      # 35 ft × 0.3048 m/ft = 10.668 m → round(1) = 10.7 m. O valor 11.0 do
      # spec antigo refletia o cálculo bugado `(speed * 0.3).round` (= 11)
      # que existia no `RaceProfileService.call`. Após a unificação com a
      # fórmula PHB exata em ambos os caminhos (call + normalize), o valor
      # correto é 10.7.
      expect(profile[:speed_m]).to eq(10.7),
        "esperado 10.7 m (35 × 0.3048 ≈ 10.668, round(1) = 10.7), veio #{profile[:speed_m].inspect}"
    end
  end

  describe 'fallback — Drow' do
    it 'devolve speed_ft = 30 (Drow nao tem Fleet of Foot)' do
      sheet = build_sheet(
        race_api_index: 'elf',
        race_name: 'Elfo',
        sub_api_index: 'drow',
        sub_name: 'Drow',
        metadata: {}
      )

      expect(described_class.new(sheet).call[:speed_ft]).to eq(30)
    end
  end

  describe 'fallback — Hill Dwarf (api_index ja em ingles)' do
    it 'devolve speed_ft = 25 (Anao base)' do
      sheet = build_sheet(
        race_api_index: 'dwarf',
        race_name: 'Anão',
        sub_api_index: 'hill',
        sub_name: 'Anão da Colina',
        metadata: {}
      )

      expect(described_class.new(sheet).call[:speed_ft]).to eq(25)
    end
  end

  # Phase 2.4.A: CharacterProvisioningService persiste `race_summary` apenas com
  # `speed_ft` (sem `speed_m`). Antes, summary.movement.speed_m vinha nil para
  # toda ficha provisionada — `build_movement` pegava `rs['speed_m']` direto.
  describe 'derivation de speed_m a partir de speed_ft' do
    it 'deriva speed_m quando race_summary só tem speed_ft' do
      sheet = build_sheet(
        race_api_index: 'human', race_name: 'Humano',
        sub_api_index: 'standard', sub_name: 'Humano Padrão',
        metadata: {}
      )
      sheet.update!(race_summary: { 'speed_ft' => 30 })

      profile = described_class.new(sheet).call
      expect(profile[:speed_ft]).to eq(30)
      expect(profile[:speed_m]).to eq(9.1),
        "esperado ~9.1 m (30 * 0.3048), veio #{profile[:speed_m].inspect}.\n" \
        '  RaceProfileService.normalize agora deriva speed_m quando ausente.'
    end

    it 'preserva speed_m explícito do race_summary quando presente' do
      sheet = build_sheet(
        race_api_index: 'human', race_name: 'Humano',
        sub_api_index: 'standard', sub_name: 'Humano Padrão',
        metadata: {}
      )
      sheet.update!(race_summary: { 'speed_ft' => 30, 'speed_m' => 9 })

      expect(described_class.new(sheet).call[:speed_m]).to eq(9)
    end
  end

  describe 'caminho feliz (metadata[\'race_summary\'] presente)' do
    it 'usa speed_ft do race_summary preferentemente ao fallback' do
      sheet = build_sheet(
        race_api_index: 'elf',
        race_name: 'Elfo',
        sub_api_index: 'wood',
        sub_name: 'Elfo da Floresta',
        metadata: { 'race_summary' => { 'speed_ft' => 99, 'speed_m' => 30, 'languages' => [] } }
      )

      expect(described_class.new(sheet).call[:speed_ft]).to eq(99),
        'race_summary explicito no metadata deve sobrescrever fallback.'
    end
  end

  # Bug raiz Adimael: o CharacterProvisioningService popula `sheet.race_summary`
  # (coluna jsonb dedicada) com `speed_ft => 35` para Wood Elf, mas o
  # RaceProfileService so olhava `metadata['race_summary']`. Resultado: a
  # coluna autoritativa era ignorada e caia sempre no fallback (que tambem
  # estava bugado pre-fix do api_index).
  describe 'fonte autoritativa: coluna sheet.race_summary' do
    it 'prefere sheet.race_summary (coluna) sobre o fallback do RaceRules' do
      sheet = build_sheet(
        race_api_index: 'elf',
        race_name: 'Elfo',
        sub_api_index: 'wood',
        sub_name: 'Elfo da Floresta',
        metadata: {},
      )
      sheet.update!(race_summary: { 'speed_ft' => 42, 'speed_m' => 13, 'languages' => ['Common'] })

      profile = described_class.new(sheet).call
      expect(profile[:speed_ft]).to eq(42),
        "esperado 42 ft (coluna race_summary autoritativa, populada pelo " \
        "CharacterProvisioningService), veio #{profile[:speed_ft].inspect}.\n" \
        "  Bug Adimael: metadata['race_summary'] estava nil, mas a coluna " \
        "sheet.race_summary tinha o valor correto. RaceProfileService deve " \
        "preferir a coluna persistida."
    end

    it 'metadata[\'race_summary\'] tem prioridade sobre a coluna (override explicito)' do
      sheet = build_sheet(
        race_api_index: 'elf',
        race_name: 'Elfo',
        sub_api_index: 'wood',
        sub_name: 'Elfo da Floresta',
        metadata: { 'race_summary' => { 'speed_ft' => 50 } },
      )
      sheet.update!(race_summary: { 'speed_ft' => 42 })

      expect(described_class.new(sheet).call[:speed_ft]).to eq(50),
        'metadata override existe para casos de tooling/admin que precisam patch sem mexer na coluna.'
    end
  end
end
