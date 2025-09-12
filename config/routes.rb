Rails.application.routes.draw do

  resources :users, only: [:show, :update, :index, :create], param: :_username
  post '/authenticate', to: 'authentication#login'
  post '/auth/logout', to: 'authentication#logout'
  post '/auth/signup', to: 'authentication#signup'

  namespace :api do
    namespace :v1 do
      namespace :admin do
        resources :users, only: [:index, :show, :update]
        resources :characters, only: [:index, :show, :create, :update, :destroy]
        resources :groups, only: [:index, :show, :create, :update, :destroy]
        resources :schedules, only: [:index, :show, :create, :update, :destroy]
        resources :races, only: [:index, :show, :create, :update, :destroy]
        resources :sub_races, only: [:index, :show, :create, :update, :destroy]
        resources :klasses, only: [:index, :show, :create, :update, :destroy]
        resources :sub_klasses, only: [:index, :show, :create, :update, :destroy]
        resources :sheets, only: [:index, :show, :create, :update, :destroy]
        resources :sheet_klasses, only: [:index, :show, :create, :update, :destroy]
        resources :roles, only: [:index]
        resources :date_dimensions, only: [:index, :update]
      end

      namespace :player do
        resources :characters, only: [:index, :show, :create, :update, :destroy]
        resources :schedules, only: [:index, :show, :create, :update, :destroy]
        resources :schedule_characters, only: [:index, :show, :update]
        resources :groups, only: [:index, :show]
        resources :sheets, only: [:index, :show, :create, :update, :destroy] do
          member do
            get :summary
            post :assign_background
            post :assign_feat
          end
          collection do
            get :available_feats
          end
        end
        resources :sheet_klasses, only: [:index, :show, :create, :update, :destroy]
        resources :sheet_known_spells, only: [:index, :create, :destroy]
        resources :sheet_prepared_spells, only: [:index, :create, :destroy]
        resources :characters_features, only: [:index, :update]
      end

      namespace :public do
        resources :characters, only: [:index, :show]
        resources :groups, only: [:index, :show]
        resources :schedules, only: [:index, :show]
        resources :races, only: [:index, :show]
        resources :sub_races, only: [:index, :show]
        resources :klasses, only: [:index, :show]
        get 'klasses/:id/levels', to: 'klasses#levels'
        resources :sub_klasses, only: [:index, :show]
        get 'sub_klasses/:id/levels', to: 'sub_klasses#levels'
        resources :spells, only: [:index, :show]
        resources :race_rules, only: [:index, :show]
        resources :traits, only: [:index]
        post 'race_rules/apply', to: 'race_rules#apply'
        resources :class_rules, only: [:index, :show]
        post 'class_rules/apply', to: 'class_rules#apply'
        resources :backgrounds, only: [:index, :show]
        post 'backgrounds/apply', to: 'backgrounds#apply'
        resources :alignments, only: [:index, :show]
        get 'equipment_categories/:id', to: 'equipment_categories#show'
        get 'equipment/:id', to: 'equipment#show'
        get 'weapon_properties/:id', to: 'equipment#weapon_properties'
        resources :date_dimensions, only: [:index]
      end
    end
  end


  get '/*a', to: 'application#not_found'
end
