Rails.application.routes.draw do

  resources :users, only: [:show, :update, :index, :create], param: :_username
  post '/authenticate', to: 'authentication#login'
  post '/auth/logout', to: 'authentication#logout'

  namespace :api do
    namespace :v1 do
      namespace :admin do
        resources :characters, only: [:index, :show, :create, :update, :destroy]
      end

      namespace :public do
        resources :characters, only: [:index, :show]
        resources :groups, only: [:index, :show]
        resources :schedules, only: [:index, :show]
      end
      
      namespace :player do
        resources :characters, only: [:index, :show, :create, :update, :destroy]
        resources :groups, only: [:index, :show, :create, :update, :destroy]
        resources :schedules, only: [:index, :show, :create, :update, :destroy]
      end
    end
  end


  get '/*a', to: 'application#not_found'
end
