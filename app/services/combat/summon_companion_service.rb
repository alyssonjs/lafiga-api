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

      npc = @schedule.combat_npcs.alive.find_by(
        owner_character_id: @character.id, name: companion['name'].to_s,
      ) || @schedule.combat_npcs.create!(atributos_de(companion))

      linha = entrar_no_tracker!(npc, companion)
      # O `npc_upserted` sozinho NAO atualiza o tracker dos outros clientes: o
      # reducer de combate escuta `combatant_upserted`. Sem este eco, o familiar
      # so apareceria na iniciativa alheia depois de um reload.
      ::Combat::Broadcaster.combatant_upserted(linha) if linha
      npc
    end

    private

    # Poe o invocado no TRACKER quando ha combate ativo. Sem isso ele existiria
    # so na lista de NPCs da mesa: nao seria alvo, nao guardaria PV/condicoes e
    # — o que importa para a Investida do Familiar — nao teria economia de acao
    # propria para gastar a reacao.
    #
    # ⚠️ ANEXA NO FIM e NAO reordena. `SortInitiativePositionsService` reseta
    # `current_turn_index` para 0: chama-lo aqui mandaria a mesa de volta ao
    # topo da rodada no meio do combate. A iniciativa gravada e a DO DONO, para
    # que a proxima reordenacao feita pelo Mestre coloque o familiar ao lado
    # dele — e para nao entrar como `nil`, que TRAVA o avanco de turno.
    def entrar_no_tracker!(npc, companion)
      cs = @schedule.combat_state
      return nil unless cs&.active?
      return nil if cs.combat_combatants.exists?(combatable: npc)

      dono = cs.combat_combatants.find_by(combatable: @character)
      cs.combat_combatants.create!(
        combatable: npc,
        name: npc.name,
        position: (cs.combat_combatants.maximum(:position) || -1) + 1,
        initiative: dono&.initiative,
        tie_break_dex: (companion.dig('stats', 'dex') || 10).to_i,
        hp_current: npc.hp_current,
        hp_max: npc.hp_max,
        ac: npc.ac,
      )
    end

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
        speed: velocidade_em_pes(c['speed'], c['speedModes']),
        # ⚠️ Sem isto o multi-modo morria aqui: a montaria nadadora entrava no
        # combate com o deslocamento de ANDAR e mais nada. A coluna e o leitor
        # do front já existiam desde 31/08.
        speed_modes: modos_de_deslocamento(c),
        proficiency_bonus: c['profBonus'].to_i,
        stats: (c['stats'] || {}).transform_keys(&:to_s),
        attacks: Array(c['attacks']).map { |a| ataque(a) },
        notes: c['description'].to_s,
        # O PNG que o Mestre subiu no catálogo viaja com o invocado. Sem isto
        # ele morria aqui: o familiar entrava no combate como quadrado cinza,
        # igual a todos os outros.
        token_image_url: c['image'].presence,
      }
    end

    def positivo(v)
      n = v.to_i
      n.positive? ? n : nil
    end

    MODOS = %w[walk fly swim climb burrow].freeze

    # Os modos NUMÉRICOS do modelo, higienizados. Ausentes = `{}` (o leitor do
    # front cai na string, como sempre fez).
    def modos_de_deslocamento(companion)
      brutos = companion['speedModes']
      return {} unless brutos.is_a?(Hash)

      modos = brutos.slice(*MODOS).transform_values { |v| v.to_i }.reject { |_, v| v <= 0 }
      modos['hover'] = true if brutos['hover']
      modos
    end

    # O NPC guarda UM inteiro no `speed`. Com os modos declarados, o andar é a
    # resposta certa; sem eles, sobra ler o primeiro número do texto — que é o
    # que achatava o statblock e continua sendo só o fallback.
    def velocidade_em_pes(texto, modos = nil)
      andar = modos.is_a?(Hash) ? modos['walk'].to_i : 0
      return andar if andar.positive?

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
