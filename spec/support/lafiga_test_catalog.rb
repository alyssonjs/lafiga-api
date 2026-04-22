# frozen_string_literal: true

# Registros estáveis (api_index único) para specs de contrato — evita violação de unique index.
module LafigaTestCatalog
  module_function

  def human_race
    Race.find_or_create_by!(api_index: 'human') { |r| r.name = 'Humano' }
  end

  def human_standard_subrace(race = human_race)
    SubRace.find_or_create_by!(race_id: race.id, api_index: 'standard') { |s| s.name = 'Humano Padrão' }
  end

  def barbarian_klass
    Klass.find_or_create_by!(api_index: 'barbarian') do |k|
      k.name = 'Bárbaro'
      k.hit_die = 12
      k.subclass_level = 3
    end
  end

  def acolyte_background
    Background.find_or_create_by!(api_index: 'acolyte') do |b|
      b.name = 'Acólito'
      b.feature_name = 'Abrigo dos Fiéis'
      b.feature_desc = 'E2E'
    end
  end

  def lawful_good_alignment
    Alignment.find_or_create_by!(api_index: 'lg') { |a| a.name = 'Leal e Bom' }
  end

  # Phase 3.1 — para regressão do bug "escola-de-evocacao" do
  # SubklassSlugResolver. Antes existia alias 'escola-de-evocacao' => 'evocation'
  # mas 'evocation' não estava no DB, quebrando o LevelUpService L2+.
  def wizard_klass
    Klass.find_or_create_by!(api_index: 'wizard') do |k|
      k.name = 'Mago'
      k.hit_die = 6
      k.subclass_level = 2
    end
  end

  def wizard_evocation_subklass(klass = wizard_klass)
    SubKlass.find_or_create_by!(klass_id: klass.id, api_index: 'escola-de-evocacao') do |s|
      s.name = 'Escola de Evocação'
    end
  end

  # Phase 4 — para regressão dos 4 aliases quebrados encontrados.
  def paladin_klass
    Klass.find_or_create_by!(api_index: 'paladin') do |k|
      k.name = 'Paladino'
      k.hit_die = 10
      k.subclass_level = 3
    end
  end

  def paladin_devotion_subklass(klass = paladin_klass)
    SubKlass.find_or_create_by!(klass_id: klass.id, api_index: 'devotion') do |s|
      s.name = 'Juramento de Devoção'
    end
  end

  def barbarian_berserker_subklass(klass = barbarian_klass)
    SubKlass.find_or_create_by!(klass_id: klass.id, api_index: 'berserker') do |s|
      s.name = 'Caminho do Furioso'
    end
  end

  # Phase 5 — para roundtrip de edição (troca de subclasse)
  def paladin_ancients_subklass(klass = paladin_klass)
    SubKlass.find_or_create_by!(klass_id: klass.id, api_index: 'ancients') do |s|
      s.name = 'Juramento dos Anciões'
    end
  end
end

RSpec.configure do |config|
  config.include LafigaTestCatalog, type: :request
end
