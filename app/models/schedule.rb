class Schedule < ApplicationRecord
  # `reserved` (data já confirmada) e `waiting` (à espera) preexistem;
  # os três últimos formam o ciclo de vida operacional da sessão.
  enum status: {
    reserved: 0,
    waiting: 1,
    in_progress: 2,
    completed: 3,
    cancelled: 4
  }

  belongs_to :date_dimension
  belongs_to :group
  belongs_to :battle_map, optional: true

  has_many :schedule_characters, dependent: :destroy
  has_many :characters, through: :schedule_characters
  has_many :campaign_notes, dependent: :nullify

  # Realtime session resources (Fase 1 — combate server-authoritative).
  has_one  :combat_state,  dependent: :destroy
  has_many :combat_npcs,   dependent: :destroy
  has_many :session_logs,  dependent: :destroy

  validates :status, :date_dimension_id, :title, presence: true
  validates :xp_awarded, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :scheduled_time,
            format: { with: /\A([01]?\d|2[0-3]):[0-5]\d\z/, message: "deve estar no formato HH:MM" },
            allow_blank: true
  validate  :highlights_must_be_well_formed
  validate  :unique_active_slot_per_group
  before_validation :normalize_highlights

  HIGHLIGHT_TYPES = %w[combat narrative discovery social].freeze
  after_commit :broadcast_created, on: :create
  after_commit :broadcast_updated, on: :update
  after_commit :broadcast_destroyed, on: :destroy

  # Sessões em que `character_id` participa via ScheduleCharacter.
  scope :for_character, ->(character_id) {
    joins(:schedule_characters).where(schedule_characters: { character_id: character_id })
  }

  # Hub / GET index (jogador não-DM global): todas as sessões que a conta deve
  # enxergar — grupos onde tem personagem (`User#groups`) + grupos que detém
  # como mestre da mesa (`User#owned_groups`, sem exigir PC) + qualquer sessão
  # em que um personagem seu está em `schedule_characters` (ex.: vínculo
  # explícito ou dados legados). Substitui `User#schedules` (through :groups),
  # que omitia `owned_groups` e só passava por personagens com `group_id`.
  def self.for_hub_player(user)
    return all if Group.user_is_dm?(user)

    gids = (user.groups.distinct.pluck(:id) + user.owned_groups.distinct.pluck(:id)).uniq
    ids = []
    ids.concat(where(group_id: gids).pluck(:id)) if gids.any?
    ids.concat(
      joins(:schedule_characters)
        .where(schedule_characters: { character_id: user.character_ids })
        .distinct
        .pluck(:id),
    )
    where(id: ids.uniq)
  end

  # Sessões cronologicamente ordenadas (ASC) — usado pela timeline da campanha.
  scope :chronological, -> { joins(:date_dimension).order('date_dimensions.date ASC, schedules.scheduled_time ASC NULLS LAST') }
  scope :active,        -> { where.not(status: :cancelled) }
  scope :concluded,     -> { where(status: :completed) }

  # Marca a sessão como em andamento e registra o início.
  # Idempotente: chamadas repetidas não sobrescrevem `started_at`.
  def start!
    return self if in_progress?
    raise StateError, "Sessão já concluída" if completed?
    raise StateError, "Sessão cancelada" if cancelled?

    update!(status: :in_progress, started_at: started_at || Time.current)
    self
  end

  # Conclui a sessão e distribui XP a todos os personagens vinculados.
  # `xp` é opcional; quando informado sobrescreve `xp_awarded`.
  # `highlights` opcional: substitui completamente a lista existente para
  # alimentar a Timeline do Hub. Aceita array de hashes `{text, type}`.
  def complete!(xp: nil, summary: nil, highlights: nil)
    raise StateError, "Sessão já concluída" if completed?
    raise StateError, "Sessão cancelada" if cancelled?

    transaction do
      attrs = { status: :completed, ended_at: Time.current }
      attrs[:started_at] = Time.current if started_at.blank?
      attrs[:xp_awarded] = xp.to_i if xp.present?
      attrs[:summary]    = summary if summary.present?
      attrs[:highlights] = highlights unless highlights.nil?
      update!(attrs)

      award = xp_awarded.to_i
      if award.positive?
        # Atualiza o XP de cada Sheet vinculada à sessão. Evitamos `update_all`
        # para que callbacks futuros (p. ex. recompute de proficiência) rodem.
        characters.includes(:sheet).find_each do |character|
          sheet = character.sheet
          next unless sheet
          sheet.update!(experience_points: sheet.experience_points.to_i + award)
        end
      end
    end
    self
  end

  # Cancela a sessão. Não distribui XP. Libera o slot do grupo nesse dia
  # (o partial unique index ignora canceladas, então a próxima reserva passa).
  def cancel!(reason: nil)
    return self if cancelled?
    raise StateError, "Sessão já concluída" if completed?

    attrs = { status: :cancelled }
    attrs[:summary] = reason if reason.present?
    update!(attrs)
    self
  end

  # Recap consolidado: aproveita o que a sessão já registrou para alimentar a
  # próxima ("Onde paramos?"). Usado pelo endpoint de timeline e pelo card
  # de criação de nova sessão do mesmo grupo.
  def recap_payload
    {
      id: id,
      title: title,
      summary: summary,
      highlights: Array(highlights),
      ended_at: ended_at,
      date: date_dimension&.date,
      xp_awarded: xp_awarded.to_i,
    }
  end

  class StateError < StandardError; end

  # Cancelamento: mestre (papel site-wide DM/Admin) ou jogador com personagem
  # em `schedule_characters` para esta sessão.
  def cancellable_by?(user)
    return false if user.nil?
    return true if Group.user_is_dm?(user)

    cids = user.respond_to?(:character_ids) ? user.character_ids : user.characters.ids
    return false if cids.blank?

    schedule_characters.exists?(character_id: cids)
  end

  private

  # Normaliza `highlights` em uma lista de hashes `{text, type}` com chaves
  # string. Aceita array de strings (cada item vira `{text:, type: 'narrative'}`)
  # e descarta entradas vazias. Garante consistência entre o que vem do controller
  # (parâmetros HTTP) e o que persistimos no banco.
  def normalize_highlights
    return if highlights.nil?
    raw = highlights.is_a?(Array) ? highlights : []

    self.highlights = raw.map do |item|
      next nil if item.nil?

      hash =
        if item.is_a?(Hash)
          item.transform_keys(&:to_s)
        elsif item.is_a?(String)
          { 'text' => item }
        else
          {}
        end

      text = hash['text'].to_s.strip
      next nil if text.empty?

      type = hash['type'].to_s.downcase
      type = 'narrative' unless HIGHLIGHT_TYPES.include?(type)
      { 'text' => text, 'type' => type }
    end.compact
  end

  def highlights_must_be_well_formed
    return if highlights.nil?
    unless highlights.is_a?(Array)
      errors.add(:highlights, 'deve ser uma lista')
      return
    end
    highlights.each_with_index do |item, idx|
      unless item.is_a?(Hash) && item['text'].is_a?(String) && item['text'].strip.present?
        errors.add(:highlights, "item #{idx} inválido (texto obrigatório)")
      end
    end
  end

  # Garante que o mesmo grupo não pode ter duas sessões ATIVAS no mesmo dia.
  # Sessões canceladas liberam o slot. Reforço em código além do partial index
  # do banco — o índice protege contra race condition; a validação dá mensagem
  # amigável ao cliente.
  def unique_active_slot_per_group
    return if cancelled?
    return if group_id.blank? || date_dimension_id.blank?

    conflict = self.class.active
                  .where(group_id: group_id, date_dimension_id: date_dimension_id)
                  .where.not(id: id)
                  .exists?
    if conflict
      errors.add(:base, "Este grupo já possui uma sessão ativa nesta data.")
    end
  end

  def broadcast_created
    ActionCable.server.broadcast(
      "group_#{group_id}_schedules",
      { event: 'created', schedule: ScheduleSerializer.serialize(self, include_dm_notes: false) },
    )
    Rails.logger.info({ event: 'schedule.created', schedule_id: id, group_id: group_id, date_dimension_id: date_dimension_id }.to_json)
  end

  def broadcast_updated
    ActionCable.server.broadcast(
      "group_#{group_id}_schedules",
      { event: 'updated', schedule: ScheduleSerializer.serialize(self, include_dm_notes: false) },
    )
    Rails.logger.info({ event: 'schedule.updated', schedule_id: id, group_id: group_id, date_dimension_id: date_dimension_id }.to_json)
  end

  def broadcast_destroyed
    ActionCable.server.broadcast("group_#{group_id}_schedules", { event: 'destroyed', schedule_id: id })
    Rails.logger.info({ event: 'schedule.destroyed', schedule_id: id, group_id: group_id, date_dimension_id: date_dimension_id }.to_json)
  end
end
