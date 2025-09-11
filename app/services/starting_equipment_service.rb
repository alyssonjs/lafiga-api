class StartingEquipmentService
  prepend SimpleCommand

  # Params:
  # - sheet: Sheet
  # - items: [ { item_index:, item_name:, category:, quantity:, equipped:, slot:, source:, props_json: {} }, ... ]
  def initialize(sheet:, items: [])
    @sheet = sheet
    @items = Array(items)
  end

  def call
    created = []
    ActiveRecord::Base.transaction do
      @items.each do |it|
        next if it.blank?
        created << SheetItem.create!(
          sheet_id: @sheet.id,
          item_index: it[:item_index] || it['item_index'],
          item_name: it[:item_name] || it['item_name'] || it[:name] || it['name'] || 'Item',
          category: it[:category] || it['category'],
          quantity: (it[:quantity] || it['quantity'] || 1).to_i,
          equipped: (it[:equipped] || it['equipped']) ? true : false,
          slot: it[:slot] || it['slot'],
          source: it[:source] || it['source'] || 'class',
          props_json: it[:props_json] || it['props_json'] || it[:props] || it['props'] || {}
        )
      end
    end
    created
  rescue => e
    errors.add(:base, e.message)
    nil
  end
end

