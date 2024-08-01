every '0 0 1 * *' do
  rake "db:populate_date_dimension"
end