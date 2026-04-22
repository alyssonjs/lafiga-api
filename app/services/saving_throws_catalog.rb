class SavingThrowsCatalog
  CACHE_KEY = 'saving_throws_catalog_v1'.freeze
  YAML_PATH = Rails.root.join('config', 'saving_throws.yml')
  CACHE_TTL = 24.hours

  # Mapeamento direto para acesso rápido
  MAPPING = {
    'STR' => 'FOR',
    'DEX' => 'DES',
    'CON' => 'CON',
    'INT' => 'INT',
    'WIS' => 'SAB',
    'CHA' => 'CAR'
  }.freeze

  def self.all
    load_saving_throws
  end

  def self.translate(id)
    return nil if id.blank?
    MAPPING[id.to_s.upcase] || id.to_s
  end

  # Traduz um array de salvaguardas
  def self.translate_array(ids)
    return [] if ids.blank?
    Array(ids).map { |id| translate(id) }.compact
  end

  def self.reload!
    Rails.cache.delete(CACHE_KEY)
    load_saving_throws
  end

  private

  def self.load_saving_throws
    Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) do
      return [] unless YAML_PATH.exist?

      raw = YAML.safe_load(YAML_PATH.read, aliases: true) || {}
      raw = raw.deep_symbolize_keys
      saving_throws = raw[:saving_throws] || []
      saving_throws.map { |st| st.slice(:id, :name, :full_name, :ability) }
    rescue => e
      Rails.logger.warn("SavingThrowsCatalog: falha ao carregar #{YAML_PATH}: #{e.message}") if defined?(Rails.logger)
      []
    end
  end
end

