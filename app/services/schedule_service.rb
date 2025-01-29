class ScheduleService
  prepend SimpleCommand

  def initialize(schedule_params)
    @schedule_params = schedule_params
  end

  def call
    create_schedule
  end

  private
  
  def create_schedule    
    ActiveRecord::Base.transaction do
      schedule = Schedule.new(@schedule_params)
      schedule.save!

      characters = schedule.group.characters

      characters.each do |character|
        ScheduleCharacter.create!(character_id: character.id, schedule_id: schedule.id)
      end 
      schedule
    end
  rescue ActiveRecord::Rollback => e
    raise StandardError.new, e.message
  rescue StandardError => e
    raise StandardError.new, e.message
  end
end
