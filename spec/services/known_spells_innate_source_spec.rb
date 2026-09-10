# frozen_string_literal: true

require 'rails_helper'

# F1 — a ficha diz de ONDE vem a magia inata, com que limite e em que modo.
#
# O irmão `known_spells_usage_columns_spec` (D6) prende o "1/LDesc"; este prende
# o "Legado Abissal, nível 3+". A diferença importa: antes desta fase a ficha
# mostrava um chip genérico "RAÇA" e um contador, sem dizer qual traço concedeu
# a magia nem que ela não gasta espaço.
#
# ⚠️ A propriedade mais importante aqui não é o rótulo: é que o índice ANOTA e
# nunca altera. Uma ficha sem atrelagem no catálogo tem de sair exatamente como
# saía — foi assim que a paridade das 69 fichas reais fechou byte a byte.
RSpec.describe 'F1 — origem, limite e modo da magia inata', type: :service do
  let(:user) { create(:user) }
  let(:character) { create(:character, user: user) }
  let(:race) { create(:race, name: 'Tiefling F1', api_index: 'tiefling-f1') }
  # ⚠️ O nome é o REAL ('Abissal'), não 'Abissal F1'. A regra que evita
  # "Abissal · Legado Abissal" é de contenção de texto, e um sufixo de fixture
  # quebrava-a — o teste passava a medir o fixture em vez da regra.
  let(:sub_race) { create(:sub_race, name: 'Abissal', api_index: 'abissal-f1', race: race) }
  let(:klass) do
    Klass.find_by(api_index: 'barbarian') || create(:klass, name: 'Bárbaro', api_index: 'barbarian', hit_die: 12)
  end
  let(:sheet) do
    create(:sheet, character: character, race: race, sub_race: sub_race,
                   str: 14, dex: 12, con: 14, int: 10, wis: 10, cha: 14)
  end
  let(:sheet_klass) { create(:sheet_klass, sheet: sheet, klass: klass, level: 5) }

  let!(:raio) { create(:spell, name: 'Raio Adoecente F1', level: 1) }
  let!(:truque) { create(:spell, name: 'Taumaturgia F1', level: 0) }

  before { sheet_klass }

  def linha(spell)
    KnownSpellsAggregator.new(sheet).call[:known_by_level].values.flatten.find { |r| r[:id] == spell.id }
  end

  def conhece!(spell, **attrs)
    SheetKnownSpell.create!({ sheet_klass: sheet_klass, spell: spell, source: 'race' }.merge(attrs))
  end

  describe 'o que a mesa lê' do
    it 'magia de legado diz o traço, o limite e o nível' do
      conhece!(raio, uses_per_rest: 'LR', uses_remaining: 1)
      SpellSource.create!(source_type: 'SubRace', source_id: sub_race.id, spell: raio,
                          origin: 'derived', casting_mode: 'uses_per_rest',
                          uses_per_long_rest: 1, min_character_level: 3,
                          notes: 'trait: abyssal_legacy')

      expect(linha(raio)[:innate_source][:label]).to eq('Legado Abissal, 1/descanso longo, nível 3+')
    end

    it 'truque à vontade não inventa nível mínimo' do
      conhece!(truque)
      SpellSource.create!(source_type: 'Race', source_id: race.id, spell: truque,
                          origin: 'derived', casting_mode: 'at_will')

      rotulo = linha(truque)[:innate_source][:label]
      expect(rotulo).to include('à vontade')
      expect(rotulo).not_to include('nível')
    end

    it 'diz explicitamente que NÃO gasta espaço de magia' do
      # É o pedido: "nem sempre usam poço de magia, por exemplo tiefling".
      conhece!(truque)
      SpellSource.create!(source_type: 'Race', source_id: race.id, spell: truque,
                          origin: 'derived', casting_mode: 'at_will')

      expect(linha(truque)[:innate_source][:uses_spell_slot]).to be(false)
    end
  end

  describe '⚠️ o rótulo não repete nem duplica' do
    it 'traço que só repete o nome da magia cede lugar à raça' do
      # `minor_illusion_cantrip` chama-se "Truque: Ilusão Menor" e a magia
      # chama-se "Ilusão Menor" — repetir não informa.
      magia = create(:spell, name: 'Taumaturgia F1 Repetida', level: 0)
      conhece!(magia)
      SpellSource.create!(source_type: 'Race', source_id: race.id, spell: magia,
                          origin: 'derived', casting_mode: 'at_will',
                          notes: 'trait: thaumaturgy_cantrip')

      # o traço real do catálogo ("Presença Sobrenatural") não é redundante,
      # então a procedência traz as duas pontas
      expect(linha(magia)[:innate_source][:label]).to start_with('Tiefling F1')
    end

    it 'traço que já contém a sub-raça não vira "Abissal · Legado Abissal"' do
      conhece!(raio, uses_per_rest: 'LR')
      SpellSource.create!(source_type: 'SubRace', source_id: sub_race.id, spell: raio,
                          origin: 'derived', casting_mode: 'uses_per_rest',
                          uses_per_long_rest: 1, notes: 'trait: abyssal_legacy')

      expect(linha(raio)[:innate_source][:label]).not_to include('·')
    end
  end

  describe '⚠️ anota, nunca altera' do
    it 'magia SEM atrelagem sai sem o campo — e com tudo o que já tinha' do
      conhece!(raio, uses_per_rest: 'LR', uses_remaining: 1)

      row = linha(raio)
      expect(row).not_to have_key(:innate_source)
      expect(row[:uses_per_rest]).to eq('LR')
      expect(row[:uses_remaining]).to eq(1)
      expect(row[:known_source]).to eq('race')
    end

    it 'a atrelagem NÃO mexe nas colunas de uso, que continuam do SheetKnownSpell' do
      # O catálogo diz 1/descanso longo; quem manda no contador é a ficha.
      conhece!(raio, uses_per_rest: 'LR', uses_remaining: 0)
      SpellSource.create!(source_type: 'SubRace', source_id: sub_race.id, spell: raio,
                          origin: 'derived', casting_mode: 'uses_per_rest',
                          uses_per_long_rest: 1, notes: 'trait: abyssal_legacy')

      row = linha(raio)
      expect(row[:uses_remaining]).to eq(0)  # gastou; o catálogo não o repõe
      expect(row[:uses_per_rest]).to eq('LR')
    end

    it 'atrelagem de OUTRA raça não contamina a ficha' do
      outra = create(:race, name: 'Élfico F1', api_index: 'elfico-f1')
      conhece!(raio, uses_per_rest: 'LR')
      SpellSource.create!(source_type: 'Race', source_id: outra.id, spell: raio,
                          origin: 'derived', casting_mode: 'at_will')

      expect(linha(raio)).not_to have_key(:innate_source)
    end
  end

  describe 'degrada sem derrubar a ficha' do
    it 'catálogo indisponível devolve índice vazio, não exceção' do
      allow(SpellSource).to receive(:where).and_raise(ActiveRecord::StatementInvalid, 'tabela ausente')
      conhece!(raio, uses_per_rest: 'LR')

      expect { linha(raio) }.not_to raise_error
      expect(linha(raio)[:uses_per_rest]).to eq('LR')
    end

    it 'ficha sem raça nem sub-raça não consulta nada' do
      sem_raca = create(:sheet, character: create(:character, user: user),
                                str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10)
      expect(Spells::InnateSourceIndex.new(sem_raca).call).to eq({})
    end
  end
end
