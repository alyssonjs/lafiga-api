class CharacterCreationService
  prepend SimpleCommand

  # Params esperados (hash):
  # - character: Character (instância já criada) OU :character_id
  # - race_id, sub_race_id (opcional)
  # - klass_id (classe inicial)
  # - abilities: { str:, dex:, con:, int:, wis:, cha: }
  def initialize(params)
    @character = params[:character] || Character.find(params[:character_id])
    @race_id = params[:race_id]
    @sub_race_id = params[:sub_race_id]
    @klass = Klass.find(params[:klass_id])
    @abilities = params[:abilities] || {}
    @background_key = params[:background_key]
    @background_choices = params[:background_choices] || {}
  end

  def call
    ActiveRecord::Base.transaction do
      sheet = Sheet.create!(
        character_id: @character.id,
        race_id: @race_id,
        sub_race_id: @sub_race_id,
        str: @abilities[:str], dex: @abilities[:dex], con: @abilities[:con],
        int: @abilities[:int], wis: @abilities[:wis], cha: @abilities[:cha]
      )

      # Classe inicial nível 1
      SheetKlass.create!(sheet: sheet, klass: @klass, level: 1)
      # Conceder features de nível 1 (classe e possivelmente subclasse se choose_level == 1)
      FeatureGrantService.call(sheet: sheet, klass: @klass, from_level: 0, to_level: 1)

      # HP inicial = DV máximo + mod CON
      con_mod = CharacterRules.modifier(sheet.con)
      hit_die = @klass.hit_die.to_i.nonzero? || 8
      sheet.update!(hp_max: hit_die + con_mod, hp_current: hit_die + con_mod, temp_hp: 0)

      # Opcional: associar background à ficha (metadata)
      if @background_key.present?
        begin
          BackgroundAssignmentService.call(sheet: sheet, key: @background_key, choices: @background_choices)
        rescue NameError
          # serviço não disponível; ignora silenciosamente
        end
      end

      sheet
    end
  end
end
