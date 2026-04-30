require 'rails_helper'
require 'yaml'

RSpec.describe 'subclass domain spells config' do
  let(:config) { YAML.load_file(Rails.root.join('config', 'subclass_overrides.yml')) }

  def always_prepared_for(subclass_slug)
    levels = config.fetch('cleric').fetch(subclass_slug).fetch('levels')
    features = levels.flat_map { |level| level.fetch('features', []) }
    feature = features.find { |entry| entry.dig('grants', 'spells', 'always_prepared') }

    feature.dig('grants', 'spells', 'always_prepared')
  end

  it 'keeps War Domain level 1 spells aligned with PHB' do
    spells = always_prepared_for('dominio-da-guerra')[1]

    expect(spells).to contain_exactly('auxílio divino', 'escudo da fé')
    expect(spells).not_to include('destruição divina')
  end

  it 'grants Time Domain first domain spells at cleric level 1' do
    spells = always_prepared_for('dominio-tempo')

    expect(spells.keys).to include(1)
    expect(spells.keys).not_to include(2)
    expect(spells[1]).to contain_exactly('feather-fall', 'expeditious-retreat')
  end

  it 'keeps cleric domain spell tables aligned with PHB and Novos Arquétipos' do
    expected = {
      'dominio-agua' => {
        1 => %w[grease create-or-destroy-water],
        3 => %w[misty-step lesser-restoration],
        5 => %w[water-walk water-breathing],
        7 => %w[control-water blight],
        9 => %w[conjure-elemental scrying]
      },
      'dominio-criacao' => {
        1 => %w[create-or-destroy-water unseen-servant],
        3 => %w[continual-flame web],
        5 => %w[create-food-and-water phantom-steed],
        7 => %w[fabricate stoneskin],
        9 => %w[creation passwall]
      },
      'dominio-mente' => {
        1 => %w[command charm-person],
        3 => %w[detect-thoughts suggestion],
        5 => %w[tongues fear],
        7 => %w[confusion dominate-beast],
        9 => %w[rarys-telepathic-bond modify-memory]
      },
      'dominio-terra' => {
        1 => %w[longstrider shield-of-faith],
        3 => %w[pass-without-trace protection-from-poison],
        5 => %w[meld-into-stone glyph-of-warding],
        7 => %w[stone-shape stoneskin],
        9 => %w[passwall wall-of-stone]
      },
      'dominio-ar' => {
        1 => %w[feather-fall jump],
        3 => %w[levitate gust-of-wind],
        5 => %w[gaseous-form wind-wall],
        7 => %w[freedom-of-movement ice-storm],
        9 => %w[cone-of-cold conjure-elemental]
      },
      'dominio-tempo' => {
        1 => %w[feather-fall expeditious-retreat],
        3 => %w[levitate misty-step],
        5 => %w[slow haste],
        7 => %w[blink dimension-door],
        9 => %w[teleportation-circle hold-monster]
      },
      'dominio-do-conhecimento' => {
        1 => ['comando', 'identificação'],
        3 => ['augúrio', 'sugestão'],
        5 => ['dificultar detecção', 'falar com os mortos'],
        7 => ['olho arcano', 'confusão'],
        9 => ['conhecimento lendário', 'vidência']
      },
      'dominio-da-vida' => {
        1 => ['bênção', 'curar ferimentos'],
        3 => ['restauração menor', 'arma espiritual'],
        5 => ['sinal de esperança', 'revivificar'],
        7 => ['proteção contra a morte', 'guardião da fé'],
        9 => ['curar ferimentos em massa', 'reviver os mortos']
      },
      'dominio-da-luz' => {
        1 => ['mãos flamejantes', 'fogo das fadas'],
        3 => ['esfera flamejante', 'raio ardente'],
        5 => ['luz do dia', 'bola de fogo'],
        7 => ['guardião da fé', 'muralha de fogo'],
        9 => ['coluna de chamas', 'vidência']
      },
      'dominio-da-natureza' => {
        1 => ['amizade animal', 'falar com animais'],
        3 => ['pele de árvore', 'crescer espinhos'],
        5 => ['ampliar plantas', 'muralha de vento'],
        7 => ['dominar besta', 'vinha esmagadora'],
        9 => ['praga de insetos', 'caminhar em árvores']
      },
      'dominio-da-tempestade' => {
        1 => ['névoa obscurecente', 'onda trovejante'],
        3 => ['lufada de vento', 'despedaçar'],
        5 => ['convocar relâmpagos', 'nevasca'],
        7 => ['controlar a água', 'tempestade de gelo'],
        9 => ['onda destrutiva', 'praga de insetos']
      },
      'dominio-da-trapaca' => {
        1 => ['enfeitiçar pessoa', 'disfarçar-se'],
        3 => ['imagem espelhada', 'passo sem pegadas'],
        5 => ['piscar', 'dissipar magia'],
        7 => ['porta dimensional', 'metamorfose'],
        9 => ['dominar pessoa', 'modificar memória']
      },
      'dominio-da-guerra' => {
        1 => ['auxílio divino', 'escudo da fé'],
        3 => ['arma mágica', 'arma espiritual'],
        5 => ['manto do cruzado', 'espíritos guardiões'],
        7 => ['movimentação livre', 'pele de pedra'],
        9 => ['coluna de chamas', 'imobilizar monstro']
      }
    }

    expected.each do |slug, spell_table|
      expect(always_prepared_for(slug)).to eq(spell_table)
    end
  end
end
