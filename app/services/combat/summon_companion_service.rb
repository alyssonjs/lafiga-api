# frozen_string_literal: true

module Combat
  # Traz um COMPANION da ficha para o tracker como NPC com DONO.
  #
  # ⚠️ POR QUE UM CAMINHO PRÓPRIO, e não o `create` de NPC. Aquele é só-DM
  # (`authorize_write!`), e com razão: NPC é do Mestre. Um invocado não é —
  # familiar do Pacto da Corrente e morto-vivo do patrono da Morte são
  # convocados pelo JOGADOR e obedecem a ele. A autorização aqui é outra e mais
  # estreita: o convocador tem de ser dono do personagem, e o companion tem de
  # estar na ficha DELE.
  #
  # ⚠️ IDEMPOTENTE por (mesa, dono, nome) entre os vivos. Sem isso, dois cliques
  # (ou um duplo-envio) colocariam dois familiares idênticos no tracker, e
  # nenhum dos dois seria "o" familiar — o jogador não teria como saber em qual
  # gastar a reação.
  class SummonCompanionService
    class Erro < StandardError; end

    def initialize(schedule:, character:, companion_id:, user:)
      @schedule = schedule
      @character = character
      @companion_id = companion_id.to_s
      @user = user
    end

    def call
      raise Erro, 'Personagem não encontrado.' unless @character
      raise Erro, 'Você não controla este personagem.' unless @character.user_id == @user&.id
      raise Erro, 'Este personagem não está na mesa.' unless mesmo_grupo?

      companion = buscar_companion
      raise Erro, 'Companion não encontrado na ficha.' unless companion

      existente = @schedule.combat_npcs.alive.find_by(
        owner_character_id: @character.id, name: companion['name'].to_s,
      )
      return existente if existente

      @schedule.combat_npcs.create!(atributos_de(companion))
    end

    private

    def mesmo_grupo?
      @schedule.group_id.present? && @character.group_id == @schedule.group_id
    end

    def buscar_companion
      lista = Array(@character.sheet&.companions)
      lista.find { |c| c.is_a?(Hash) && c['id'].to_s == @companion_id }
    end

    def atributos_de(c)
      {
        name: c['name'].to_s,
        owner_character_id: @character.id,
        hp_max: c['hpMax'].to_i,
        # `hpCurrent` pode vir 0 numa ficha nunca tocada — invocar com 0 PV
        # colocaria o familiar morto no tracker.
        hp_current: positivo(c['hpCurrent']) || c['hpMax'].to_i,
        ac: c['ac'].to_i,
        speed: velocidade_em_pes(c['speed']),
        proficiency_bonus: c['profBonus'].to_i,
        stats: (c['stats'] || {}).transform_keys(&:to_s),
        attacks: Array(c['attacks']).map { |a| ataque(a) },
        notes: c['description'].to_s,
      }
    end

    def positivo(v)
      n = v.to_i
      n.positive? ? n : nil
    end

    # O companion guarda a velocidade como TEXTO ("40 ft, escalada 30 ft") e o
    # NPC guarda um inteiro. Lê o primeiro número — a locomoção alternativa não
    # cabe no campo e fica nas notas.
    def velocidade_em_pes(texto)
      texto.to_s[/\d+/]&.to_i
    end

    def ataque(a)
      {
        'name' => a['name'].to_s,
        'attack_bonus' => a['attackBonus'].to_s,
        'damage_dice' => a['damage'].to_s,
        'damage_type' => a['damageType'].to_s,
        'range' => a['range'].to_s,
      }
    end
  end
end
