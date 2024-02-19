Rails.application.routes.draw do

  post '/authenticate', to: 'authentication#login'
  post '/auth/logout', to: 'authentication#logout'

  resources :users, only: [:show, :update, :index, :create], param: :_username 
  namespace :api do
    namespace :v1 do
    end
  end


  get '/*a', to: 'application#not_found'
end
