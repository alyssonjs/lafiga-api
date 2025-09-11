class SheetPreparedSpell < ApplicationRecord
  self.table_name = 'sheet_prepared_spells'
  belongs_to :sheet
  belongs_to :spell
end

