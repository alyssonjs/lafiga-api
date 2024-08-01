class DateDimension < ApplicationRecord

    def self.current_date
      today = Date.today
      find_by(year: today.year, month: today.month, day: today.day)
    end
    
    def self.current_week
      today = Date.today
      start_of_week = today.beginning_of_week
      end_of_week = today.end_of_week
      where('date >= ? AND date <= ?', start_of_week, end_of_week)
    end
  
    def self.current_month
      today = Date.today
      where(year: today.year, month: today.month)
    end
    
    def self.next_day(date)
      where('date > ?', date).order(date: :asc).first
    end
    
    def self.next_week(date)
      start_of_week = date.end_of_week + 1.day
      end_of_week = start_of_week.end_of_week
      where('date >= ? AND date <= ?', start_of_week, end_of_week)
    end
    
    def self.previous_day(date)
      where('date < ?', date).order(date: :desc).first
    end
    
    def self.previous_week(date)
      end_of_week = date.beginning_of_week - 1.day
      start_of_week = end_of_week.beginning_of_week
      where('date >= ? AND date <= ?', start_of_week, end_of_week)
    end
end
  