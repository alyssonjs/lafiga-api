## BattleMapTemplatesCatalog
##
## Carrega `config/battle_map_templates.yml` e devolve os blueprints como
## hashes JSON-friendly. Usado pelo BattleMapTemplatesController.
##
## Memoizado em prod (singleton de array). Em dev/teste recarrega quando
## RAILS_ENV != 'production' OU quando `Rails.application.config.cache_classes`
## e false — assim alteracoes no YAML aparecem sem reboot.
class BattleMapTemplatesCatalog
  CONFIG_PATH = Rails.root.join('config', 'battle_map_templates.yml').freeze

  class << self
    def all
      cache_enabled? ? (@templates ||= load_templates) : load_templates
    end

    def find(slug)
      all.find { |t| t['slug'] == slug.to_s }
    end

    def reset!
      @templates = nil
    end

    # Aplica os patches do template e devolve a matriz `cells` final.
    def materialize_cells(template)
      width = template['width'].to_i
      height = template['height'].to_i
      base = template['base_terrain'] || 'empty'
      cells = Array.new(height) { Array.new(width, base) }
      Array(template['patches']).each do |patch|
        x = patch['x'].to_i
        y = patch['y'].to_i
        w = patch['w'].to_i
        h = patch['h'].to_i
        terrain = patch['terrain'] || base
        (y...(y + h)).each do |row|
          next if row.negative? || row >= height
          (x...(x + w)).each do |col|
            next if col.negative? || col >= width
            cells[row][col] = terrain
          end
        end
      end
      cells
    end

    private

    def cache_enabled?
      Rails.env.production?
    end

    def load_templates
      raw = YAML.safe_load_file(CONFIG_PATH, permitted_classes: [Symbol], aliases: true) || {}
      Array(raw['templates']).map(&:freeze).freeze
    rescue Errno::ENOENT
      []
    end
  end
end
