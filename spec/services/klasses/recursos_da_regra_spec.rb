require 'rails_helper'

# Os RECURSOS por nível passam a sair da REGRA, não de um `case` escrito à mão
# dentro do `CharacterSheetSummaryService`.
#
# 🐞 Havia até QUATRO cópias do mesmo número: `ClassRules[...][:resources]` (que
# ninguém lia), o `case` do summary, o `classResources.ts` do front, e a tabela
# de progressão em HTML. No nível 20 do bárbaro já discordavam — a regra dizia
# 6 fúrias, o resto dizia ilimitado. Cópia que ninguém lê é a que apodrece
# primeiro.
RSpec.describe 'recursos de classe vindos da regra', type: :service do
  # ⚠️ Pergunta sobre a REGRA: não precisa de ficha nenhuma para ser feita.
  def escada(classe, chave, nivel)
    ClassRules.escada_de_recurso(classe, chave, nivel)
  end

  describe 'a escada é lida da regra' do
    it 'fúrias do bárbaro sobem com o nível', :aggregate_failures do
      expect(escada('barbarian', :rage, 1)[:total]).to eq(2)
      expect(escada('barbarian', :rage, 3)[:total]).to eq(3)
      expect(escada('barbarian', :rage, 6)[:total]).to eq(4)
      expect(escada('barbarian', :rage, 12)[:total]).to eq(5)
      expect(escada('barbarian', :rage, 17)[:total]).to eq(6)
    end

    # ⚠️ A divergência que a auditoria mediu: a regra dizia 6 no nível 20 e o
    # motor dizia ilimitado. Agora é uma coisa só.
    it '⚠️ no nível 20 a fúria é ILIMITADA na regra, como o motor sempre fez' do
      expect(escada('barbarian', :rage, 20)[:total]).to eq(999)
    end

    it 'o dano de fúria vem junto, do `values_by_level`', :aggregate_failures do
      expect(escada('barbarian', :rage, 1)[:damage_bonus]).to eq(2)
      expect(escada('barbarian', :rage, 9)[:damage_bonus]).to eq(3)
      expect(escada('barbarian', :rage, 16)[:damage_bonus]).to eq(4)
    end

    it 'Formas Selvagens: 2, e ilimitadas no 20', :aggregate_failures do
      expect(escada('druid', :wild_shape, 5)[:total]).to eq(2)
      expect(escada('druid', :wild_shape, 20)[:total]).to eq(999)
    end
  end

  # ⚠️ Abaixo do nível de entrada o recurso NÃO é emitido — é assim que o motor
  # se comporta hoje, e é o que faz Indomável só aparecer do 9 em diante.
  describe 'escada que ainda não começou' do
    it 'Indomável não existe antes do 9', :aggregate_failures do
      expect(escada('fighter', :indomitable, 8)).to be_nil
      expect(escada('fighter', :indomitable, 9)[:total]).to eq(1)
      expect(escada('fighter', :indomitable, 17)[:total]).to eq(3)
    end

    it 'classe que não declara a chave devolve nil', :aggregate_failures do
      expect(escada('wizard', :rage, 20)).to be_nil
      expect(escada('nao-existe', :rage, 1)).to be_nil
    end
  end

  # ⚠️ O PORTÃO: mudar a regra muda o que a ficha mostra. Era isto que não
  # acontecia — a escada da regra era letra morta.
  describe '⚠️ a regra MANDA na ficha' do
    let!(:barbaro) { Klass.find_by(api_index: 'barbarian') || Klass.create!(name: 'Bárbaro', api_index: 'barbarian') }

    after do
      barbaro.update_columns(rules: nil)
      RaceRules.reload! if defined?(RaceRules)
    end

    it 'gravar `resources` no overlay muda as fúrias', :aggregate_failures do
      expect(escada('barbarian', :rage, 1)[:total]).to eq(2)

      barbaro.update!(rules: {
                        'id' => 'barbarian', 'name' => 'Bárbaro', 'hit_die' => 'd12',
                        'resources' => { 'rage' => { 'recharge' => 'LR', 'uses_by_level' => { '1' => 7 } } }
                      })

      expect(escada('barbarian', :rage, 1)[:total]).to eq(7)
    end
  end

  # ⚠️ Os testes acima provam a REGRA. Esta secção prova a LIGAÇÃO dela ao
  # serviço da ficha — e faz falta: apagar a leitura no
  # `CharacterSheetSummaryService` não derrubava nenhum dos outros exemplos.
  describe '⚠️ o serviço da ficha LÊ a regra (fiação)' do
    let(:fonte) do
      File.read(Rails.root.join('app', 'services', 'character_sheet_summary_service.rb'))
    end

    it 'fúria, formas selvagens e canalizar vêm da regra', :aggregate_failures do
      %i[rage wild_shape channel_divinity].each do |chave|
        expect(fonte).to include("ClassRules.escada_de_recurso(klass.api_index, :#{chave}, level)")
      end
    end

    it 'os três do guerreiro vêm da regra, em laço' do
      expect(fonte).to match(/%i\[action_surge second_wind indomitable\]\.each/)
      expect(fonte).to include('ClassRules.escada_de_recurso(klass.api_index, chave, level)')
    end

    # 🐞 As escadas escritas à mão têm de ter SUMIDO: enquanto existirem, são a
    # quinta cópia do mesmo número à espera de divergir.
    it '⚠️ não sobrou escada escrita à mão para estes recursos', :aggregate_failures do
      expect(fonte).not_to match(/when level >= 17 then 6\s*\n\s*when level >= 12 then 5/)
      expect(fonte).not_to include('ind_total = level >= 17 ? 3')
      expect(fonte).not_to include('total = level >= 20 ? 999 : 2')
    end
  end
end
