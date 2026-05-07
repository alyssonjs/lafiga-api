# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RacialSpellsService, type: :service do
  let(:user) { create(:user) }
  let(:character) { create(:character, user: user) }
  let(:race) { Race.find_by(api_index: 'drow') || create(:race, name: 'Drow', api_index: 'drow') }
  let(:sub_race) do
    SubRace.find_or_create_by!(race: race, api_index: 'racial-spells-spec-sub') do |sr|
      sr.name = 'Sub (spec)'
    end
  end
  let(:klass) do
    Klass.find_by(api_index: 'wizard') || create(:klass, name: 'Mago', api_index: 'wizard', hit_die: 6, subclass_level: 2)
  end
  let(:sheet) do
    create(:sheet,
      character: character,
      race: race,
      sub_race: sub_race,
      str: 10, dex: 14, con: 12, int: 16, wis: 10, cha: 14
    )
  end
  let(:sheet_klass) { create(:sheet_klass, sheet: sheet, klass: klass, level: 1) }

  # Criar magias de teste
  let!(:dancing_lights) { create(:spell, name: 'Luz Dançante', level: 0) }
  let!(:faerie_fire) { create(:spell, name: 'Fogo das Fadas', level: 1) }
  let!(:darkness) { create(:spell, name: 'Escuridão', level: 2) }

  before do
    sheet_klass # Garantir que existe sheet_klass
  end

  describe '#call' do
    context 'Drow nível 1' do
      let(:race_rule) do
        {
          race_id: 'drow',
          innate_spells: [
            { level: 1, spells: ['Luz Dançante'], ability: 'CHA', uses: nil }
          ]
        }
      end

      it 'aplica cantrip Luz Dançante' do
        result = described_class.call(
          sheet: sheet,
          race_rule: race_rule,
          character_level: 1
        )

        expect(result).to be_success
        known_spell = SheetKnownSpell.find_by(sheet_klass: sheet_klass, spell: dancing_lights)
        expect(known_spell).to be_present
        expect(known_spell.source).to eq('race')
        expect(known_spell.uses_per_rest).to be_nil # Cantrip não tem usos limitados
      end
    end

    context 'quando sync de progressão gravou a magia inata como class primeiro' do
      let(:race_rule) do
        {
          race_id: 'drow',
          innate_spells: [
            { level: 1, spells: ['Luz Dançante'], ability: 'CHA', uses: nil }
          ]
        }
      end

      before do
        SheetKnownSpell.create!(sheet_klass: sheet_klass, spell: dancing_lights, source: 'class')
      end

      it 'promove para race (chips RAÇA / known_source no summary)' do
        result = described_class.call(
          sheet: sheet,
          race_rule: race_rule,
          character_level: 1
        )

        expect(result).to be_success
        known = SheetKnownSpell.find_by(sheet_klass: sheet_klass, spell: dancing_lights)
        expect(known.source).to eq('race')
      end
    end

    context 'quando já existe como subclass, não sobrescreve com race' do
      let(:race_rule) do
        {
          race_id: 'drow',
          innate_spells: [
            { level: 1, spells: ['Luz Dançante'], ability: 'CHA', uses: nil }
          ]
        }
      end

      before do
        SheetKnownSpell.create!(sheet_klass: sheet_klass, spell: dancing_lights, source: 'subclass')
      end

      it 'mantém subclass' do
        described_class.call(sheet: sheet, race_rule: race_rule, character_level: 1)
        known = SheetKnownSpell.find_by(sheet_klass: sheet_klass, spell: dancing_lights)
        expect(known.source).to eq('subclass')
      end
    end

    context 'Drow nível 3' do
      let(:race_rule) do
        {
          race_id: 'drow',
          innate_spells: [
            { level: 1, spells: ['Luz Dançante'], ability: 'CHA', uses: nil },
            { level: 3, spells: ['Fogo das Fadas'], ability: 'CHA', uses: 'LR' }
          ]
        }
      end

      it 'aplica Luz Dançante e Fogo das Fadas' do
        result = described_class.call(
          sheet: sheet,
          race_rule: race_rule,
          character_level: 3
        )

        expect(result).to be_success
        
        # Cantrip
        dancing_spell = SheetKnownSpell.find_by(sheet_klass: sheet_klass, spell: dancing_lights)
        expect(dancing_spell).to be_present
        expect(dancing_spell.uses_per_rest).to be_nil
        
        # Magia com usos limitados
        faerie_spell = SheetKnownSpell.find_by(sheet_klass: sheet_klass, spell: faerie_fire)
        expect(faerie_spell).to be_present
        expect(faerie_spell.source).to eq('race')
        expect(faerie_spell.uses_per_rest).to eq('LR')
        expect(faerie_spell.uses_remaining).to eq(1)
      end
    end

    context 'Drow nível 5 (todas magias)' do
      let(:race_rule) do
        {
          race_id: 'drow',
          innate_spells: [
            { level: 1, spells: ['Luz Dançante'], ability: 'CHA', uses: nil },
            { level: 3, spells: ['Fogo das Fadas'], ability: 'CHA', uses: 'LR' },
            { level: 5, spells: ['Escuridão'], ability: 'CHA', uses: 'LR' }
          ]
        }
      end

      it 'aplica todas as três magias' do
        result = described_class.call(
          sheet: sheet,
          race_rule: race_rule,
          character_level: 5
        )

        expect(result).to be_success
        expect(SheetKnownSpell.where(sheet_klass: sheet_klass, source: 'race').count).to eq(3)
        
        darkness_spell = SheetKnownSpell.find_by(sheet_klass: sheet_klass, spell: darkness)
        expect(darkness_spell).to be_present
        expect(darkness_spell.uses_per_rest).to eq('LR')
      end
    end

    context 'Drow nível 2 (ainda não tem Fogo das Fadas)' do
      let(:race_rule) do
        {
          race_id: 'drow',
          innate_spells: [
            { level: 1, spells: ['Luz Dançante'], ability: 'CHA', uses: nil },
            { level: 3, spells: ['Fogo das Fadas'], ability: 'CHA', uses: 'LR' }
          ]
        }
      end

      it 'aplica apenas Luz Dançante' do
        result = described_class.call(
          sheet: sheet,
          race_rule: race_rule,
          character_level: 2
        )

        expect(result).to be_success
        expect(SheetKnownSpell.where(sheet_klass: sheet_klass, source: 'race').count).to eq(1)
        expect(SheetKnownSpell.exists?(sheet_klass: sheet_klass, spell: faerie_fire)).to be_falsey
      end
    end

    context 'quando spell não existe no banco' do
      let(:race_rule) do
        {
          race_id: 'test',
          innate_spells: [
            { level: 1, spells: ['Magia Inexistente'], ability: 'CHA', uses: nil }
          ]
        }
      end

      it 'não falha mas loga warning' do
        expect(Rails.logger).to receive(:warn).with(/Spell not found/)
        
        result = described_class.call(
          sheet: sheet,
          race_rule: race_rule,
          character_level: 1
        )

        expect(result).to be_success
        expect(SheetKnownSpell.where(sheet_klass: sheet_klass, source: 'race').count).to eq(0)
      end
    end

    context 'formato RaceRules.apply (tiefling infernal, traits -> innate_spells)' do
      let(:race) { Race.find_by(api_index: 'tiefling') || create(:race, name: 'Tiefling', api_index: 'tiefling') }
      let!(:spell_th) { create(:spell, name: 'Taumaturgia', level: 0, api_index: 'thaumaturgy') }
      let!(:spell_hr) { create(:spell, name: 'Repreensão Infernal', level: 1, api_index: 'hellish-rebuke') }
      let!(:spell_dk) { create(:spell, name: 'Escuridão', level: 2, api_index: 'darkness') }

      let(:race_rule) do
        RaceRules.apply(race_id: 'tiefling', subrace_id: 'infernal', choices: {})
      end

      it 'nível 5 aplica cantrip base + legado infernal variant' do
        described_class.call(sheet: sheet, race_rule: race_rule, character_level: 5)

        ids = SheetKnownSpell.where(sheet_klass: sheet_klass, source: 'race').joins(:spell).pluck('spells.api_index').sort
        expect(ids).to include('thaumaturgy', 'hellish-rebuke', 'darkness')
      end
    end

    context 'quando sheet não tem sheet_klass' do
      before do
        sheet.sheet_klasses.destroy_all
      end

      let(:race_rule) do
        {
          race_id: 'drow',
          innate_spells: [
            { level: 1, spells: ['Luz Dançante'], ability: 'CHA', uses: nil }
          ]
        }
      end

      it 'retorna sheet mas não aplica magias' do
        expect(Rails.logger).to receive(:warn).with(/No sheet_klass found/)
        
        result = described_class.call(
          sheet: sheet,
          race_rule: race_rule,
          character_level: 1
        )

        expect(result).to be_success
        expect(result.result).to eq(sheet)
      end
    end

    context 'Drow PHB-PT: aplica nomes canonicos via api_index (nao "Globos de Luz")' do
      # Regressao: o YAML race_rules.yml#drow_magic.grants.spells lista
      # `spell: dancing-lights` (api_index canonico). Antes do fix de
      # canonicalizacao, a Spell na DB tinha `name: 'Globos De Luz'`,
      # divergindo do PHB-PT ('Luzes Dançantes') e do `description` do
      # trait. Resultado: o jogador via "Globos de Luz" na ficha Drow e o
      # wizard nao casava `'Luzes Dançantes'` no spell picker (`useRaceGrantedSpellLocks`).
      let!(:dancing_lights_canonical) do
        Spell.find_by(api_index: 'dancing-lights') ||
          create(:spell, api_index: 'dancing-lights', name: 'Luzes Dançantes', level: 0)
      end
      let!(:faerie_fire_canonical) do
        Spell.find_by(api_index: 'faerie-fire') ||
          create(:spell, api_index: 'faerie-fire', name: 'Fogo das Fadas', level: 1)
      end
      let!(:darkness_canonical) do
        Spell.find_by(api_index: 'darkness') ||
          create(:spell, api_index: 'darkness', name: 'Escuridão', level: 2)
      end

      let(:race_rule_drow_l5) do
        # Mesma estrutura que `RaceRules.extract_innate_spells_from_traits`
        # devolve em producao para `drow_magic.grants.spells` no YAML.
        {
          race_id: 'drow',
          innate_spells: [
            { name: 'dancing-lights', unlocked_at_level: 1, ability: 'CHA', uses: nil },
            { name: 'faerie-fire',    unlocked_at_level: 3, ability: 'CHA', uses: 'LR' },
            { name: 'darkness',       unlocked_at_level: 5, ability: 'CHA', uses: 'LR' }
          ]
        }
      end

      it 'cria SheetKnownSpell para Luzes Dançantes (nao "Globos de Luz")' do
        described_class.call(sheet: sheet, race_rule: race_rule_drow_l5, character_level: 5)

        ks = SheetKnownSpell.where(sheet_klass: sheet_klass, source: 'race').includes(:spell).map(&:spell)
        names = ks.map(&:name).sort
        expect(names).to include('Luzes Dançantes'), "esperava 'Luzes Dançantes', recebeu #{names.inspect}"
        expect(names).not_to include('Globos De Luz')
        expect(names).not_to include('Globos de Luz')
      end

      it 'cria as 3 magias raciais com api_indices canonicos no nivel 5' do
        described_class.call(sheet: sheet, race_rule: race_rule_drow_l5, character_level: 5)

        api_indices = SheetKnownSpell.where(sheet_klass: sheet_klass, source: 'race').joins(:spell).pluck('spells.api_index').sort
        expect(api_indices).to eq(%w[dancing-lights darkness faerie-fire])
      end

      it 'aplica apenas Luzes Dançantes no nivel 1 (faerie-fire/darkness exigem nivel 3/5)' do
        described_class.call(sheet: sheet, race_rule: race_rule_drow_l5, character_level: 1)

        api_indices = SheetKnownSpell.where(sheet_klass: sheet_klass, source: 'race').joins(:spell).pluck('spells.api_index').sort
        expect(api_indices).to eq(['dancing-lights'])
      end
    end

    context 'troca de raca: limpa magias raciais antigas antes de aplicar novas' do
      # Regressao: Drow → Tiefling antes deste fix mantinha Globos de Luz/Fogo
      # das Fadas (source: 'race') na ficha mesmo apos virar Tiefling, porque
      # `find_or_initialize_by` so adicionava as novas. RacialSpellsService.call
      # agora limpa todas as `source: 'race'` antes de re-aplicar — operacao
      # idempotente, segura para reprovision repetido.
      let!(:thaumaturgy) { create(:spell, name: 'Taumaturgia', level: 0) }

      before do
        # Estado simulando ficha vinda da raca anterior (Drow level 3).
        SheetKnownSpell.create!(sheet_klass: sheet_klass, spell: dancing_lights, source: 'race')
        SheetKnownSpell.create!(sheet_klass: sheet_klass, spell: faerie_fire, source: 'race', uses_per_rest: 'LR', uses_remaining: 1)
      end

      let(:race_rule_tiefling) do
        {
          race_id: 'tiefling',
          innate_spells: [
            { level: 1, spells: ['Taumaturgia'], ability: 'CHA', uses: nil }
          ]
        }
      end

      it 'remove magias raciais antigas mesmo quando a nova raca tem outras magias' do
        described_class.call(sheet: sheet, race_rule: race_rule_tiefling, character_level: 1)

        race_known = SheetKnownSpell.where(sheet_klass: sheet_klass, source: 'race').joins(:spell).pluck('spells.name').sort
        expect(race_known).to eq(['Taumaturgia'])
        expect(SheetKnownSpell.exists?(sheet_klass: sheet_klass, spell: dancing_lights)).to be(false)
        expect(SheetKnownSpell.exists?(sheet_klass: sheet_klass, spell: faerie_fire)).to be(false)
      end

      it 'remove magias raciais antigas mesmo quando a nova raca nao tem magias inatas' do
        described_class.call(sheet: sheet, race_rule: { race_id: 'human', innate_spells: [] }, character_level: 1)

        expect(SheetKnownSpell.where(sheet_klass: sheet_klass, source: 'race')).to be_empty
      end

      it 'preserva magias com `source: feat` ao trocar raca' do
        feat_only_spell = create(:spell, name: 'Magic Initiate Cantrip', level: 0)
        SheetKnownSpell.create!(sheet_klass: sheet_klass, spell: feat_only_spell, source: 'feat')

        described_class.call(sheet: sheet, race_rule: race_rule_tiefling, character_level: 1)

        feat_kept = SheetKnownSpell.find_by(sheet_klass: sheet_klass, spell: feat_only_spell)
        expect(feat_kept).to be_present
        expect(feat_kept.source).to eq('feat')
      end
    end
  end

  describe 'métodos do modelo SheetKnownSpell' do
    let!(:cantrip_known) do
      create(:sheet_known_spell,
        sheet_klass: sheet_klass,
        spell: dancing_lights,
        source: 'race',
        uses_per_rest: nil
      )
    end

    let!(:limited_spell) do
      create(:sheet_known_spell,
        sheet_klass: sheet_klass,
        spell: faerie_fire,
        source: 'race',
        uses_per_rest: 'LR',
        uses_remaining: 1
      )
    end

    describe '#cantrip?' do
      it 'retorna true para cantrip' do
        expect(cantrip_known.cantrip?).to be true
      end

      it 'retorna false para magia de nível' do
        expect(limited_spell.cantrip?).to be false
      end
    end

    describe '#has_uses?' do
      it 'retorna false para cantrip' do
        expect(cantrip_known.has_uses?).to be false
      end

      it 'retorna true para magia com usos limitados' do
        expect(limited_spell.has_uses?).to be true
      end
    end

    describe '#use_once!' do
      it 'decrementa usos restantes' do
        expect { limited_spell.use_once! }.to change { limited_spell.uses_remaining }.from(1).to(0)
      end

      it 'retorna false se usos esgotados' do
        limited_spell.update(uses_remaining: 0)
        expect(limited_spell.use_once!).to be false
      end
    end

    describe '#restore_uses!' do
      it 'restaura usos para o máximo' do
        limited_spell.update(uses_remaining: 0)
        limited_spell.restore_uses!
        expect(limited_spell.uses_remaining).to eq(1)
      end
    end
  end
end

