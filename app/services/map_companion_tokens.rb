# frozen_string_literal: true

# O COMPANHEIRO NO MAPA (04/10, a mesa: "equipar o companheiro animal ... que deve ficar seguindo o personagem
# enquanto não estiver em combate ... e quando o companheiro for montaria, deve ter a opção de montar").
#
# O token do companheiro é ligado ao DONO pelo `companheiroDe` (o id do personagem) — nunca pelo `characterId`, que
# faria dele o token do personagem em toda busca (o chibi, o equipamento, "o PC no mapa") — e ao companheiro da ficha
# pelo `companheiroId`. O id do token sai do companheiro (`companheiro-<id>`): pôr de novo não duplica.
#
# Quem pode: o Mestre, ou o JOGADOR DONO do personagem — e o companheiro tem de estar na ficha dele (a autorização
# espelha a de invocar, `Combat::SummonCompanionService`). Montar e desmontar mudam SÓ os campos da montaria do token
# do próprio personagem (`CAMPOS_DA_MONTARIA`).
class MapCompanionTokens
  # sem permissão (403)
  class Proibido < StandardError; end
  # pedido inválido (422)
  class Invalido < StandardError; end

  TOKEN_PREFIX = 'companheiro-'
  # o espaço do porte (como o invocado, `Combat::SummonCompanionService::CELULAS_DO_PORTE`)
  CELULAS_DO_PORTE = { 'tiny' => 1, 'small' => 1, 'medium' => 1, 'large' => 2, 'huge' => 3, 'gargantuan' => 4 }.freeze
  # a espécie do desenho no mapa (a chave do bicho no front, `CRIATURAS_DE_MONSTRO`: `winter-wolf`, `eagle`)
  ESPECIE = /\A[a-z0-9-]{1,40}\z/
  CAMPOS_DA_MONTARIA = %w[montaria tamanhoAPe size x y montariaCompanheiroId].freeze

  def self.token_id(companion_id)
    "#{TOKEN_PREFIX}#{companion_id}"
  end

  # O personagem que o usuário controla: o Mestre, qualquer um; o jogador, só os dele.
  def self.personagem!(user, character_id)
    character = Character.find_by(id: character_id.to_s)
    raise Invalido, 'Personagem não encontrado.' unless character
    raise Proibido, 'Você não controla este personagem.' unless Group.user_is_dm?(user) || character.user_id == user&.id

    character
  end

  # O companheiro da ficha do personagem.
  def self.companheiro!(character, companion_id)
    c = Array(character.sheet&.companions).find { |x| x.is_a?(Hash) && x['id'].to_s == companion_id.to_s }
    raise Invalido, 'Companheiro não encontrado na ficha.' unless c

    c
  end

  # O token do companheiro em (x, y): o nome e o porte da ficha; a espécie do pedido ou a guardada no companheiro.
  def self.token(character, companion, x:, y:, especie: nil)
    esp = especie.to_s.strip.presence || companion['especie'].to_s.strip.presence
    raise Invalido, 'Espécie inválida.' if esp && esp !~ ESPECIE

    {
      'id' => token_id(companion['id']),
      'name' => companion['name'].to_s.presence || 'Companheiro',
      'x' => x.to_i,
      'y' => y.to_i,
      'size' => CELULAS_DO_PORTE[companion['size'].to_s.strip.downcase] || 1,
      'color' => '#8B6BB1',
      'imageMode' => 'color',
      'companheiroDe' => character.id.to_s,
      'companheiroId' => companion['id'].to_s,
      'especie' => esp,
    }.compact
  end

  # Os campos da montaria que o pedido pode mudar — o resto é recusado (o jogador não muda nada além disso).
  def self.campos_da_montaria(raw)
    changes = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw
    raise Invalido, 'changes deve ser um objeto' unless changes.is_a?(Hash)

    changes = changes.deep_stringify_keys
    extras = changes.keys - CAMPOS_DA_MONTARIA
    raise Invalido, "campo fora da montaria: #{extras.join(', ')}" if extras.any?

    if changes.key?('montaria') && !changes['montaria'].nil? && changes['montaria'].to_s !~ ESPECIE
      raise Invalido, 'Montaria inválida.'
    end
    %w[size tamanhoAPe].each do |k|
      next unless changes.key?(k)
      next if k == 'tamanhoAPe' && changes[k].nil?

      n = Integer(changes[k], exception: false)
      raise Invalido, "#{k} inválido" unless n && n.between?(1, 4)

      changes[k] = n
    end
    %w[x y].each do |k|
      next unless changes.key?(k)

      n = Integer(changes[k], exception: false)
      raise Invalido, "#{k} inválido" unless n && n >= 0

      changes[k] = n
    end
    if changes.key?('montariaCompanheiroId') && !changes['montariaCompanheiroId'].nil? &&
       changes['montariaCompanheiroId'].to_s.length > 80
      raise Invalido, 'montariaCompanheiroId inválido'
    end
    changes
  end
end
