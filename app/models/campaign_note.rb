# Diário compartilhado da campanha. Vive por grupo e pode (opcionalmente) ser
# vinculado a uma sessão específica para mostrar "esta nota nasceu na sessão X".
#
# `kind` categoriza o conteúdo para filtros e ícones na UI:
#   - note      : nota livre (default)
#   - recap     : resumo/recapitulação rápida
#   - lore      : informação de mundo descoberta
#   - npc       : ficha curta de NPC
#   - location  : descrição de local
#   - quest     : ponta solta / missão a perseguir
#
# `visibility`:
#   - group     : todos do grupo veem
#   - dm_only   : só o DM/admin (nota privada do mestre)
class CampaignNote < ApplicationRecord
  enum kind: { note: 0, recap: 1, lore: 2, npc: 3, location: 4, quest: 5 }
  enum visibility: { group: 0, dm_only: 1 }, _prefix: :visibility

  belongs_to :group
  belongs_to :schedule, optional: true
  belongs_to :user

  validates :body,  length: { maximum: 5_000 }
  validates :title, length: { maximum: 200 }

  scope :recent_first, -> { order(updated_at: :desc) }
  scope :pinned_first, -> { order(pinned: :desc, updated_at: :desc) }
  scope :visible_to,   ->(user) {
    if Group.user_is_dm?(user)
      all
    else
      where(visibility: visibilities[:group])
        .or(where(user_id: user&.id))
    end
  }

  def as_journal_json
    {
      id: id,
      title: title,
      body: body,
      kind: kind,
      visibility: visibility,
      pinned: pinned,
      group_id: group_id,
      schedule_id: schedule_id,
      author: user ? { id: user.id, username: user.username } : nil,
      created_at: created_at,
      updated_at: updated_at,
    }
  end
end
