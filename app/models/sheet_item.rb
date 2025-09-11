class SheetItem < ApplicationRecord
  belongs_to :sheet

  validates :sheet_id, presence: true
  validates :item_name, presence: true
  validates :quantity, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate  :validate_equipment_proficiency

  before_save :sanitize_slot

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
  rescue NameError
    # EquipmentRules não disponível: não valida
  end

  def armor_like?
    key = (item_index || item_name || '').to_s.downcase
    idx = key.strip.gsub(' ', '-').gsub(/ç/,'c').gsub(/á|à|ã|â/,'a').gsub(/é|ê/,'e').gsub(/í/,'i').gsub(/ó|ô|õ/,'o').gsub(/ú/,'u')
    EquipmentRules::ARMOR_TABLE.key?(idx) rescue false
  end
end
