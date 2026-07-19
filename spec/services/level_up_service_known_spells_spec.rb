# frozen_string_literal: true

require "rails_helper"

RSpec.describe LevelUpService, "persist_known_spells! via metadata per_level" do
  it "persists cantrips and spells from per_level for the target level (L2+ contract)" do
    role = Role.find_or_create_by!(name: "player")
    user = User.create!(
      email: "lu_ks_#{SecureRandom.hex(4)}@example.com",
      username: "luks#{SecureRandom.hex(4)}",
      password: "password1",
      password_confirmation: "password1",
      role_id: role.id
    )

    race = Race.create!(name: "Spec Race", api_index: "spec_race_#{SecureRandom.hex(4)}")
    klass = Klass.create!(
      name: "Spec Wizard",
      api_index: "spec_wizard_#{SecureRandom.hex(4)}",
      hit_die: 6,
      subclass_level: 2
    )

    cantrip = FactoryBot.create(:spell, level: 0, name: "Spec Cantrip #{SecureRandom.hex(2)}", api_index: "spec_c_#{SecureRandom.hex(4)}")
    leveled = FactoryBot.create(:spell, level: 1, name: "Spec Spell #{SecureRandom.hex(2)}", api_index: "spec_s_#{SecureRandom.hex(4)}")

    character = Character.create!(user: user, name: "Spec PC", background: "Test")
    sheet = Sheet.create!(
      character: character,
      race_id: race.id,
      str: 10, dex: 10, con: 10, int: 16, wis: 10, cha: 10,
      hp_max: 8,
      hp_current: 8,
      metadata: {
        "class_choices" => {
          "per_level" => {
            "2" => {
              "cantrips" => [{ "id" => cantrip.id, "name" => cantrip.name, "level" => 0 }],
              "spells" => [{ "id" => leveled.id, "name" => leveled.name, "level" => 1 }]
            }
          }
        }
      }
    )

    sk = SheetKlass.create!(sheet: sheet, klass: klass, level: 1)

    service = LevelUpService.new(sheet_id: sheet.id, klass_id: klass.id, levels: 1)
    service.send(:persist_known_spells!, sk, from_level: 2, to_level: 2)

    ids = SheetKnownSpell.where(sheet_klass_id: sk.id).pluck(:spell_id)
    expect(ids).to include(cantrip.id, leveled.id)
  end

  describe '.seed_level_one_known_spells!' do
    let(:role) { Role.find_or_create_by!(name: 'player') }
    let(:user) do
      User.create!(
        email: "lu_seed1_#{SecureRandom.hex(4)}@example.com",
        username: "luseed#{SecureRandom.hex(4)}",
        password: 'password1', password_confirmation: 'password1',
        role_id: role.id
      )
    end
    let(:race) { Race.find_by(api_index: 'human') || Race.create!(name: 'Humano', api_index: 'human') }

    it 'preenche truques e magias de L1 para warlock antes do primeiro LevelUpGuard' do
      warlock = Klass.find_by(api_index: 'warlock')
      skip 'Klass warlock ausente' unless warlock

      sc = SpellRules.sc_for(warlock, 1)
      skip 'spellcasting L1 ausente' unless sc && sc.spells_known.to_i.positive?

      sub = SubKlass.find_by(klass_id: warlock.id) ||
            SubKlass.create!(klass: warlock, api_index: 'fiend', name: 'Ínfero')

      character = Character.create!(user: user, name: "Warlock seed #{SecureRandom.hex(2)}", background: 'Test')
      sheet = Sheet.create!(
        character: character,
        race_id: race.id,
        str: 10, dex: 10, con: 12, int: 10, wis: 10, cha: 16,
        hp_max: 10, hp_current: 10,
        metadata: { 'class_choices' => { 'per_level' => { '1' => { 'skills' => %w[Arcanismo Enganação] } } } }
      )
      SheetKlass.create!(sheet: sheet, klass: warlock, sub_klass_id: sub.id, level: 1)

      described_class.seed_level_one_known_spells!(sheet_id: sheet.id, klass_id: warlock.id)
      sk = sheet.sheet_klasses.find_by!(klass_id: warlock.id)

      cantrips = SheetKnownSpell.where(sheet_klass_id: sk.id).joins(:spell).where(spells: { level: 0 }).count
      leveled = SheetKnownSpell.where(sheet_klass_id: sk.id).joins(:spell).where('spells.level > 0').count

      expect(cantrips).to be >= sc.cantrips_known.to_i
      expect(leveled).to be >= sc.spells_known.to_i
    end
  end

  describe 'auto-heal de string crua / typo via SpellResolver' do
    # Phase 12 (causa raiz spells): antes, qualquer entry com `id` nao numerico
    # era descartada silenciosamente (`(sp["id"]).to_i == 0`). Agora passa por
    # SpellResolver, vira SheetKnownSpell e o metadata eh re-escrito no
    # formato canonico {id:Int, name:String, level:Int}.
    let(:role) { Role.find_or_create_by!(name: 'player') }
    let(:user) do
      User.create!(
        email: "lu_heal_#{SecureRandom.hex(4)}@example.com",
        username: "luheal#{SecureRandom.hex(4)}",
        password: 'password1', password_confirmation: 'password1',
        role_id: role.id
      )
    end
    let(:race) { Race.create!(name: 'Spec Race', api_index: "spec_race_#{SecureRandom.hex(4)}") }
    let(:klass) do
      Klass.create!(name: 'Spec Wizard', api_index: "spec_wizard_#{SecureRandom.hex(4)}", hit_die: 6, subclass_level: 2)
    end
    let(:character) { Character.create!(user: user, name: 'Spec PC', background: 'Test') }

    let!(:chill_touch) do
      Spell.find_by(api_index: 'chill-touch') ||
        FactoryBot.create(:spell, name: 'Toque Arrepiante', api_index: 'chill-touch', level: 0)
    end

    def build_sheet_with(per_level_l2)
      sheet = Sheet.create!(
        character: character, race_id: race.id,
        str: 10, dex: 10, con: 10, int: 16, wis: 10, cha: 10,
        hp_max: 8, hp_current: 8,
        metadata: { 'class_choices' => { 'per_level' => { '2' => per_level_l2 } } }
      )
      sk = SheetKlass.create!(sheet: sheet, klass: klass, level: 1)
      [sheet, sk]
    end

    it 'cria SheetKnownSpell quando cantrips tem hash com id textual com typo' do
      sheet, sk = build_sheet_with('cantrips' => [{ 'id' => 'Toque arrepiane', 'name' => 'Toque arrepiane' }])

      service = LevelUpService.new(sheet_id: sheet.id, klass_id: klass.id, levels: 1)
      service.send(:persist_known_spells!, sk, from_level: 2, to_level: 2)

      expect(SheetKnownSpell.where(sheet_klass_id: sk.id).pluck(:spell_id)).to include(chill_touch.id)
    end

    it 'reescreve o metadata para o formato canonico {id:Int} apos resolver' do
      sheet, sk = build_sheet_with('cantrips' => [{ 'id' => 'Toque arrepiane', 'name' => 'Toque arrepiane' }])

      service = LevelUpService.new(sheet_id: sheet.id, klass_id: klass.id, levels: 1)
      service.send(:persist_known_spells!, sk, from_level: 2, to_level: 2)

      sheet.reload
      canon = sheet.metadata.dig('class_choices', 'per_level', '2', 'cantrips', 0)
      expect(canon).to eq('id' => chill_touch.id, 'name' => 'Toque Arrepiante', 'level' => 0)
    end

    it 'aceita string crua (nao apenas Hash) em cantrips' do
      sheet, sk = build_sheet_with('cantrips' => ['Toque arrepiane'])

      service = LevelUpService.new(sheet_id: sheet.id, klass_id: klass.id, levels: 1)
      service.send(:persist_known_spells!, sk, from_level: 2, to_level: 2)

      expect(SheetKnownSpell.where(sheet_klass_id: sk.id).pluck(:spell_id)).to include(chill_touch.id)
    end

    it 'loga warn quando nao resolve (em vez de descartar silenciosamente)' do
      sheet, sk = build_sheet_with('cantrips' => [{ 'id' => 'Magia Inexistente XYZ', 'name' => 'Magia Inexistente XYZ' }])

      expect(Rails.logger).to receive(:warn).with(/spell nao resolvida.*Magia Inexistente XYZ/).at_least(:once)

      service = LevelUpService.new(sheet_id: sheet.id, klass_id: klass.id, levels: 1)
      service.send(:persist_known_spells!, sk, from_level: 2, to_level: 2)
    end
  end

  describe '#mirror_known_spells_into_selections! (fix magias-fantasma)' do
    let(:role) { Role.find_or_create_by!(name: 'player') }
    let(:user) do
      User.create!(
        email: "lu_mir_#{SecureRandom.hex(4)}@example.com",
        username: "lumir#{SecureRandom.hex(4)}",
        password: 'password1', password_confirmation: 'password1',
        role_id: role.id
      )
    end
    let(:race) { Race.create!(name: 'Spec Race', api_index: "spec_race_#{SecureRandom.hex(4)}") }
    let(:wizard) do
      Klass.find_by(api_index: 'wizard') ||
        Klass.create!(name: 'Mago Spec', api_index: 'wizard', hit_die: 6, subclass_level: 2)
    end

    it 'reflete SheetKnownSpell (auto-fill) em spell_selections e é idempotente' do
      cantrip = FactoryBot.create(:spell, level: 0, name: "Mir Cantrip #{SecureRandom.hex(2)}", api_index: "mirc_#{SecureRandom.hex(4)}")
      leveled = FactoryBot.create(:spell, level: 2, name: "Mir Spell #{SecureRandom.hex(2)}", api_index: "mirs_#{SecureRandom.hex(4)}")

      character = Character.create!(user: user, name: 'Mir PC', background: 'Test')
      sheet = Sheet.create!(
        character: character, race_id: race.id,
        str: 10, dex: 10, con: 10, int: 16, wis: 10, cha: 10, hp_max: 8, hp_current: 8,
        metadata: {}
      )
      sk = SheetKlass.create!(sheet: sheet, klass: wizard, level: 3)

      # Simula o que o auto-fill do provisionamento cria: SheetKnownSpell sem source,
      # ausente de spell_selections (= "fantasma").
      SheetKnownSpell.create!(sheet_klass_id: sk.id, spell_id: cantrip.id)
      SheetKnownSpell.create!(sheet_klass_id: sk.id, spell_id: leveled.id)

      svc = LevelUpService.new(sheet_id: sheet.id, klass_id: wizard.id, levels: 1)
      svc.send(:mirror_known_spells_into_selections!, sk)
      svc.send(:mirror_known_spells_into_selections!, sk) # roda 2x → não duplica

      sel = sheet.reload.metadata['spell_selections']
      expect(sel['cantrips'].map(&:to_s)).to contain_exactly(cantrip.id.to_s)
      expect(sel['known'].map(&:to_s)).to contain_exactly(leveled.id.to_s)
      # Mago: spellbook espelha as conhecidas de nível > 0.
      expect(sel['spellbook'].map(&:to_s)).to contain_exactly(leveled.id.to_s)
    end
  end
end
