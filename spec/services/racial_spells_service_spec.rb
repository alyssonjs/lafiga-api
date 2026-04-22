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

