class Sheet < ApplicationRecord
  COIN_KEYS = %w[cp sp ep gp pp].freeze
  COIN_DEFAULTS = COIN_KEYS.each_with_object({}) { |k, h| h[k] = 0 }.freeze
  PRIMARY_POUCH_ID = 'primary'.freeze

  validates :character_id, uniqueness: true
  validate :sub_race_belongs_to_race
  validate :coins_must_be_valid
  validate :coin_pouches_must_be_valid

  belongs_to :character
  belongs_to :race
  belongs_to :sub_race, optional: true
  belongs_to :alignment, optional: true
  belongs_to :background, optional: true

  has_many :sheet_klasses
  has_many :klasses, through: :sheet_klasses
  has_many :sub_klasses, through: :sheet_klasses
  has_many :sheet_feats, dependent: :destroy
  has_many :feats, through: :sheet_feats
  has_many :sheet_items, dependent: :destroy

  has_one :runtime_state, class_name: 'SheetRuntimeState', dependent: :destroy

  before_validation :reconcile_coins_into_primary_pouch_if_needed
  before_validation :normalize_coin_pouches
  before_validation :sync_aggregate_coins_from_pouches

  # Devolve o runtime_state, criando uma row vazia (com defaults) se ainda
  # não existir. Operação idempotente — usada por controllers/services que
  # leem ou mutam runtime sem precisar saber se já foi inicializado.
  def runtime!
    runtime_state || create_runtime_state!
  end

  # Soma de todas as algibeiras (contrato legado da UI "Carteira" agregada).
  def wallet_hash
    aggregate_wallet_from_pouches(normalized_coin_pouches_array)
  end

  # Array de hashes com chaves string para JSON.
  def normalized_coin_pouches_array
    normalize_coin_pouches_array!(read_attribute(:coin_pouches))
  end

  def coin_pouches_for_api
    normalized_coin_pouches_array.map do |p|
      {
        id: p['id'],
        name: p['name'].to_s,
        cp: p['cp'].to_i,
        sp: p['sp'].to_i,
        ep: p['ep'].to_i,
        gp: p['gp'].to_i,
        pp: p['pp'].to_i
      }
    end
  end

  # Aplica delta às moedas da **algibeira primaria** (Carteira).
  def apply_coin_delta!(delta)
    list = dup_pouches
    idx = primary_pouch_index(list)
    apply_delta_to_pouch_at!(list, idx, delta)
    assign_pouches_and_save!(list)
  end

  def apply_coin_delta_to_pouch!(pouch_id, delta)
    list = dup_pouches
    idx = list.index { |p| p['id'].to_s == pouch_id.to_s }
    raise ActiveRecord::RecordNotFound, 'Algibeira não encontrada' unless idx

    apply_delta_to_pouch_at!(list, idx, delta)
    assign_pouches_and_save!(list)
  end

  # Substitui o conteúdo da **algibeira primaria** (compat com carteira unica).
  def set_wallet!(values)
    list = dup_pouches
    idx = primary_pouch_index(list)
    list[idx] = merge_pouch_coins(list[idx], sanitize_wallet(values))
    assign_pouches_and_save!(list)
  end

  def set_pouch_wallet!(pouch_id, values)
    list = dup_pouches
    idx = list.index { |p| p['id'].to_s == pouch_id.to_s }
    raise ActiveRecord::RecordNotFound, 'Algibeira não encontrada' unless idx

    list[idx] = merge_pouch_coins(list[idx], sanitize_wallet(values))
    assign_pouches_and_save!(list)
  end

  # DM: nova algibeira vazia com nome customizado.
  def add_coin_pouch!(name)
    nm = name.to_s.strip
    raise ArgumentError, 'Nome obrigatório' if nm.blank?

    list = dup_pouches
    list << {
      'id' => SecureRandom.uuid,
      'name' => nm[0, 80]
    }.merge(COIN_DEFAULTS.stringify_keys)
    assign_pouches_and_save!(list)
  end

  # DM: renomeia algibeira (nao permite esvaziar nome).
  def rename_coin_pouch!(pouch_id, new_name)
    nm = new_name.to_s.strip
    raise ArgumentError, 'Nome obrigatório' if nm.blank?

    list = dup_pouches
    p = list.find { |x| x['id'].to_s == pouch_id.to_s }
    raise ActiveRecord::RecordNotFound, 'Algibeira não encontrada' unless p

    p['name'] = nm[0, 80]
    assign_pouches_and_save!(list)
  end

  # DM: remove algibeira se estiver vazia e nao for a ultima.
  def destroy_coin_pouch!(pouch_id)
    list = dup_pouches
    raise ArgumentError, 'Deve existir ao menos uma algibeira' if list.size <= 1

    p = list.find { |x| x['id'].to_s == pouch_id.to_s }
    raise ActiveRecord::RecordNotFound, 'Algibeira não encontrada' unless p

    if p['id'] == PRIMARY_POUCH_ID
      raise ArgumentError, 'A algibeira primária (Carteira) não pode ser removida'
    end

    unless pouch_empty?(p)
      raise ArgumentError, 'Só é possível remover uma algibeira sem moedas'
    end

    list.reject! { |x| x['id'].to_s == pouch_id.to_s }
    assign_pouches_and_save!(list)
  end

  # Move moedas entre duas algibeiras num único save (origem/destino distintos).
  # `amounts_hash` — apenas chaves COIN_KEYS; valores inteiros >= 0 a debitar da origem.
  def transfer_pouch_coins!(from_pouch_id, to_pouch_id, amounts_hash)
    from_id = from_pouch_id.to_s
    to_id = to_pouch_id.to_s
    raise ArgumentError, 'Origem e destino não podem ser iguais' if from_id == to_id

    list = dup_pouches
    from_idx = list.index { |p| p['id'].to_s == from_id }
    to_idx = list.index { |p| p['id'].to_s == to_id }
    raise ActiveRecord::RecordNotFound, 'Algibeira de origem não encontrada' unless from_idx
    raise ActiveRecord::RecordNotFound, 'Algibeira de destino não encontrada' unless to_idx

    slice = sanitize_wallet(amounts_hash)
    moved = false
    COIN_KEYS.each do |k|
      want = slice[k].to_i
      next if want <= 0

      moved = true
      have = list[from_idx][k].to_i
      if want > have
        raise ArgumentError, "Saldo insuficiente em #{k.upcase} (pedido #{want}, disponível #{have})"
      end

      list[from_idx][k] = have - want
      list[to_idx][k] = list[to_idx][k].to_i + want
    end
    raise ArgumentError, 'Informe ao menos uma moeda com valor positivo' unless moved

    assign_pouches_and_save!(list)
  end

  private

  def reconcile_coins_into_primary_pouch_if_needed
    return unless will_save_change_to_coins? && !will_save_change_to_coin_pouches?

    sanitized = sanitize_wallet(coins)
    list = normalize_coin_pouches_array!(read_attribute(:coin_pouches))
    idx = primary_pouch_index(list)
    list[idx] = merge_pouch_coins(list[idx], sanitized)
    self.coin_pouches = list
  end

  def normalize_coin_pouches
    self.coin_pouches = normalize_coin_pouches_array!(read_attribute(:coin_pouches))
  end

  def sync_aggregate_coins_from_pouches
    list = Array(coin_pouches)
    self.coins = aggregate_wallet_from_pouches(list)
  end

  def normalize_coin_pouches_array!(raw)
    list = case raw
           when Array then raw.map { |e| e.is_a?(Hash) ? e.stringify_keys : {} }
           when String
             begin
               JSON.parse(raw)
             rescue StandardError
               []
             end
           else
             []
           end

    list = [default_primary_pouch] if list.blank?

    seen_ids = {}
    list.each_with_index do |p, i|
      p = p.stringify_keys
      p['id'] = PRIMARY_POUCH_ID if i.zero? && p['id'].blank?
      p['id'] = SecureRandom.uuid if p['id'].blank?
      # evita colisao accidental
      if seen_ids[p['id']]
        p['id'] = SecureRandom.uuid
      end
      seen_ids[p['id']] = true
      p['id'] = PRIMARY_POUCH_ID if i.zero?

      p['name'] = 'Carteira' if p['name'].blank?
      p['name'] = p['name'].to_s[0, 80]
      COIN_KEYS.each do |k|
        p[k] = [p[k].to_i, 0].max
      end
      list[i] = p
    end

    list
  end

  def default_primary_pouch
    base = COIN_DEFAULTS.stringify_keys
    c = read_attribute(:coins) || {}
    COIN_KEYS.each { |k| base[k] = [[c[k], c[k.to_sym]].compact.first.to_i, 0].max }
    { 'id' => PRIMARY_POUCH_ID, 'name' => 'Carteira' }.merge(base)
  end

  def dup_pouches
    normalize_coin_pouches_array!(read_attribute(:coin_pouches)).map(&:dup)
  end

  def primary_pouch_index(list)
    idx = list.index { |p| p['id'] == PRIMARY_POUCH_ID }
    idx || 0
  end

  def merge_pouch_coins(pouch, wallet_slice)
    out = pouch.stringify_keys
    wallet_slice.each do |k, v|
      out[k] = v if COIN_KEYS.include?(k)
    end
    out
  end

  def sanitize_wallet(values)
    out = COIN_DEFAULTS.dup
    Hash(values).each do |k, v|
      key = k.to_s
      out[key] = [v.to_i, 0].max if COIN_KEYS.include?(key)
    end
    out
  end

  def aggregate_wallet_from_pouches(list)
    sum = COIN_DEFAULTS.dup
    list.each do |p|
      COIN_KEYS.each { |k| sum[k] += p[k].to_i }
    end
    sum
  end

  def apply_delta_to_pouch_at!(list, idx, delta)
    p = list[idx]
    COIN_KEYS.each do |k|
      next unless delta.key?(k) || delta.key?(k.to_sym)

      v = (delta[k] || delta[k.to_sym]).to_i
      p[k] = p[k].to_i + v
      if p[k].negative?
        errors.add(:coin_pouches, "#{k} não pode ficar negativo")
        raise ActiveRecord::RecordInvalid, self
      end
    end
  end

  def assign_pouches_and_save!(list)
    self.coin_pouches = list
    self.coins = aggregate_wallet_from_pouches(list)
    save!
  end

  def pouch_empty?(p)
    COIN_KEYS.all? { |k| p[k].to_i <= 0 }
  end

  def coins_must_be_valid
    Hash(coins).each do |k, v|
      key = k.to_s
      next unless COIN_KEYS.include?(key)

      errors.add(:coins, "#{key} não pode ser negativo") if v.to_i.negative?
    end
  end

  def coin_pouches_must_be_valid
    return unless coin_pouches.is_a?(Array)

    Array(coin_pouches).each do |p|
      next unless p.is_a?(Hash)

      ph = p.stringify_keys
      COIN_KEYS.each do |k|
        errors.add(:coin_pouches, "#{k} não pode ser negativo") if ph[k].to_i.negative?
      end
    end
  end

  def sub_race_belongs_to_race
    return unless sub_race.present? && sub_race.race_id != race_id

    errors.add(:sub_race, 'deve pertencer à raça selecionada.')
  end
end
