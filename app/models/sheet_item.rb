class SheetItem < ApplicationRecord
  belongs_to :sheet

  validates :sheet_id, presence: true
  validates :item_name, presence: true
  validates :quantity, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate  :validate_equipment_proficiency

  before_save :sanitize_slot
  after_save  :enforce_slot_exclusivity_and_conflicts

  private

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

  def has_dual_wielder_feat?
    # checa feats via associação e via metadata
    begin
      names = []
      begin
        names += Array(sheet.feats).map { |f| f.name.to_s.downcase }
      rescue; end
      begin
        feats_meta = Array((sheet.metadata || {})['feats'])
        names += feats_meta.map { |f| (f['name'] || f[:name]).to_s.downcase }
      rescue; end
      names.any? do |n|
        n.include?('dual wielder') || n.include?('empunhador duplo') || n.include?('duas armas') || n.include?('duelista duplo')
      end
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
