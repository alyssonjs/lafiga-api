class SubKlass < ApplicationRecord
  validates :name, :klass_id, presence: true
  validates :api_index, uniqueness: true, allow_blank: true

  belongs_to :klass
  has_many :sub_klass_levels, dependent: :destroy
  has_many :features, through: :sub_klass_levels
  has_many :sheet_klasses

  # Scopes para facilitar consultas
  scope :by_klass, ->(klass) { where(klass: klass) }
  scope :with_features, -> { includes(:features) }
  scope :with_levels, -> { includes(:sub_klass_levels) }

  # Métodos para verificar se subclasse tem spellcasting
  def has_spellcasting?
    features.any? { |f| f.name.match?(/conjuração|spellcasting/i) }
  end

  # Método para obter features por nível
  def features_at_level(level)
    level_record = sub_klass_levels.find_by(level: level)
    level_record ? level_record.features : []
  end

  # Método para verificar se subclasse é customizada (não do PHB)
  def custom_subclass?
    api_index.present? && !api_index.match?(/^(berserker|totem|lore|valor|fiend|great_old_one|celestial|life|light|nature|tempest|trickery|war|land|moon|spores|wild_magic|draconic|divine_soul|shadow_magic|storm_sorcery|champion|battle_master|eldritch_knight|assassin|thief|arcane_trickster|evocation|abjuration|conjuration|divination|enchantment|illusion|necromancy|transmutation|way_of_the_open_hand|way_of_shadow|way_of_the_four_elements|oath_of_devotion|oath_of_the_ancients|oath_of_vengeance|beast_master|hunter|gloom_stalker|horizon_walker|monster_slayer)$/)
  end
end
