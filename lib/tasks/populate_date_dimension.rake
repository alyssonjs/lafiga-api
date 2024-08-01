namespace :db do
  desc "Populate date dimension table"
  task populate_date_dimension: :environment do
    start_date = Date.today
    end_date = start_date + 6.month

    current_date = start_date
    while current_date <= end_date
      date_attributes = {
        date: current_date,
        year: current_date.year,
        month: current_date.month,
        day: current_date.day,
        day_of_week: current_date.wday,
        day_name: current_date.strftime('%A'),
        is_weekend: [0, 6].include?(current_date.wday)
      }

      DateDimension.create(date_attributes)

      current_date += 1.day
    end

    puts "Date dimension table populated successfully!"
  end
end