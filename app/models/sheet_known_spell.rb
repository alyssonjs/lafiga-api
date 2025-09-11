class SheetKnownSpell < ApplicationRecord
  self.table_name = 'sheet_known_spells'
  belongs_to :sheet_klass
  belongs_to :spell
end

