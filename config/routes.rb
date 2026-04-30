Rails.application.routes.draw do
  # Lightweight healthcheck used by Docker healthchecks, Caddy upstream probes,
  # and uptime monitors. Returns 200 with no DB hit. Touch DB at /up?db=1.
  get '/up', to: ->(env) {
    if env['QUERY_STRING'].to_s.include?('db=1')
      ActiveRecord::Base.connection.execute('SELECT 1')
    end
    [200, { 'Content-Type' => 'application/json' }, [%({"status":"ok"})]]
  }

  mount ActionCable.server => '/cable'

  resources :users, only: [:show, :update, :index, :create], param: :_username
  post '/authenticate', to: 'authentication#login'
  post '/auth/logout', to: 'authentication#logout'
  post '/auth/signup', to: 'authentication#signup'

  namespace :api do
    namespace :v1 do
      namespace :admin do
        get 'dm_user_picker', to: 'dm_user_picker#index'
        resources :dm_users, only: %i[index show create update] do
          member do
            post :reset_password
          end
        end
        resources :users, only: [:index, :show, :update]
        resource :dm_progression_settings, only: [:show, :update], controller: 'dm_progression_settings'
        resources :characters, only: [:index, :show, :create, :update, :destroy] do
          collection do
            post :provision
          end
          resource :dm_notes, only: [:show, :update], controller: 'character_dm_notes'
          resource :dm_level_unlock, only: [:create, :destroy], controller: 'character_dm_level_unlocks'
        end
        resources :groups, only: [:index, :show, :create, :update, :destroy] do
          member do
            post :add_character
            post :remove_character
          end
          resources :campaign_notes, only: [:index, :create]
        end
        resources :campaign_notes, only: [:show, :update, :destroy]
        resources :schedules, only: [:index, :show, :create, :update, :destroy]
        resources :magic_items, only: [:index, :show, :create, :update, :destroy] do
          collection do
            post :bulk_import
          end
        end
        get    'catalog_items/:api_index', to: 'catalog_items#show',    constraints: { api_index: %r{[^/]+} }
        match  'catalog_items/:api_index', to: 'catalog_items#update',  via: %i[put patch], constraints: { api_index: %r{[^/]+} }
        delete 'catalog_items/:api_index', to: 'catalog_items#destroy', constraints: { api_index: %r{[^/]+} }
        resources :monsters, only: [:index, :show, :create, :update, :destroy] do
          collection do
            post :bulk_import
          end
        end
        resources :feats, only: [:index, :show, :create, :update, :destroy]
        resources :spells, only: [:index, :show, :create, :update, :destroy]
        resources :sheet_items, only: [:index, :create, :update, :destroy] do
          member do
            post :equip
            post :unequip
          end
          collection do
            post :grant
          end
        end
        resources :races, only: [:index, :show, :create, :update, :destroy]
        resources :sub_races, only: [:index, :show, :create, :update, :destroy]
        resources :klasses, only: [:index, :show, :create, :update, :destroy] do
          member do
            post :level_features
            patch 'level_features/:feature_id', action: :update_level_feature
            delete 'level_features/:feature_id', action: :destroy_level_feature
          end
        end
        resources :sub_klasses, only: [:index, :show, :create, :update, :destroy] do
          member do
            post :level_features
            patch 'level_features/:feature_id', action: :update_level_feature
            delete 'level_features/:feature_id', action: :destroy_level_feature
          end
        end
        resources :backgrounds, only: [:index, :show, :create, :update, :destroy]
        resources :sheets, only: [:index, :show, :create, :update, :destroy] do
          member do
            get :summary
            get  :wallet, to: 'wallets#show'
            put  :wallet, to: 'wallets#update'
          end
          resources :coin_pouches, only: [:create, :update, :destroy]
        end
        resources :sheet_klasses, only: [:index, :show, :create, :update, :destroy]
        resources :roles, only: [:index]
        resources :date_dimensions, only: [:index, :update] do
          collection do
            post :set_availability_by_date
          end
        end
      end

      namespace :player do
        patch 'password', to: 'passwords#update'
        patch 'profile', to: 'profiles#update'
        resources :characters, only: [:index, :show, :create, :update, :destroy] do
          collection do
            post :provision
          end
          resources :diary_entries, only: [:index, :show, :create, :update, :destroy]
        end
        # Per-step draft endpoint (creation + surgical edit). See
        # api/app/controllers/api/v1/player/character_drafts_controller.rb.
        resources :character_drafts, only: [:show, :update] do
          member do
            post :provision
          end
        end
        resources :schedules, only: [:index, :show, :create, :update, :destroy] do
          member do
            post :start
            post :complete
            post :cancel
          end

          # Endpoints de combate em tempo real (Fase 1B). Aninhados sob
          # schedule porque combat_state é 1:1 com Schedule e todas as
          # entidades (combatants, npcs, logs) pertencem a uma sessão.
          # Authorization centralizada em Combat::BaseController.
          scope module: 'combat' do
            resource :combat_state, only: [:show], controller: 'combat_states' do
              post :begin
              post :finish
              post :advance_turn
              post :set_round
              put :update_movement_ledger
            end

            resources :combat_combatants, only: [:index, :create, :update, :destroy] do
              member do
                post :apply_damage
                post :heal
                post :record_death_save
              end
              collection do
                post :reorder
              end
            end

            resources :combat_npcs, only: [:index, :show, :create, :update, :destroy] do
              member do
                post :defeat
                post :revive
              end
            end

            resources :session_logs, only: [:index, :create]
          end
        end
        resources :schedule_characters, only: [:index, :show, :update]
        resources :groups, only: [:index, :show, :create, :update, :destroy] do
          member do
            get  :timeline
            get  :last_session
            post :add_character
            post :remove_character
          end
          resources :campaign_notes, only: [:index, :create]
        end
        resources :campaign_notes, only: [:show, :update, :destroy]
        resources :sheets, only: [:index, :show, :create, :update, :destroy] do
          member do
            get :summary
            post :assign_background
            post :assign_feat
            get  :wallet, to: 'wallets#show'
            put  :wallet, to: 'wallets#update'

            # Runtime state (Fase A): coexiste com hp_current/temp_hp em
            # sheets, mas trata tudo MENOS HP. Veja
            # api/app/controllers/api/v1/player/sheet_runtime_states_controller.rb
            get   :runtime,            to: 'sheet_runtime_states#show'
            patch :runtime,            to: 'sheet_runtime_states#update'
            post  'runtime/short_rest', to: 'sheet_runtime_states#short_rest'
            post  'runtime/long_rest',  to: 'sheet_runtime_states#long_rest'
          end
          collection do
            get :available_feats
          end
        end
        resources :sheet_klasses, only: [:index, :show, :create, :update, :destroy]
        resources :sheet_known_spells, only: [:index, :create, :destroy]
        resources :sheet_prepared_spells, only: [:index, :create, :destroy]
        resources :characters_features, only: [:index, :update]

        # Allow destroying a feat assigned to a sheet
        resources :sheet_feats, only: [:destroy]

        resources :sheet_items, only: [:index, :create, :update, :destroy] do
          member do
            post :equip
            post :unequip
          end
        end

        resources :channels, only: [:index, :create] do
          collection do
            post :direct
          end
          resources :channel_messages, path: 'messages', only: [:index, :create]
        end

        # BattleMap (Mapa Tatico) — persistencia server-first dos mapas usados
        # na sessao. Member: duplicate; Collection: import_legacy (one-shot
        # do localStorage para o backend); Member: move_token (endpoint hot
        # path para arrasto de token, evita PATCH do tokens inteiro).
        resources :battle_maps, only: [:index, :show, :create, :update, :destroy] do
          member do
            post :duplicate
            post :move_token
          end
          collection do
            post :import_legacy
          end
        end
        resources :battle_map_templates, only: [:index], param: :slug do
          member do
            post :instantiate
          end
        end
      end

      namespace :public do
        resources :characters, only: [:index, :show]
        resources :groups, only: [:index, :show]
        resources :schedules, only: [:index, :show]
        resources :races, only: [:index, :show]
        resources :sub_races, only: [:index, :show]
        resources :klasses, only: [:index, :show] do
          member do
            get :levels
            get :subclasses
          end
        end
        resources :sub_klasses, only: [:index, :show] do
          member do
            get :levels
            get :always_prepared_spells
          end
        end
        resources :spells, only: [:index, :show]
        resources :race_rules, only: [:index, :show]
        resources :traits, only: [:index]
        post 'race_rules/apply', to: 'race_rules#apply'
        resources :class_rules, only: [:index, :show]
        post 'class_rules/apply', to: 'class_rules#apply'
        # Kit 1.PoC: catálogos canônicos de escolhas de classe (YAML).
        # Ex.: GET /api/v1/public/class_choices/metamagic
        resources :class_choices, only: [:show], constraints: { id: /[a-z_][a-z0-9_]*/ }
        resources :magic_items, only: [:index, :show]
        resources :monsters, only: [:index, :show]
        resources :backgrounds, only: [:index, :show]
        post 'backgrounds/apply', to: 'backgrounds#apply'
        resources :alignments, only: [:index, :show]
        resources :feats, only: [:index, :show]
        resources :skills, only: [:index, :show]
        resources :saving_throws, only: [:index, :show]
        # Centralizar em EquipmentController
        get 'equipment_categories/:id', to: 'equipment#categories'
        get 'equipment/:id', to: 'equipment#show'
        get 'weapon_properties/:id', to: 'equipment#weapon_properties'
        get 'equipment_catalog_snapshot', to: 'equipment#equipment_catalog_snapshot'
        get 'equipment_list/:category', to: 'equipment#equipment_list'
        get 'equipment_profile', to: 'equipment#profile'
        get 'starting_equipment', to: 'equipment#starting_equipment'
        resources :date_dimensions, only: [:index]
      end
    end
  end


  get '/*a', to: 'application#not_found'
end
