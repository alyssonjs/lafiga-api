# frozen_string_literal: true

require 'rails_helper'

# Os casos são os mesmos do Vitest (`front-lafiga/src/app/utils/relogioDoMundo.bdd.test.ts`): a conta do relógio tem de
# dar igual nos dois lados (L0.2; plano B1).
RSpec.describe Mundo::Relogio do
  casos = JSON.parse(File.read(Rails.root.join('config/mundo/relogio_casos.json')))
  hora = ->(iso) { iso && Time.iso8601(iso) }
  ancora = lambda do |h|
    Mundo::Relogio::Ancora.new(
      epoca_em: hora.call(h['epoca_em']),
      minuto_na_epoca: h['minuto_na_epoca'],
      fator: h['fator'],
      pausado_desde: hora.call(h['pausado_desde']),
    )
  end
  em_json = lambda do |a|
    {
      'epoca_em' => a.epoca_em.utc.iso8601(3),
      'minuto_na_epoca' => a.minuto_na_epoca,
      'fator' => a.fator,
      'pausado_desde' => a.pausado_desde&.utc&.iso8601(3),
    }
  end

  describe '.momento' do
    casos['momentos'].each do |c|
      it(c['nome']) do
        expect(described_class.momento(c['minuto'])).to eq(c['esperado'].symbolize_keys.merge(minuto: c['minuto']))
      end
    end
  end

  describe '.minuto' do
    casos['ancoras'].each do |c|
      it(c['nome']) do
        expect(described_class.minuto(ancora.call(c['ancora']), hora.call(c['agora']))).to eq(c['minuto'])
      end
    end
  end

  describe '.reancora' do
    casos['reancoras'].each do |c|
      it(c['nome']) do
        antes = ancora.call(c['ancora'])
        agora = hora.call(c['agora'])
        nova = described_class.reancora(antes, agora, **c['mudanca'].symbolize_keys)

        expect(em_json.call(nova)).to eq(c['nova'])
        # sem salto: no instante da mudança, o minuto é o mesmo
        expect(described_class.minuto(nova, agora)).to eq(described_class.minuto(antes, agora))
        c['depois'].each do |d|
          expect(described_class.minuto(nova, hora.call(d['agora']))).to eq(d['minuto']), d['agora']
        end
      end
    end

    it 'recusa um fator que não seja inteiro positivo' do
      antes = ancora.call(casos['reancoras'].first['ancora'])
      expect { described_class.reancora(antes, Time.utc(2026, 10, 9), fator: 0) }.to raise_error(ArgumentError)
      expect { described_class.reancora(antes, Time.utc(2026, 10, 9), fator: 1.5) }.to raise_error(ArgumentError)
    end
  end
end
