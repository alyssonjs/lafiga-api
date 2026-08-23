# frozen_string_literal: true

require 'rails_helper'

# Magia inata (racial/talento) tem orcamento proprio em
# `sheet_known_spells.uses_remaining` — nao gasta espaco de magia. Zerar
# `spell_slots_used` no descanso NAO a devolvia, porque ela nunca esteve la.
RSpec.describe 'descanso restaura magia inata' do
  let(:sheet) { create(:sheet, current_level: 5) }
  let!(:sheet_klass) { create(:sheet_klass, sheet: sheet, level: 5) }

  def innate!(nome, per_rest)
    sufixo = SecureRandom.hex(3)
    spell = Spell.create!(name: "#{nome} #{sufixo}", api_index: "spec-innate-#{sufixo}", level: 1, desc: 'x')
    SheetKnownSpell.create!(sheet_klass: sheet_klass, spell: spell, gained_at_class_level: 3,
                            source: 'race', uses_per_rest: per_rest, uses_remaining: 0)
  end

  it 'descanso LONGO devolve o uso de LR' do
    lr = innate!('Repreensão Infernal', 'LR')

    Sheets::Runtime::ApplyLongRestService.call(sheet)

    expect(lr.reload.uses_remaining).to eq(1)
  end

  it 'descanso longo devolve tambem o de SR (tudo que volta no curto volta no longo)' do
    sr = innate!('Truque de SR', 'SR')

    Sheets::Runtime::ApplyLongRestService.call(sheet)

    expect(sr.reload.uses_remaining).to eq(1)
  end

  it 'REGRESSAO: descanso CURTO nao devolve o de LR' do
    lr = innate!('Repreensão Infernal', 'LR')
    sr = innate!('Truque de SR', 'SR')

    Sheets::Runtime::ApplyShortRestService.call(sheet)

    expect(lr.reload.uses_remaining).to eq(0)
    expect(sr.reload.uses_remaining).to eq(1)
  end

  it 'magia SEM usos proprios (de classe) nao e tocada' do
    sufixo = SecureRandom.hex(3)
    spell = Spell.create!(name: "Bola de Fogo #{sufixo}", api_index: "spec-class-#{sufixo}", level: 3, desc: 'x')
    de_classe = SheetKnownSpell.create!(sheet_klass: sheet_klass, spell: spell,
                                        gained_at_class_level: 5, source: 'class')

    Sheets::Runtime::ApplyLongRestService.call(sheet)

    # A coluna tem default 0 no banco; o que importa e que o descanso NAO a
    # promoveu a 1 — magia de classe recupera pelo espaco, nao por uso proprio.
    expect(de_classe.reload.uses_per_rest).to be_nil
    expect(de_classe.uses_remaining).to eq(0)
  end
end
