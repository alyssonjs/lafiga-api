# frozen_string_literal: true

# BDD para os helpers puros usados pela rake `spells:import_xlsx`. Os
# helpers vivem em `lib/spells_import_helpers.rb` para serem testaveis
# unitariamente, sem precisar carregar Rake::Application nem tocar I/O.
#
# Cobertura por secao:
#   N1 — `near_duplicate_names?`: tolera fold/plural/typo, rejeita nomes
#         genuinamente diferentes (regressao do falso positivo "Moldar Agua"
#         vs "Moldar Terra" detectado durante a implementacao).
#   N2 — `levenshtein`: distancia correta nos casos canonicos.
#   N3 — `stem_pt`: despluraliza palavras PT-BR (oes->ao, eis->el, etc).
#   S1 — `signature_for_yml` / `signature_for_xlsx`: insensitivity a
#         case/diacritic/espaco e ordem de components.
#   P1 — `pick_canonical`: api_index nao-`pt-*` vence sobre `pt-*`.

require 'rails_helper'
require Rails.root.join('lib/spells_import_helpers.rb').to_s

RSpec.describe SpellsImportHelpers do
  describe 'N1 — near_duplicate_names?' do
    it 'N1.1 — case + diacritico iguais' do
      expect(described_class.near_duplicate_names?('Bola De Fogo', 'bola de fogo')).to eq(true)
      expect(described_class.near_duplicate_names?('Curar Ferimentos', 'curar ferimentos')).to eq(true)
    end

    it 'N1.2 — singular vs plural PT-BR (regressao Espirito/Espiritos Guardiao/Guardioes)' do
      # Plural regular oes->ao (cobre o caso real que motivou o stemmer:
      # "Espíritos Guardiões" no xlsx vs "Espírito Guardião" no spells.yml).
      expect(described_class.near_duplicate_names?('Espíritos Guardiões', 'Espírito Guardião')).to eq(true)
      expect(described_class.near_duplicate_names?('Leões', 'Leão')).to eq(true)
      expect(described_class.near_duplicate_names?('Animais', 'Animal')).to eq(true)
      # Plural irregular ("misseis" -> "missil") nao e coberto pelo stem
      # mecanico, mas o falso negativo nao prejudica a deduplicacao real
      # porque a planilha nunca traz a mesma magia em singular E plural.
    end

    it 'N1.3 — typo curto (1 char) e tolerado' do
      expect(described_class.near_duplicate_names?('Globo de Invulnerabilidade', 'Globo De Invunerabilidade'))
        .to eq(true)
    end

    it 'N1.4 — REJEITA nomes diferentes que coincidem em outras dimensoes' do
      # Regressao: signature pura (level/school/casting_time/range/components)
      # gerava falsos positivos como esses; agora Levenshtein + stem rejeitam.
      expect(described_class.near_duplicate_names?('Moldar Água', 'Moldar Terra')).to eq(false)
      expect(described_class.near_duplicate_names?('Mísseis Mágicos', 'Raio Guiador')).to eq(false)
      expect(described_class.near_duplicate_names?('Chama Sagrada', 'Raio De Gelo')).to eq(false)
      expect(described_class.near_duplicate_names?('Carne Para Pedra', 'Desintegrar')).to eq(false)
    end

    it 'N1.5 — strings vazias retornam false (defensivo)' do
      expect(described_class.near_duplicate_names?('', 'foo')).to eq(false)
      expect(described_class.near_duplicate_names?('foo', '')).to eq(false)
    end
  end

  describe 'N2 — levenshtein' do
    it 'N2.1 — distancia 0 para strings iguais' do
      expect(described_class.levenshtein('foo', 'foo')).to eq(0)
    end

    it 'N2.2 — distancia conhecida do par "espiritos guardioes" / "espirito guardiao"' do
      # Regressao: minha primeira estimativa foi 2; valor real e 4
      # (drop final s, drop final s, substitute o->a, substitute e->o).
      expect(described_class.levenshtein('espiritos guardioes', 'espirito guardiao')).to eq(4)
    end

    it 'N2.3 — distancia 1 para "invulnerabilidade" vs "invunerabilidade"' do
      expect(described_class.levenshtein('invulnerabilidade', 'invunerabilidade')).to eq(1)
    end

    it 'N2.4 — strings vazias' do
      expect(described_class.levenshtein('', 'abc')).to eq(3)
      expect(described_class.levenshtein('abc', '')).to eq(3)
      expect(described_class.levenshtein('', '')).to eq(0)
    end
  end

  describe 'N3 — stem_pt (despluralizador PT-BR)' do
    it 'N3.1 — oes -> ao' do
      expect(described_class.stem_pt('guardioes')).to eq('guardiao')
      expect(described_class.stem_pt('leoes')).to eq('leao')
    end

    it 'N3.2 — eis -> el / ais -> al' do
      expect(described_class.stem_pt('paineis')).to eq('painel')
      expect(described_class.stem_pt('animais')).to eq('animal')
    end

    it 'N3.3 — plural simples termina em s' do
      expect(described_class.stem_pt('espiritos')).to eq('espirito')
      expect(described_class.stem_pt('raios')).to eq('raio')
    end

    it 'N3.4 — palavras curtas (<4 chars) nao sao stemmed' do
      expect(described_class.stem_pt('ais')).to eq('ais')
      expect(described_class.stem_pt('os')).to eq('os')
    end

    it 'N3.5 — multiplas palavras sao stemmed individualmente' do
      expect(described_class.stem_pt('espiritos guardioes')).to eq('espirito guardiao')
    end
  end

  describe 'S1 — signature_for_yml / signature_for_xlsx' do
    it 'S1.1 — fields normalizados (fold + sort components) batem entre yml e xlsx' do
      yml = {
        'level' => 3, 'school' => 'Conjuration',
        'casting_time' => '1 ação', 'range' => 'Pessoal (4,5 metros de raio)',
        'components' => %w[V S M],
      }
      xlsx = {
        'level' => 3, 'school' => 'CONJURATION',
        'casting_time' => '1 acao', 'range' => 'pessoal (4,5 metros de raio)',
        'components' => %w[M V S], # ordem diferente
      }
      expect(described_class.signature_for_yml(yml)).to eq(described_class.signature_for_xlsx(xlsx))
    end

    it 'S1.2 — level diferente -> signatures diferentes' do
      a = { 'level' => 1, 'school' => 'X', 'casting_time' => 'a', 'range' => 'b', 'components' => [] }
      b = a.merge('level' => 2)
      expect(described_class.signature_for_yml(a)).not_to eq(described_class.signature_for_yml(b))
    end
  end

  describe 'P1 — pick_canonical' do
    let(:canonical) { { 'api_index' => 'spirit-guardians', 'name' => 'Espiritos Guardioes' } }
    let(:pt_mirror) { { 'api_index' => 'pt-espirito-guardiao', 'name' => 'Espirito Guardiao' } }

    it 'P1.1 — api_index nao-pt-* vence sobre pt-*' do
      winner, loser = described_class.pick_canonical(canonical, pt_mirror)
      expect(winner).to eq(canonical)
      expect(loser).to eq(pt_mirror)
    end

    it 'P1.2 — ordem de argumentos invertida tambem retorna canonico como winner' do
      winner, loser = described_class.pick_canonical(pt_mirror, canonical)
      expect(winner).to eq(canonical)
      expect(loser).to eq(pt_mirror)
    end

    it 'P1.3 — empate (ambos nao-pt-* ou ambos pt-*): primeiro vence' do
      a = { 'api_index' => 'foo', 'name' => 'A' }
      b = { 'api_index' => 'bar', 'name' => 'B' }
      winner, _loser = described_class.pick_canonical(a, b)
      expect(winner).to eq(a)
    end
  end
end
