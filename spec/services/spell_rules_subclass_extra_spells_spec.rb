# frozen_string_literal: true

require 'rails_helper'

# Colegio do Conhecimento (Bardo) L6 — "Segredos Magicos Adicionais".
#
# Diretriz: front-lafiga/src/docs/class-feature-directives/bard/subclasses/
#           colegio-do-conhecimento.md  (ancoras F6.1, F6.4, F6.5)
#
# A regra: as 2 magias contam como magias de BARDO (F6.4) mas NAO ocupam o
# limite normal de conhecidas (F6.5). Antes desta exclusao elas viravam
# `SheetKnownSpell` como qualquer outra e INFLAVAM a contagem — o guard de
# level-up (`known_count < known_limit`) passava cedo demais, mascarando um
# deficit real, e o auto-preenchimento achava a ficha cheia.
#
# ⚠️ Contraste deliberado: os Segredos Magicos da CLASSE (L10/14/18) pelo PHB
# ESTAO inclusos na coluna Magias Conhecidas — esses continuam contando.
RSpec.describe SpellRules, 'magias extras de subclasse fora do limite' do
  let!(:role) { Role.find_or_create_by!(name: 'player') }
  let(:user) do
    User.create!(
      email: "lore_#{SecureRandom.hex(4)}@example.com",
      username: "lore#{SecureRandom.hex(4)}",
      password: 'password1', password_confirmation: 'password1', role_id: role.id
    )
  end
  let!(:human) { Race.find_or_create_by!(api_index: 'human') { |r| r.name = 'Humano' } }
  let!(:bard) do
    Klass.find_or_create_by!(api_index: 'bard') do |k|
      k.name = 'Bardo'
      k.hit_die = 8
      k.subclass_level = 3
    end
  end
  let!(:lore) do
    SubKlass.find_or_create_by!(api_index: 'lore') do |sk|
      sk.klass = bard
      sk.name = 'Colegio do Conhecimento'
    end
  end
  let!(:valor) do
    SubKlass.find_or_create_by!(api_index: 'valor') do |sk|
      sk.klass = bard
      sk.name = 'Colegio da Bravura'
    end
  end

  # 4 magias niveladas: 2 "normais" (L5) + 2 dos Segredos Adicionais (L6).
  def make_spell(label, level)
    slug = "#{label.parameterize}-#{SecureRandom.hex(3)}"
    Spell.create!(name: "#{label} #{SecureRandom.hex(3)}", level: level, api_index: slug)
  end

  let!(:normal_a) { make_spell('Normal A', 1) }
  let!(:normal_b) { make_spell('Normal B', 2) }
  let!(:extra_a)  { make_spell('Extra A', 3) }
  let!(:extra_b)  { make_spell('Extra B', 0) } # truque É permitido (F6.3)

  def build_sheet_klass(sub_klass:, with_l6_extras: true)
    character = Character.create!(user: user, name: 'Bardo do Conhecimento', background: 'Artista')
    per_level = { '5' => { 'spells' => [] } }
    if with_l6_extras
      per_level['6'] = {
        'learn_any_class_spells' => [
          { 'id' => extra_a.id.to_s, 'name' => extra_a.name },
          { 'id' => extra_b.id.to_s, 'name' => extra_b.name }
        ]
      }
    end
    sheet = Sheet.create!(
      character: character, race_id: human.id,
      str: 8, dex: 14, con: 12, int: 12, wis: 10, cha: 17,
      hp_max: 40, hp_current: 40,
      race_summary: { 'name' => 'Humano' }, class_summary: {},
      background_summary: { 'name' => 'Artista' },
      metadata: { 'class_choices' => { 'per_level' => per_level } }
    )
    sk = SheetKlass.create!(sheet: sheet, klass: bard, level: 6, sub_klass: sub_klass)
    # TODAS viram SheetKnownSpell — inclusive as extras (elas aparecem na ficha).
    [normal_a, normal_b, extra_a, extra_b].each do |sp|
      SheetKnownSpell.create!(sheet_klass_id: sk.id, spell_id: sp.id)
    end
    sk
  end

  it 'F6.5 — as 2 magias do L6 do Conhecimento NAO entram na contagem' do
    sk = build_sheet_klass(sub_klass: lore)
    counts = described_class.known_counts_for(sk)
    # 2 niveladas normais + extra_a (nivel 3) excluida → 2, nao 3.
    expect(counts[:spells]).to eq(2)
    # O truque extra tambem sai da contagem de truques.
    expect(counts[:cantrips]).to eq(0)
  end

  it 'F6.4 — mas elas CONTINUAM existindo como magias conhecidas na ficha' do
    sk = build_sheet_klass(sub_klass: lore)
    # A exclusao é só da CONTAGEM: as linhas seguem lá (a ficha as exibe).
    expect(SheetKnownSpell.where(sheet_klass_id: sk.id).count).to eq(4)
    expect(described_class.subclass_extra_known_spell_ids(sk)).to match_array([extra_a.id, extra_b.id])
  end

  it 'F6.5b — outra subclasse de Bardo nao ganha a excecao' do
    # A Bravura nao tem Segredos Adicionais: mesmo com a chave no metadata (por
    # engano/legado), as magias contam normalmente.
    sk = build_sheet_klass(sub_klass: valor)
    expect(described_class.subclass_extra_known_spell_ids(sk)).to eq([])
    expect(described_class.known_counts_for(sk)[:spells]).to eq(3)
  end

  it 'F6.5c — sem escolhas no L6, a contagem é a normal' do
    sk = build_sheet_klass(sub_klass: lore, with_l6_extras: false)
    expect(described_class.subclass_extra_known_spell_ids(sk)).to eq([])
    expect(described_class.known_counts_for(sk)[:spells]).to eq(3)
  end

  it 'F6.5d — ids nao numericos no metadata sao ignorados sem estourar' do
    sk = build_sheet_klass(sub_klass: lore)
    sheet = sk.sheet
    meta = sheet.metadata
    meta['class_choices']['per_level']['6']['learn_any_class_spells'] = [
      { 'id' => 'Toque Arrepiante', 'name' => 'Toque Arrepiante' }, # nome, nao id
      extra_a.id.to_s
    ]
    sheet.update!(metadata: meta)
    sk.reload
    # So o id resolvivel entra na exclusao; o resto nao quebra a contagem.
    expect(described_class.subclass_extra_known_spell_ids(sk)).to eq([extra_a.id])
  end
end
