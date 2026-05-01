every '0 0 1 * *' do
  rake "db:populate_date_dimension"
end

# Retenção do feed da sessão: deleta items >1 mês que NÃO estão entre os
# últimos 1000 do schedule, e pendings órfãos >5min.
# Veja app/services/session_feed/retention.rb.
every 1.day, at: '3:30 am' do
  runner "SessionFeed::Retention.run_all"
end