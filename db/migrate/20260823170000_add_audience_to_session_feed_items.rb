class AddAudienceToSessionFeedItems < ActiveRecord::Migration[6.0]
  # Canal da mensagem no feed da sessão.
  #
  # `all` = o chat Geral de sempre (Mestre incluído). `players` = o chat da
  # EQUIPE, que o Mestre não pode ler nem escrever — é onde a mesa combina o
  # plano sem ele.
  #
  # Coluna e não uma chave dentro de `payload` porque a leitura FILTRA por ela:
  # o filtro tem de ser SQL, no servidor. Esconder no cliente não esconde nada.
  def change
    add_column :session_feed_items, :audience, :string, null: false, default: 'all'
    add_index :session_feed_items, %i[schedule_id audience posted_at],
              order: { posted_at: :desc },
              name: 'index_session_feed_items_on_schedule_audience_posted_at'
  end
end
