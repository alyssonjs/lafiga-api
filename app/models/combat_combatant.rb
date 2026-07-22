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
  PER_TURN_TURN_STATE_KEYS = %w[attacksMade].freeze

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
    update!(
      actions_used: RESET_ACTIONS.dup,
      turn_state: Hash(turn_state).except(*PER_TURN_TURN_STATE_KEYS),
    )
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
