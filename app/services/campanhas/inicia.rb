# frozen_string_literal: true

module Campanhas
  # COMEÇA a campanha de uma região num mundo (09/10; L1.1, plano B3): a linha da região, a campanha e os setores, pela
  # ficha (`Regioes::Ficha`). Quem chama: o seed de dev (`mundo:semear_argoba`) e, no L1.7, a fundação da vila.
  #
  # Rodar de novo não duplica e NÃO desfaz o jogo: a campanha e os setores que já existem ficam como estão (a etapa, o
  # estado e as pressões mudam em jogo). Só o setor que falta é criado, com os valores iniciais da ficha e a ordem da
  # corrente. Duas chamadas ao mesmo tempo esbarram nos índices únicos, e a segunda falha sem gravar pela metade.
  module Inicia
    module_function

    ATRIBUTOS_DO_SETOR = (Regioes::Ficha::PARTES_DO_SETOR - %w[chave]).freeze

    # → a Campanha (a nova, ou a que o mundo já tinha)
    def call(mundo, regiao:)
      ficha = Regioes::Ficha.de(regiao)
      dados = ficha['campanha']

      Campanha.transaction do
        linha = Regiao.sincroniza!(ficha['chave'])
        campanha = mundo.campanhas.find_or_create_by!(chave: dados['chave']) do |c|
          c.assign_attributes(regiao: linha, nome: dados['nome'], ameaca: dados['ameaca']['chave'], etapa: dados['etapas'].first)
        end
        dados['setores'].each.with_index(1) do |s, ordem|
          campanha.setores.find_or_create_by!(chave: s['chave']) do |setor|
            setor.assign_attributes(s.slice(*ATRIBUTOS_DO_SETOR).merge('ordem' => ordem))
          end
        end
        campanha
      end
    end
  end
end
