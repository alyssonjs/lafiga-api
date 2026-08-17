# Linha do tracker de iniciativa. Polimórfico: `combatable` aponta para
# `Character` (PC) ou `CombatNpc` (NPC). Veja a migration para o racional
# da modelagem (HP cacheado, position vs initiative, JSONB schemas).
class CombatCombatant < ApplicationRecord
  RESET_ACTIONS = { 'action' => false, 'bonus_action' => false, 'movement' => false, 'reaction' => false }.freeze
  RESET_DEATH_SAVES = { 'successes' => 0, 'failures' => 0 }.freeze

  # Chaves POR-TURNO do `turn_state`. O `turn_state` é OPACO por design
  # (válvula genérica do front — chaves futuras podem durar vários turnos,
  # ex.: buffs), então NUNCA zeramos o hash inteiro na virada de turno.
  # Esta lista é a exceção documentada à opacidade: apenas chaves
  # comprovadamente por-turno entram aqui e são removidas em
  # `reset_turn_actions!`; todo o resto do hash é preservado intacto.
  # Chaves por-turno futuras (ex.: budget de ataques extra) devem ser
  # adicionadas a esta lista.
  # `bearFormAttacks`: composição do multiataque da Forma de Urso (mordida/garra/
  # arma) — por-turno, zera junto com `attacksMade` no início do turno.
  # `protectiveRageAcActive`: Fúria Protetora (Protetor Tribal L3) — ação bônus
  # concede +2 CA vs corpo-a-corpo "até o início do seu PRÓXIMO turno"; zerar no
  # início do turno do dono é exatamente essa expiração.
  # `pendingBardicInspiration` NÃO entra aqui: quando a decisão vem de um TR
  # IMPOSTO, ela é a CHAVE que destrava a 2ª fase (aplicar dano/condição). Apagá-la
  # sozinha deixava o `pendingTargetSave` órfão — o card dizia "resolvido", o efeito
  # nunca era aplicado e a hotbar de quem conjurou ficava travada para sempre.
  # A varredura dela mora em `sweep_orphan_bardic_decision`, que descarta o TR junto.
  # `battleMagic` (Bardo, Colégio da Bravura L14): a janela de ataque com arma
  # como AÇÃO BÔNUS nasce de uma magia conjurada com a AÇÃO — vale só naquele
  # turno. Sem entrar aqui, um turno em que o Bardo conjurou deixaria a lane de
  # bônus acesa nos turnos seguintes.
  PER_TURN_TURN_STATE_KEYS = %w[
    attacksMade bearFormAttacks protectiveRageAcActive battleMagic
  ].freeze

  belongs_to :combat_state
  belongs_to :combatable, polymorphic: true

  validates :name, presence: true
  validates :initiative, numericality: { only_integer: true }, allow_nil: true
  validates :initiative_bonus, :hp_current, :hp_max, :ac, :temp_hp, :position, :tie_break_dex,
            numericality: { only_integer: true }
  validates :hp_current, numericality: { greater_than_or_equal_to: 0 }
  validates :hp_max,     numericality: { greater_than_or_equal_to: 0 }
  validates :temp_hp,    numericality: { greater_than_or_equal_to: 0 }
  validates :position,   numericality: { greater_than_or_equal_to: 0 }
  validate  :conditions_well_formed
  validate  :actions_used_well_formed
  validate  :death_saves_well_formed
  validate  :combatable_belongs_to_session  # G13

  before_validation :ensure_default_jsonb
  before_save       :bump_turn_state_rev       # versiona TODA escrita do turn_state
  before_save       :auto_resolve_death_saves  # G15
  after_save        :sync_npc_defeated_state   # G8

  # Aplica dano respeitando temp_hp. Retorna o dano efetivo aplicado a hp_current
  # (já descontado o que temp_hp absorveu). Marca `is_dead=true` se hp_current
  # chegar a 0 e for NPC; PCs ficam estabilizando via death_saves.
  def apply_damage!(amount)
    raise ArgumentError, 'damage deve ser >= 0' if amount.to_i.negative?
    remaining = amount.to_i

    if temp_hp.positive?
      absorbed = [temp_hp, remaining].min
      self.temp_hp = temp_hp - absorbed
      remaining -= absorbed
    end

    new_hp = [hp_current - remaining, 0].max
    self.hp_current = new_hp

    if new_hp.zero? && combatable_type == CombatNpc.name
      self.is_dead = true
    end

    save!
    self
  end

  def heal!(amount)
    raise ArgumentError, 'heal deve ser >= 0' if amount.to_i.negative?
    self.hp_current = [hp_current + amount.to_i, hp_max].min
    self.is_stabilized = false if hp_current.positive?
    self.is_dead = false if hp_current.positive?
    save!
    self
  end

  # Reseta as ações usadas no início do turno deste combatente.
  # Também remove do `turn_state` APENAS as chaves por-turno
  # (PER_TURN_TURN_STATE_KEYS), preservando o resto do hash — garante que o
  # budget de ataques não fica sujo quando nenhum cliente está aberto na
  # virada (o front continua zerando defensivamente; a operação é idempotente).
  def reset_turn_actions!
    ts = Hash(turn_state)
    # Houserule Defensor da Tribo (Protetor Tribal L10) — "1 reação por RODADA":
    # ao usar a reação, `reactionUsedRound` guarda a rodada do uso. Enquanto a
    # rodada da sessão for <= a rodada gravada (mesma rodada), a reação NÃO
    # recarrega neste reset (fica gasta até o fim da rodada, inclusive no turno do
    # Defensor). Numa RODADA NOVA (round > gravado), libera e limpa o marcador.
    used_round = ts['reactionUsedRound']
    cur_round = combat_state&.round
    keep_reaction =
      used_round.is_a?(Integer) && cur_round.is_a?(Integer) && cur_round <= used_round
    next_actions = RESET_ACTIONS.dup
    next_actions['reaction'] = true if keep_reaction
    # `reaction` NUNCA foi chave legítima de turn_state — só existiu como marcador
    # otimista de front (bug: nunca limpo). Removê-la aqui AUTO-CURA combatentes
    # presos por esse flag stale na próxima virada de turno deles. O estado real
    # de reação vive em `actions_used.reaction` + `reactionUsedRound` (round-lock).
    next_ts = ts.except(*PER_TURN_TURN_STATE_KEYS, 'reaction')
    next_ts = next_ts.except('reactionUsedRound') unless keep_reaction
    next_ts = sweep_expired_bardic_inspiration(next_ts, cur_round)
    next_ts = sweep_expired_countercharm(next_ts, cur_round)
    next_ts = sweep_orphan_bardic_decision(next_ts)
    update!(actions_used: next_actions, turn_state: next_ts)
  end

  # Erro de concorrencia: alguem gravou o `turn_state` entre a leitura do cliente
  # e esta escrita. Vira 409 no controller, com o combatente atual no corpo para
  # o cliente reconciliar sem um GET extra.
  class TurnStateRevisionConflict < StandardError
    attr_reader :current_rev

    def initialize(current_rev)
      @current_rev = current_rev
      super("turn_state foi alterado por outra escrita (rev atual: #{current_rev})")
    end
  end

  TURN_STATE_OPS = %w[set merge delete].freeze

  # Aplica MUTACOES GRANULARES ao `turn_state`, todas na mesma transacao e sob
  # lock da linha.
  #
  # Por que existe: o caminho antigo (`update` com o hash INTEIRO montado no
  # cliente) perde escritas concorrentes por construcao — quem grava por ultimo
  # ressuscita as chaves que o outro apagou. Aqui o cliente declara a INTENCAO
  # ("apaga `pendingTargetSave`", "grava `bardicInspiration`") e o servidor aplica
  # sobre o estado FRESCO, entao duas intencoes disjuntas nunca se desfazem.
  #
  # `base_rev` e OPCIONAL e serve para operacoes que dependem do que foi lido
  # (ex.: "gasta o dado que eu vi"): se a revisao mudou, levanta conflito em vez
  # de gravar sobre premissa velha. Ops idempotentes (delete de pending) podem
  # omitir.
  #
  # Ops (apenas chaves de PRIMEIRO NIVEL — e a granularidade dos pendings, que e
  # onde a concorrencia dói; caminhos aninhados seriam complexidade sem demanda):
  #   { 'op' => 'set',    'key' => 'pendingTargetSave', 'value' => {...} }
  #   { 'op' => 'merge',  'key' => 'turnFlags',         'value' => {...} }  # merge raso
  #   { 'op' => 'delete', 'key' => 'pendingTargetSave' }
  #
  # Retorna a nova revisao.
  def apply_turn_state_ops!(ops, base_rev: nil)
    raise ArgumentError, 'ops deve ser um array' unless ops.is_a?(Array)

    new_rev = nil
    with_lock do
      reload
      if base_rev.present? && Integer(base_rev) != turn_state_rev
        raise TurnStateRevisionConflict, turn_state_rev
      end

      next_ts = Hash(turn_state)
      ops.each { |op| next_ts = apply_turn_state_op(next_ts, op) }
      new_rev = turn_state_rev + 1
      update!(turn_state: next_ts, turn_state_rev: new_rev)
    end
    new_rev
  end

  def apply_turn_state_op(ts, op)
    o = op.respond_to?(:to_unsafe_h) ? op.to_unsafe_h : op
    o = o.stringify_keys if o.respond_to?(:stringify_keys)
    raise ArgumentError, 'op malformada' unless o.is_a?(Hash)

    kind = o['op'].to_s
    key  = o['key'].to_s
    raise ArgumentError, "op invalida: #{kind}" unless TURN_STATE_OPS.include?(kind)
    raise ArgumentError, 'key obrigatoria' if key.empty?

    case kind
    when 'delete'
      ts.except(key)
    when 'set'
      ts.merge(key => o['value'])
    when 'merge'
      current = ts[key]
      value   = o['value']
      raise ArgumentError, 'merge exige value do tipo objeto' unless value.is_a?(Hash)

      base = current.is_a?(Hash) ? current : {}
      ts.merge(key => base.merge(value))
    end
  end

  # Decisão de Inspiração Bárdica não resolvida até o turno do portador voltar: a
  # janela da regra ("antes do resultado ser declarado") já fechou. Descarta a
  # decisão E, se ela segurava um TR imposto (`resumeSaveD20`), o próprio TR —
  # senão o pending fica órfão e trava a hotbar de quem impôs o teste. Descartar
  # equivale ao "Dispensar TRs" do Mestre: o efeito simplesmente não se aplica.
  def sweep_orphan_bardic_decision(ts)
    pending = ts['pendingBardicInspiration']
    return ts unless pending.is_a?(Hash)

    next_ts = ts.except('pendingBardicInspiration')
    next_ts = next_ts.except('pendingTargetSave') if pending.key?('resumeSaveD20')
    next_ts
  end

  # Canção de Proteção (Bardo Nv 6) dura até o FIM do próximo turno do Bardo.
  # Este reset roda no INÍCIO do turno dele — então na rodada seguinte à ativação a
  # atuação AINDA VALE (só acaba quando aquele turno terminar). Limpar aqui de forma
  # incondicional (como as PER_TURN_TURN_STATE_KEYS) cortaria um turno inteiro de
  # duração; por isso a varredura só age a partir da rodada +2.
  def sweep_expired_countercharm(ts, current_round)
    cc = ts['countercharm']
    return ts unless cc.is_a?(Hash)

    activated = cc['activatedRound']
    return ts unless activated.is_a?(Integer) && current_round.is_a?(Integer)
    return ts if current_round <= activated + 1

    ts.except('countercharm')
  end

  # Inspiração Bárdica dura 10 minutos (100 rodadas) — passado esse prazo o dado
  # simplesmente não vale mais. Sem esta varredura ele ficaria no jsonb para
  # sempre: o front esconde o badge e recusa a oferta, mas o estado morto seguia
  # viajando em todo `combatant_upserted`. Roda no início do turno do portador,
  # que é quando já mexemos no `turn_state` dele.
  def sweep_expired_bardic_inspiration(ts, current_round)
    insp = ts['bardicInspiration']
    return ts unless insp.is_a?(Hash)

    expires = insp['expiresAtRound']
    return ts unless expires.is_a?(Integer) && current_round.is_a?(Integer)
    return ts if current_round < expires

    ts.except('bardicInspiration', 'pendingBardicInspiration')
  end

  # Decrementa `turns_left` no fim da rodada (ciclo completo da iniciativa), PHB.
  # `turns_left` ausente ou nil = indefinido; 0 = indefinido; 1 = remove neste tick.
  # @return [Boolean] true se `conditions` foi persistido com mudança
  def tick_conditions_at_end_of_turn!
    list = conditions
    return false if list.blank?

    new_list = tick_condition_rows_for_end_of_turn(list)
    assign_attributes(conditions: new_list)
    return false unless changed?

    save!
    true
  end

  # Aplica resultado de death save (PCs apenas). +1 success ou +1 failure.
  # 3 sucessos => is_stabilized=true e zera contadores. 3 falhas => is_dead=true.
  # Veja `auto_resolve_death_saves` (que cuida do auto-resolve em qualquer
  # caminho que mexa direto em `death_saves`).
  def record_death_save!(kind)
    raise ArgumentError, "kind deve ser :success ou :failure" unless %i[success failure].include?(kind.to_sym)
    saves = death_saves.dup
    field = kind.to_sym == :success ? 'successes' : 'failures'
    saves[field] = [saves[field].to_i + 1, 3].min
    self.death_saves = saves
    save!
    self
  end

  private

  # A revisao acompanha TODA escrita do `turn_state`, nao so a via de ops — senao
  # a valvula REPLACE antiga (`PATCH combatant`) avancaria o estado sem avancar a
  # versao, e o cliente descartaria como "stale" um eco que na verdade e novo.
  # Nao re-incrementa quando `apply_turn_state_ops!` ja definiu a revisao.
  def bump_turn_state_rev
    return unless turn_state_changed?
    return if turn_state_rev_changed?

    self.turn_state_rev = turn_state_rev.to_i + 1
  end

  def ensure_default_jsonb
    self.conditions   = []                       if conditions.nil?
    self.actions_used = RESET_ACTIONS.dup        if actions_used.blank?
    self.death_saves  = RESET_DEATH_SAVES.dup    if death_saves.blank?
    # turn_state é OPACO de propósito (válvula genérica de persistência de
    # estado de turno do front). Sem validação de schema — qualquer JSON.
    # Na virada de turno, `reset_turn_actions!` remove SÓ as chaves listadas
    # em PER_TURN_TURN_STATE_KEYS; o restante é gerenciado pelo front.
    self.turn_state   = {}                       if turn_state.blank?
  end

  # G15 — Auto-resolve baseado em death_saves. Garante que UI/back nunca
  # divirjam: se o front mandar successes=3 sem setar is_stabilized=true, o
  # backend resolve. Se mandar failures=3 sem is_dead=true, idem.
  #
  # Após estabilizar/morrer, zera os contadores (D&D: estabilizado deixa de
  # rolar; morto não há recuperação por save). Isso evita "death save zumbi"
  # caso o personagem volte mais tarde via cura.
  def auto_resolve_death_saves
    return unless death_saves.is_a?(Hash)
    s = death_saves['successes'].to_i
    f = death_saves['failures'].to_i

    if f >= 3
      self.is_dead = true
      self.death_saves = RESET_DEATH_SAVES.dup
    elsif s >= 3
      self.is_stabilized = true
      self.death_saves = RESET_DEATH_SAVES.dup
    end
  end

  # G8 — Quando combatant de NPC vira is_dead=true, marca o CombatNpc como
  # defeated_at. Quando combatant de NPC volta a ter HP > 0 (raro: revive via
  # spell/heal), reverte. PCs não tocam neste callback (sua "morte" é
  # resolvida via death_saves e ressurreição é via narrativa, não via flag).
  def sync_npc_defeated_state
    return unless combatable_type == CombatNpc.name
    npc = combatable
    return unless npc

    if is_dead && npc.alive?
      npc.update_column(:defeated_at, Time.current)  # update_column evita callback recursivo
    elsif !is_dead && !npc.alive? && hp_current.positive?
      npc.update_column(:defeated_at, nil)
    end
  end

  # G13 — Garante que o combatable pertence à mesma sessão/grupo do
  # combat_state. Sem isso, dá pra adicionar Character de outro grupo no
  # tracker — fonte de bugs e vazamento de dados.
  def combatable_belongs_to_session
    return if combat_state.nil? || combatable.nil?

    schedule = combat_state.schedule
    return if schedule.nil?

    case combatable_type
    when 'Character'
      # Sessões-fantasma de teste (sandbox) não têm grupo e servem para
      # exercitar combate com qualquer ficha — sem restrição de grupo.
      return if schedule.respond_to?(:sandbox) && schedule.sandbox

      # Fichas explicitamente vinculadas à mesa pelo DM (aba NPCs →
      # linked_npc_character_ids, ou PC tratado como NPC só nesta sessão) podem
      # ser de outro grupo por desenho — o DM as adicionou de propósito.
      linked_ids = Array(schedule.linked_npc_sheet_ids_normalized) +
                   Array(schedule.dm_temp_npc_character_ids_normalized)
      return if linked_ids.include?(combatable.id)

      group_id = combatable.group_id
      if group_id.present? && group_id != schedule.group_id
        errors.add(:combatable, 'pertence a outro grupo')
      end
    when 'CombatNpc'
      if combatable.schedule_id != schedule.id
        errors.add(:combatable, 'pertence a outra sessão')
      end
    end
  end

  def tick_condition_rows_for_end_of_turn(list)
    Array(list).filter_map do |raw|
      next nil unless raw.is_a?(Hash)

      h = raw.stringify_keys
      id = h['id'].to_s.strip
      next nil if id.blank?

      tl_raw = h.key?('turns_left') ? h['turns_left'] : nil
      if tl_raw.nil?
        h
      else
        tl = tl_raw.to_i
        if tl <= 0
          h
        elsif tl > 1
          h.merge('turns_left' => tl - 1)
        end
        # tl == 1 → expira (omitir)
      end
    end
  end

  def conditions_well_formed
    return if conditions.blank?
    return errors.add(:conditions, 'deve ser uma lista') unless conditions.is_a?(Array)
    conditions.each_with_index do |cond, idx|
      unless cond.is_a?(Hash) && cond['id'].is_a?(String) && cond['id'].strip.present?
        errors.add(:conditions, "item #{idx} sem id")
      end
    end
  end

  def actions_used_well_formed
    return errors.add(:actions_used, 'deve ser um Hash') unless actions_used.is_a?(Hash)
    missing = RESET_ACTIONS.keys - actions_used.keys.map(&:to_s)
    errors.add(:actions_used, "chaves faltando: #{missing.join(', ')}") if missing.any?
  end

  def death_saves_well_formed
    return errors.add(:death_saves, 'deve ser um Hash') unless death_saves.is_a?(Hash)
    s = death_saves['successes'].to_i
    f = death_saves['failures'].to_i
    errors.add(:death_saves, 'successes deve estar entre 0 e 3') unless (0..3).include?(s)
    errors.add(:death_saves, 'failures deve estar entre 0 e 3')  unless (0..3).include?(f)
  end
end
