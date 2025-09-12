class Api::V1::Public::DateDimensionsController < ApplicationController
  def index
    year  = params.require(:year).to_i
    month = params.require(:month).to_i

    prev_month_date = Date.new(year, month, 1).prev_month
    next_month_date = Date.new(year, month, 1).next_month

    start_date = prev_month_date.beginning_of_month
    end_date   = next_month_date.end_of_month

    dates = DateDimension
              .where(date: start_date..end_date)
              .includes(schedule: :group, schedules: :group)   # pré-carrega schedule(s) e seu group
              .order(:date)

    render json: dates, include: {
      schedule: {
        include: { group: { include: :characters } },
        except: [:created_at, :updated_at]
      },
      schedules: {
        include: { group: { include: :characters } },
        except: [:created_at, :updated_at]
      }
    }, status: :ok
  end
end
