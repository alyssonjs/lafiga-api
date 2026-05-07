class SheetItem < ApplicationRecord
  belongs_to :sheet
  belongs_to :item, optional: true

  # ── Slots aceitos ─────────────────────────────────────────────────
  # Slots clássicos (combate / armadura)
  COMBAT_SLOTS    = %w[main_hand off_hand armor shield].freeze
  # Slots de acessório (Fase 2.1) — desbloqueiam itens como anel da
  # vontade, manopla da força, manto de resistência, botas aladas, etc.
  # ring_left/ring_right permitem ATÉ 2 anéis equipados simultaneamente.
  ACCESSORY_SLOTS = %w[
    ring_left ring_right amulet cloak boots helmet gloves belt
    circlet earrings bracelet_left bracelet_right
  ].freeze
  ALL_SLOTS       = (COMBAT_SLOTS + ACCESSORY_SLOTS).freeze

  validates :sheet_id, presence: true
  validates :item_name, presence: true
  validates :quantity, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :slot, inclusion: { in: ALL_SLOTS, allow_nil: true,
                                message: "deve ser um destes: #{ALL_SLOTS.join(', ')}" }
  validate  :validate_equipment_proficiency

  before_validation :resolve_catalog_item
  before_save :sanitize_slot
  after_save  :enforce_slot_exclusivity_and_conflicts

  # Serialização canônica usada pelo frontend (CharacterBag/HubBag).
  # Mantém o mesmo shape que `EquipmentProfileService#as_json` para que o
  # mapper único `mapApiInventoryItem` funcione tanto vindo do GET character
  # quanto dos endpoints `/sheet_items`.
  def as_inventory_json
    weapon_props = begin
      EquipmentRules.weapon_props(self)
    rescue NameError
      nil
    end

    {
      id: id,
      index: item_index,
      name: item_name,
      category: category,
      quantity: quantity,
      equipped: equipped,
      slot: slot,
      source: source,
      props: props_json,
      weapon_props: weapon_props,
      notes: notes,
    }
  end

  private

  # Garante que todo SheetItem aponte para um Item canonico no catalogo.
  # Se o caller (controller, service, importer) ja passou item_id, respeita.
  # Caso contrario, resolve via ItemResolver — que tenta achar Item existente
  # por nome/slug ou cria um novo a partir das tabelas EquipmentRules. O
  # `item_index` tambem e populado para manter consistencia com o frontend
  # (mapApiInventoryItem usa `index` como chave estavel pra weapons).
  def resolve_catalog_item
    return if item_id.present?
    return if item_name.blank?

    resolver = ItemResolver.new
    item = resolver.resolve(name: item_name, category: category)
    return unless item

    self.item_id = item.id
    self.item_index = item.api_index if item_index.blank?
  rescue StandardError => e
    Rails.logger.warn("SheetItem#resolve_catalog_item failed: #{e.class}: #{e.message}")
  end

  def sanitize_slot
    unless equipped
      self.slot = nil
    end
  end

  def validate_equipment_proficiency
    return unless equipped
    # armor/shield checks
    if slot.to_s == 'shield'
      cats = EquipmentRules.allowed_armor_categories(sheet)
      unless cats.include?('shields')
        errors.add(:base, 'Sem proficiência em escudos')
      end
    end
    if slot.to_s == 'armor' || armor_like?
      res = EquipmentRules.can_wear?(sheet: sheet, armor_item: self)
      errors.add(:base, (res[:reason] || 'Sem proficiência em armadura')) unless res[:ok]
    end

    # off-hand: arma deve ser leve (regra básica de duas armas)
    if slot.to_s == 'off_hand'
      begin
        if EquipmentRules.is_weapon?(self)
          props = EquipmentRules.weapon_props(self) || {}
          is_light = !!props[:light]
          # permitir não-leve se explicitamente habilitado nos props_json (porta de entrada para façanhas/estilos)
          allow_override = !!(props_json || {})['allow_offhand_non_light']
          # ou se o personagem possuir façanha "Dual Wielder"/"Empunhador Duplo"
          allow_override ||= has_dual_wielder_feat?
          unless is_light || allow_override
            errors.add(:base, 'A arma da mão secundária deve ser leve')
          end
        end
      rescue NameError
        # sem EquipmentRules, não valida
      end
    end
  rescue NameError
    # EquipmentRules não disponível: não valida
  end

  def armor_like?
    key = (item_index || item_name || '').to_s.downcase
    idx = key.strip.gsub(' ', '-').gsub(/ç/,'c').gsub(/á|à|ã|â/,'a').gsub(/é|ê/,'e').gsub(/í/,'i').gsub(/ó|ô|õ/,'o').gsub(/ú/,'u')
    EquipmentRules::ARMOR_TABLE.key?(idx) rescue false
  end

  # Match por:
  #   1) `api_index` canônico (`mestre_de_armas_duplas` no DB; `dual_wielder` em
  #      payloads vindos do front/SRD).
  #   2) substring do nome (PT-BR oficial + variantes históricas).
  # Bug histórico: a checagem só por substring `'duas armas'` não cobria
  # o nome canônico `'Mestre de Armas Duplas'` — usuário com a façanha
  # ficava bloqueado de equipar arma não-leve na mão secundária.
  DUAL_WIELDER_NAME_PATTERNS = [
    'mestre de armas duplas',  # PT-BR oficial (config/feats_improved.yml)
    'dual wielder',            # SRD EN
    'empunhador duplo',        # tradução alternativa
    'duas armas',              # match histórico
    'duelista duplo',          # tradução alternativa
  ].freeze
  DUAL_WIELDER_API_INDEXES = %w[mestre_de_armas_duplas dual_wielder].freeze

  def has_dual_wielder_feat?
    begin
      api_indexes = []
      names = []
      begin
        Array(sheet.feats).each do |f|
          api_indexes << f.api_index.to_s.downcase if f.respond_to?(:api_index) && f.api_index.present?
          names << f.name.to_s.downcase if f.respond_to?(:name) && f.name.present?
        end
      rescue; end
      begin
        feats_meta = Array((sheet.metadata || {})['feats'])
        feats_meta.each do |f|
          api_indexes << (f['api_index'] || f[:api_index]).to_s.downcase
          names << (f['name'] || f[:name]).to_s.downcase
        end
      rescue; end
      api_indexes.compact.any? { |idx| DUAL_WIELDER_API_INDEXES.include?(idx) } ||
        names.compact.any? { |n| DUAL_WIELDER_NAME_PATTERNS.any? { |pat| n.include?(pat) } }
    rescue
      false
    end
  end

  # Garante que apenas um item ocupe cada slot por ficha e resolve conflitos simples
  def enforce_slot_exclusivity_and_conflicts
    return unless equipped && slot.present?
    # Desmarca outros itens no mesmo slot para esta ficha
    SheetItem.where(sheet_id: sheet_id).where.not(id: id).where(slot: slot).update_all(equipped: false, slot: nil)

    # Regras de conflito básicas entre slots
    begin
      # Se equipou escudo, desocupa mão secundária
      if slot.to_s == 'shield'
        SheetItem.where(sheet_id: sheet_id, equipped: true, slot: 'off_hand').update_all(equipped: false, slot: nil)
      end

      # Se equipou em off_hand, remove escudo
      if slot.to_s == 'off_hand'
        SheetItem.where(sheet_id: sheet_id, equipped: true, slot: 'shield').update_all(equipped: false, slot: nil)
      end

      # Se arma de 2 mãos na principal, remove off_hand e escudo
      if slot.to_s == 'main_hand' && EquipmentRules.is_weapon?(self)
        props = EquipmentRules.weapon_props(self) || {}
        using_two = (props_json || {})['using_two_hands'] ? true : false
        is_two_handed = (props[:hands].to_i == 2) || (props[:versatile] && using_two)
        if is_two_handed
          SheetItem.where(sheet_id: sheet_id, equipped: true, slot: ['off_hand','shield']).update_all(equipped: false, slot: nil)
        end
      end
    rescue NameError
      # EquipmentRules não disponível
    end
  end
end
