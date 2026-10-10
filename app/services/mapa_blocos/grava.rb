# frozen_string_literal: true

module MapaBlocos
  # GRAVA blocos do mapa da vila (09/10; L1.2, plano B3 e B8). Quem chama hoje: as ferramentas de dev (o protótipo envia
  # o mundo gerado; um bloco muda de propósito). Depois: o gerador (L1.3), o corte e a coleta (L2.4b, L2.5b), a obra
  # (L3.3).
  #
  # - **A versão só sobe quando o conteúdo muda**, e só o bloco que mudou avisa (`bloco_mudou` no canal do mapa, com
  #   `bc`, `bl` e a versão nova): o cliente recarrega só aquele bloco.
  # - **Uma leva é tudo ou nada:** um bloco inválido desfaz a leva inteira.
  # - **O aviso sai depois da transação**, para quem recarrega já ler o bloco novo. Quem chama dentro de uma transação
  #   própria recebe o aviso antes do commit dela.
  # - O que não vem fica como estava: mudar só os objetos guarda o terreno.
  # - **Quem grava o mundo diz quem o gerou** (a C0): com `geracao`, a semente e as versões do gerador e dos biomas
  #   vão para o mapa na mesma transação dos blocos.
  module Grava
    module_function

    Resultado = Struct.new(:bloco, :mudou, keyword_init: true)
    CAMPOS_DA_GERACAO = %i[semente versao_do_gerador versao_dos_biomas].freeze

    # um bloco só → Resultado
    def call(mapa, bc:, bl:, terreno: nil, objetos: nil, ator: nil)
      varios(mapa, [{ bc: bc, bl: bl, terreno: terreno, objetos: objetos }], ator: ator).first
    end

    # uma leva: [{ bc:, bl:, terreno:, objetos: }] → [Resultado], na mesma ordem. `geracao`:
    # { semente:, versao_do_gerador:, versao_dos_biomas: }, de quem gerou a leva
    def varios(mapa, lista, ator: nil, geracao: nil)
      raise ArgumentError, "o mapa #{mapa.id} não é em blocos" unless mapa.blocos?

      resultados = MapaBloco.transaction do
        mapa.update!(geracao.to_h.symbolize_keys.slice(*CAMPOS_DA_GERACAO)) if geracao
        lista.map { |item| grava_um(mapa, item.to_h.symbolize_keys) }
      end
      resultados.select(&:mudou).each { |r| MapRealtime::Broadcaster.bloco_mudou(mapa, r.bloco, actor: ator) }
      resultados
    end

    def grava_um(mapa, item)
      bloco = mapa.mapa_blocos.lock.find_or_initialize_by(bc: item[:bc], bl: item[:bl])
      bloco.terreno = como_json(item[:terreno]) unless item[:terreno].nil?
      bloco.objetos = como_json(item[:objetos]) unless item[:objetos].nil?
      bloco.terreno = { 'camadas' => {} } if bloco.new_record? && item[:terreno].nil?
      return Resultado.new(bloco: bloco, mudou: false) unless bloco.new_record? || bloco.changed?

      bloco.versao += 1 if bloco.persisted?
      bloco.save!
      Resultado.new(bloco: bloco, mudou: true)
    end

    # o valor como o banco o devolve (chaves em texto): sem isso, o mesmo conteúdo com chave em símbolo "mudava"
    def como_json(valor)
      JSON.parse(valor.to_json)
    end
  end
end
