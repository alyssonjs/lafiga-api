Rails.application.routes.draw do

  resources :users, only: [:show, :update, :index, :create], param: :_username
  post '/authenticate', to: 'authentication#login'
  post '/auth/logout', to: 'authentication#logout'

  namespace :api do
    namespace :v1 do
      namespace :admin do
        resources :characters, only: [:index, :show, :create, :update, :destroy]
        resources :groups, only: [:index, :show, :create, :update, :destroy]
        resources :schedules, only: [:index, :show, :create, :update, :destroy]
        resources :races, only: [:index, :show, :create, :update, :destroy]
        resources :sub_races, only: [:index, :show, :create, :update, :destroy]
        resources :klasses, only: [:index, :show, :create, :update, :destroy]
        resources :sub_klasses, only: [:index, :show, :create, :update, :destroy]
      end

      namespace :player do
        resources :characters, only: [:index, :show, :create, :update, :destroy]
        resources :schedules, only: [:index, :show, :create, :update, :destroy]
        resources :groups, only: [:index, :show]
      end

      namespace :public do
        resources :characters, only: [:index, :show]
        resources :groups, only: [:index, :show]
        resources :schedules, only: [:index, :show]
        resources :races, only: [:index, :show]
        resources :sub_races, only: [:index, :show]
        resources :klasses, only: [:index, :show]
        resources :sub_klasses, only: [:index, :show]
      end
    end
  end


  get '/*a', to: 'application#not_found'
end
