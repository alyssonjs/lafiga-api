class Race < ApplicationRecord
  # ⚠️ O overlay de regras tem cache PRÓPRIO (12h). Sem esta invalidação, o
  # mestre gravava a raça e via o valor antigo — por até meio dia, e sem nada
  # na tela a dizer porquê. `saved_change_to_rules_json?` limita a purga a quem
  # de facto mexeu nas regras: mudar só o `playable` não derruba o cache.
  after_commit :invalidar_overlay_de_regras, if: :deve_invalidar_overlay?

  validates :name, presence: true
  validates :api_index, uniqueness: true, allow_nil: true

  has_many :sub_races, dependent: :destroy
  has_many :race_traits, dependent: :destroy
  has_many :traits, through: :race_traits

  # Traits where sub_race_id is NULL only (shared by all subraces of this race).
  # `traits` includes every subrace's rows via race_id alone — do not use for sheet summary.
  has_many :base_race_traits, -> { where(sub_race_id: nil) }, class_name: 'RaceTrait'
  has_many :base_traits, through: :base_race_traits, source: :trait

  private

  def deve_invalidar_overlay?
    respond_to?(:saved_change_to_rules_json?) && saved_change_to_rules_json?
  rescue StandardError
    false
  end

  def invalidar_overlay_de_regras
    RaceRules.reload_overlay! if defined?(RaceRules)
  end

end
