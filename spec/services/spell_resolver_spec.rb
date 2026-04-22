# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SpellResolver do
  let(:resolver) { described_class.new }

  before(:all) do
    described_class.reset_caches!
  end

  describe '#resolve' do
    let!(:chill_touch) do
      Spell.find_by(api_index: 'chill-touch') ||
        FactoryBot.create(:spell, name: 'Toque Arrepiante', api_index: 'chill-touch', level: 0)
    end

    context 'pelo id numerico' do
      it 'resolve Integer' do
        expect(resolver.resolve(chill_touch.id)).to eq(chill_touch)
      end

      it 'resolve string numerica' do
        expect(resolver.resolve(chill_touch.id.to_s)).to eq(chill_touch)
      end
    end

    context 'pelo nome' do
      it 'resolve nome canonico exato' do
        expect(resolver.resolve('Toque Arrepiante')).to eq(chill_touch)
      end

      it 'resolve com case diferente' do
        expect(resolver.resolve('toque arrepiante')).to eq(chill_touch)
      end
    end

    context 'pelo api_index' do
      it 'resolve quando o input ja e um slug' do
        expect(resolver.resolve('chill-touch')).to eq(chill_touch)
      end
    end

    context 'pelo aliases.yml (typos historicos)' do
      it 'resolve "Toque arrepiane" (typo: faltou t e e)' do
        expect(resolver.resolve('Toque arrepiane')).to eq(chill_touch)
      end

      it 'aceita Hash com id textual' do
        expect(resolver.resolve({ 'id' => 'Toque arrepiane', 'name' => 'Toque arrepiane' })).to eq(chill_touch)
      end

      it 'eh agnostico a acentos no input' do
        # Nao adicionamos alias com til; o lookup deve transliterate antes de bater
        # contra a chave do yml.
        expect(resolver.resolve('TOQUE ARREPIANE')).to eq(chill_touch)
      end
    end

    context 'pelo indice transliterado (sem acento, mesmo nome canonico)' do
      let!(:orbe) do
        Spell.find_by(api_index: 'chromatic-orb') ||
          FactoryBot.create(:spell, name: 'Orbe Cromática', api_index: 'chromatic-orb', level: 1)
      end

      before { described_class.reset_caches! }

      it 'resolve nome sem acento' do
        expect(resolver.resolve('Orbe Cromatica')).to eq(orbe)
      end
    end

    context 'quando nao resolve' do
      it 'devolve nil para nome inventado' do
        expect(resolver.resolve('Bola de Fogo Imaginaria')).to be_nil
      end

      it 'devolve nil para Hash sem id e sem name' do
        expect(resolver.resolve({})).to be_nil
      end

      it 'devolve nil para entrada lixo "2.0"' do
        expect(resolver.resolve('2.0')).to be_nil
      end
    end
  end

  describe '#normalize' do
    let!(:chill_touch) do
      Spell.find_by(api_index: 'chill-touch') ||
        FactoryBot.create(:spell, name: 'Toque Arrepiante', api_index: 'chill-touch', level: 0)
    end

    it 'devolve hash canonico {id, name, level, api_index} quando resolve' do
      result = resolver.normalize('Toque arrepiane')
      expect(result).to eq(
        id: chill_touch.id,
        name: 'Toque Arrepiante',
        level: 0,
        api_index: 'chill-touch'
      )
    end

    it 'devolve nil quando nao resolve' do
      expect(resolver.normalize('Bola de Fogo Imaginaria')).to be_nil
    end
  end

  describe 'cache local de instancia' do
    let!(:spell) do
      Spell.find_by(api_index: 'chill-touch') ||
        FactoryBot.create(:spell, name: 'Toque Arrepiante', api_index: 'chill-touch', level: 0)
    end

    it 'consulta o DB so uma vez por chave (id)' do
      expect(Spell).to receive(:find_by).with(id: spell.id).once.and_call_original
      3.times { resolver.resolve(spell.id) }
    end
  end
end
