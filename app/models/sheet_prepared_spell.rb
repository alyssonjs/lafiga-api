class SheetPreparedSpell < ApplicationRecord
  self.table_name = 'sheet_prepared_spells'
  belongs_to :sheet
  belongs_to :spell

  before_validation :normalize_auto_flag

  private

  def normalize_auto_flag
    self.auto = false if auto.nil?
  end
end

