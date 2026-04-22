class SkillsCatalog
  CACHE_KEY = 'skills_catalog_v1'.freeze
  YAML_PATH = Rails.root.join('config', 'skills.yml')
  CACHE_TTL = 24.hours

  def self.all
    load_skills
  end

  def self.find(id)
    return nil if id.blank?
    skills = load_skills
    skills.find { |s| s[:id] == id.to_s || s[:name].downcase == id.to_s.downcase }
  end

  # Retorna um hash { id => name } para tradução rápida
  def self.id_to_name_map
    load_skills.each_with_object({}) { |s, h| h[s[:id]] = s[:name] }
  end

  # Retorna um hash { name => id } para lookup reverso
  def self.name_to_id_map
    load_skills.each_with_object({}) { |s, h| h[s[:name]] = s[:id] }
  end

  def self.reload!
    Rails.cache.delete(CACHE_KEY)
    load_skills
  end

  private

  def self.load_skills
    Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) do
      return [] unless YAML_PATH.exist?

      raw = YAML.safe_load(YAML_PATH.read, aliases: true) || {}
      raw = raw.deep_symbolize_keys
      skills = raw[:skills] || []
      skills.map { |s| s.slice(:id, :name, :ability) }
    rescue => e
      Rails.logger.warn("SkillsCatalog: falha ao carregar #{YAML_PATH}: #{e.message}") if defined?(Rails.logger)
      []
    end
  end
end

