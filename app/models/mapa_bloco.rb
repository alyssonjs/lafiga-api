# frozen_string_literal: true

# Um BLOCO do mapa da vila (L1.2; plano B3, B8 e D5): `LADO`×`LADO` células de um `BattleMap` em blocos. Guarda o
# terreno nos VÉRTICES (uma camada de bits por terreno do LPC) e os objetos ESPARSOS que moram nele. O formato é o de
# `config/mundo/mapa_blocos.json`, o mesmo que o front confere (`lpcMapa/blocosDoServidor.ts`).
#
# - **Vértices:** o bloco tem (colunas + 1) × (linhas + 1) vértices, por linha; a última coluna e a última linha
#   repetem as do vizinho, para cada bloco desenhar o seu chão sozinho. Os bits vão em base64, o 1º bit no bit mais
#   baixo do 1º byte.
# - **Objetos:** cada um mora no bloco do seu PÉ (a célula de `col`/`lin`; no carimbo, a do canto de baixo à esquerda
#   da pegada), então dois blocos nunca têm o mesmo objeto. O que passa da borda (a copa, a parede) o cliente desenha
#   com os vizinhos que já tem.
# - **O contrato é SEMÂNTICO** (09/10, a C0 de `jogo/composicao-do-mapa.md`): o bloco guarda o que a coisa É, e a arte
#   escolhe como ela aparece. O terreno vai pelo nome; a árvore, pela espécie; o carimbo, pela peça do catálogo. Nenhum
#   PNG no estado do mundo: a folha, o recorte e a variante do desenho são recusados.
class MapaBloco < ApplicationRecord
  FORMATO = JSON.parse(File.read(Rails.root.join('config/mundo/mapa_blocos.json'))).freeze
  LADO = FORMATO.fetch('lado')
  TERRENOS = FORMATO.fetch('terrenos').freeze
  TIPOS = FORMATO.fetch('tipos_de_objeto').freeze
  ESPECIES = FORMATO.fetch('especies_de_arvore').freeze
  PECAS = FORMATO.fetch('pecas').freeze
  PX_POR_CELULA = 32
  # teto por bloco, para proteger o JSONB e o broadcast (o mundo de 200×200 do protótipo dá ~100 por bloco)
  MAX_OBJETOS = 3000
  # os campos inteiros que cada tipo de objeto precisa (além de `id` e `tipo`)
  INTEIROS = {
    'arvore' => %w[col lin],
    'casa' => %w[col lin largura parede telhado],
    'pedra' => %w[col lin],
    'carimbo' => %w[col lin],
    'piso' => %w[col lin colunas linhas],
  }.freeze
  # o que é da ARTE e não entra no bloco: o desenho da árvore, a folha e o recorte do carimbo
  DA_ARTE = { 'arvore' => %w[variante folha ret], 'carimbo' => %w[folha ret variante] }.freeze
  # o ajuste fino do carimbo na célula do pé, em px (menos de uma célula), e o vão da peça que estica (a ponte)
  AJUSTE_MAX = 31

  belongs_to :battle_map

  validates :bc, :bl, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :bc, uniqueness: { scope: %i[battle_map_id bl] }
  validates :versao, numericality: { only_integer: true, greater_than: 0 }
  validate :dentro_do_mapa
  validate :terreno_bem_formado
  validate :objetos_bem_formados

  # os blocos da janela de `raio` em volta de (bc, bl), por linha e coluna (a borda do mapa corta a janela)
  scope :na_janela, ->(bc, bl, raio) { where(bc: (bc - raio)..(bc + raio), bl: (bl - raio)..(bl + raio)).order(:bl, :bc) }

  # as células deste bloco (o da última coluna e o da última linha podem ser menores)
  def colunas
    [LADO, battle_map.width - bc * LADO].min
  end

  def linhas
    [LADO, battle_map.height - bl * LADO].min
  end

  def bytes_por_camada
    ((colunas + 1) * (linhas + 1) + 7) / 8
  end

  def para_api
    { bc: bc, bl: bl, versao: versao, terreno: terreno, objetos: objetos }
  end

  # quantos blocos o mapa tem, contando os menores da borda
  def self.blocos_no_mapa(mapa)
    ((mapa.width + LADO - 1) / LADO) * ((mapa.height + LADO - 1) / LADO)
  end

  # a célula do PÉ de um objeto, presa dentro do mapa: é ela que diz em que bloco ele mora
  def self.celula_do_pe(objeto, colunas_do_mapa, linhas_do_mapa)
    [objeto['col'].clamp(0, colunas_do_mapa - 1), objeto['lin'].clamp(0, linhas_do_mapa - 1)]
  end

  private

  def dentro_do_mapa
    return unless battle_map && bc.is_a?(Integer) && bl.is_a?(Integer)
    return if bc >= 0 && bl >= 0 && bc * LADO < battle_map.width && bl * LADO < battle_map.height

    errors.add(:base, "o bloco #{bc},#{bl} fica fora do mapa")
  end

  def terreno_bem_formado
    camadas = terreno.is_a?(Hash) ? terreno['camadas'] : nil
    return errors.add(:terreno, 'deve ser { camadas: { terreno: base64 } }') unless camadas.is_a?(Hash)
    return unless battle_map && errors[:base].empty?

    camadas.each do |nome, bits|
      next errors.add(:terreno, "terreno desconhecido: #{nome}") unless TERRENOS.include?(nome)

      bytes = bits.is_a?(String) ? Base64.strict_decode64(bits) : nil
      next if bytes&.bytesize == bytes_por_camada

      errors.add(:terreno, "a camada #{nome} deve ter #{bytes_por_camada} bytes (os vértices do bloco)")
    rescue ArgumentError
      errors.add(:terreno, "a camada #{nome} não é base64")
    end
  end

  def objetos_bem_formados
    return errors.add(:objetos, 'deve ser uma lista') unless objetos.is_a?(Array)
    return errors.add(:objetos, "no máximo #{MAX_OBJETOS} por bloco") if objetos.size > MAX_OBJETOS

    ids = []
    objetos.each do |o|
      erro = erro_do_objeto(o, ids)
      next ids << o['id'] unless erro

      errors.add(:objetos, erro)
      break
    end
  end

  def erro_do_objeto(o, ids)
    return 'cada objeto é um mapa' unless o.is_a?(Hash)
    return 'objeto sem id' unless o['id'].is_a?(String) && o['id'].present? && o['id'].size <= 80
    return "id repetido: #{o['id']}" if ids.include?(o['id'])
    return "#{o['id']}: tipo desconhecido: #{o['tipo']}" unless TIPOS.include?(o['tipo'])

    faltam = INTEIROS.fetch(o['tipo']).reject { |campo| o[campo].is_a?(Integer) }
    return "#{o['id']}: falta #{faltam.join(', ')}" if faltam.any?

    erro = erro_semantico(o)
    return erro if erro
    return nil unless battle_map && errors[:base].empty?

    col, lin = self.class.celula_do_pe(o, battle_map.width, battle_map.height)
    return nil if col.div(LADO) == bc && lin.div(LADO) == bl

    "#{o['id']}: o pé (#{col},#{lin}) é do bloco #{col.div(LADO)},#{lin.div(LADO)}"
  end

  # o contrato semântico: a espécie da árvore, a peça do carimbo, e nada da arte
  def erro_semantico(o)
    da_arte = DA_ARTE.fetch(o['tipo'], []).select { |campo| o.key?(campo) }
    return "#{o['id']}: #{da_arte.join(', ')} é da arte, não do mundo" if da_arte.any?

    case o['tipo']
    when 'arvore'
      "#{o['id']}: espécie desconhecida: #{o['especie'].inspect}" unless ESPECIES.include?(o['especie'])
    when 'carimbo'
      return "#{o['id']}: peça fora do catálogo: #{o['peca'].inspect}" unless PECAS.include?(o['peca'])

      erro_do_ajuste(o)
    end
  end

  def erro_do_ajuste(o)
    fora = %w[dx dy].select { |k| o.key?(k) && !(o[k].is_a?(Integer) && o[k].abs <= AJUSTE_MAX) }
    return "#{o['id']}: #{fora.join(', ')} deve ser inteiro de -#{AJUSTE_MAX} a #{AJUSTE_MAX} (px)" if fora.any?
    return nil if !o.key?('colunas') || (o['colunas'].is_a?(Integer) && o['colunas'].between?(1, LADO))

    "#{o['id']}: colunas deve ser inteiro de 1 a #{LADO}"
  end
end
