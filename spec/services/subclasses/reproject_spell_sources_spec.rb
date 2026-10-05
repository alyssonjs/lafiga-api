# frozen_string_literal: true

require 'rails_helper'

# A reprojeção de `SpellSource` a partir do `levels_json` GRAVADO.
#
# ⚠️ O buraco que ela fecha: a derivação vivia só no import. Editar
# `grants.spells` pela página não mexia em `SpellSource` nenhum — e é dele que a
# ficha tira as magias sempre preparadas. O mestre via a regra nova na página e
# a ficha seguia com a lista velha, sem erro em lugar nenhum.
RSpec.describe Subclasses::ReprojectSpellSources do
  let(:klass) do
    Klass.find_by(api_index: 'druid') ||
      Klass.create!(name: 'Druida SO', api_index: 'druid', hit_die: 8)
  end
  let(:sub) do
    SubKlass.create!(name: 'Círculo SO', api_index: "circulo-so-#{SecureRandom.hex(3)}", klass: klass)
  end
  let!(:cura)  { create(:spell, name: 'Curar Ferimentos SO') }
  let!(:nevoa) { create(:spell, name: 'Névoa Obscurecente SO') }

  def grava_niveis(mapa)
    sub.update!(levels_json: [{ 'level' => 3,
                                'grants' => { 'spells' => { 'always_prepared' => mapa } } }])
  end

  def fontes
    SpellSource.where(source_type: 'SubKlass', source_id: sub.id, always_prepared: true)
  end

  it 'cria as fontes a partir do que está GRAVADO' do
    grava_niveis('3' => [cura.name, nevoa.name])

    r = described_class.call(sub)

    expect(fontes.pluck(:spell_id)).to match_array([cura.id, nevoa.id])
    expect(fontes.pluck(:min_class_level).uniq).to eq([3])
    expect(r.criadas).to eq(2)
  end

  it 'REMOVE a fonte cuja magia saiu da regra — o "SpellSource podre" do plano' do
    grava_niveis('3' => [cura.name, nevoa.name])
    described_class.call(sub)

    grava_niveis('3' => [cura.name])
    r = described_class.call(sub)

    expect(fontes.pluck(:spell_id)).to eq([cura.id])
    expect(r.removidas).to eq(1)
  end

  it 'atualiza o nível mínimo quando a regra muda de nível' do
    grava_niveis('3' => [cura.name])
    described_class.call(sub)

    grava_niveis('5' => [cura.name])
    r = described_class.call(sub)

    expect(fontes.find_by(spell_id: cura.id).min_class_level).to eq(5)
    expect(r.atualizadas).to eq(1)
  end

  it '⚠️ não toca nas fontes `expanded` — nascem do TOPO do YAML, fora do levels_json' do
    expandida = SpellSource.create!(source_type: 'SubKlass', source_id: sub.id, spell_id: nevoa.id,
                                    always_prepared: false, notes: 'expanded')
    grava_niveis('3' => [cura.name])

    described_class.call(sub)

    expect(SpellSource.exists?(expandida.id)).to be(true)
  end

  it 'relata o rótulo que não casou com magia nenhuma, em vez de descartar calado' do
    grava_niveis('3' => ['Magia Que Não Existe'])

    r = described_class.call(sub)

    expect(r.nao_resolvidas).to eq(['Magia Que Não Existe'])
    expect(fontes.count).to eq(0)
  end

  it 'é idempotente: a segunda passagem não cria, não muda e não remove' do
    grava_niveis('3' => [cura.name])
    described_class.call(sub)

    r = described_class.call(sub)

    expect([r.criadas, r.atualizadas, r.removidas]).to eq([0, 0, 0])
  end
end
