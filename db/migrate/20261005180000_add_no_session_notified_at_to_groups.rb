# frozen_string_literal: true

# A MESA SEM SESSÃO MARCADA avisa os jogadores (05/10, a mesa: "quando um grupo não tiver nenhuma sessão marcada nas
# próximas duas semanas, mande uma notificação com dias disponíveis"). A marca do último aviso mora no grupo: o lembrete
# se repete a cada 3 dias enquanto continuar sem sessão, e some assim que alguém marcar.
class AddNoSessionNotifiedAtToGroups < ActiveRecord::Migration[6.0]
  def change
    add_column :groups, :no_session_notified_at, :datetime
  end
end
