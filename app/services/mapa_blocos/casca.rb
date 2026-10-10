# frozen_string_literal: true

module MapaBlocos
  # A CASCA do mapa de um setor (09/10; L1.2, plano B3): o `BattleMap` da vila, em blocos, do tamanho que a ficha da
  # região dá ao setor. Uma por setor; chamar de novo devolve a que já existe. O dono é o Mestre do grupo, que é quem
  # escreve no mapa; quem tem personagem no grupo lê.
  #
  # Nasce sem blocos: quem os grava é o gerador (L1.3). Até lá, o protótipo gera o mundo e os envia
  # (`/dev/mapa-lpc?vila=1`).
  module Casca
    module_function

    # a semente do gerador do protótipo (`planejaMundo`), até o gerador do servidor (L1.3) ter a sua
    SEMENTE_DO_PROTOTIPO = 11

    def call(setor, group:)
      tamanho = setor.ficha['mapa'] or raise ArgumentError, "o setor #{setor.chave} ainda não tem mapa na ficha"
      raise ArgumentError, "o grupo #{group.id} não tem Mestre (dm_user): o mapa precisa de dono" unless group.dm_user

      BattleMap.find_or_create_by!(setor_id: setor.id, map_kind: 'vila') do |mapa|
        mapa.assign_attributes(
          name: setor.nome, user: group.dm_user, group: group, armazenamento: 'blocos', cells: [],
          width: tamanho['colunas'], height: tamanho['linhas'], semente: SEMENTE_DO_PROTOTIPO,
        )
      end
    end
  end
end
