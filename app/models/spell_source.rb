class SpellSource < ApplicationRecord
  belongs_to :spell

  # Polymorphic-like reference without Rails polymorphism to keep it simple
  # source_type in ['Klass','SubKlass','Race','SubRace','Feature','Background']
end

