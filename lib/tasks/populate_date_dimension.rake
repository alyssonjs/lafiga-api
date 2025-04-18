namespace :db do
  desc "Populate date dimension table (2 meses antes até 6 meses depois de hoje)"
  task populate_date_dimension: :environment do
    start_date = Date.today - 2.months
    end_date   = Date.today + 6.months

    (start_date..end_date).each do |current_date|
      attrs = {
        year:        current_date.year,
        month:       current_date.month,
        day:         current_date.day,
        day_of_week: current_date.wday,
        day_name:    current_date.strftime('%A'),
        is_weekend:  [0, 6].include?(current_date.wday),
        available:   true
      }

      # Garante unicidade por date
      date_dim = DateDimension.find_or_initialize_by(date: current_date)
      date_dim.assign_attributes(attrs)
      date_dim.save! if date_dim.changed?
    end

    puts "Date dimension table populated/updated from #{start_date} to #{end_date}!"
  end
end
