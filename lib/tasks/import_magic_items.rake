namespace :magic_items do
  desc 'Import magic items from YAML at api/config/magic_items.yml'
  task import: :environment do
    path = Rails.root.join('config','magic_items.yml')
    unless File.exist?(path)
      puts "YAML not found at #{path}"
      next
    end
    data = YAML.load_file(path) || []
    imported = 0
    data.each do |row|
      begin
        attrs = symbolize_keys_deep(row)
        name = attrs[:name] || next
        slug = attrs[:slug].presence || I18n.transliterate(name.to_s).downcase.strip.gsub(/[^a-z0-9\-\s]/,'').gsub(/\s+/,'-').gsub(/-+/,'-')
        item = MagicItem.find_or_initialize_by(slug: slug)
        item.name = name
        item.rarity = attrs[:rarity]
        item.category = attrs[:category]
        item.sub_category = attrs[:sub_category]
        item.requires_attunement = !!attrs[:requires_attunement]
        item.attunement_note = attrs[:attunement_note]
        item.weight_kg = to_kg(attrs[:weight])
        item.value_gp = attrs[:value_gp]
        item.source = attrs[:source]
        item.cursed = !!attrs[:cursed]
        item.curse_text = attrs[:curse_text]
        item.charges = attrs[:charges]
        item.recharge = attrs[:recharge]
        item.bonuses = (attrs[:bonuses] || {})
        item.properties = (attrs[:properties] || {})
        # Effects is an array of JSON objects describing rules (see .cursor/regras_itens_magicos.txt)
        if item.respond_to?(:effects=)
          item.effects = Array(attrs[:effects])
        elsif attrs[:effects].present?
          puts "[warn] effects column missing; skipping effects for #{name} (run db:migrate)"
        end
        item.description = attrs[:description]
        item.tags = Array(attrs[:tags]).map(&:to_s)
        item.save!
        imported += 1
      rescue => e
        puts "Failed to import #{row.inspect}: #{e.message}"
      end
    end
    puts "Imported #{imported} magic items"
  end

  def symbolize_keys_deep(obj)
    case obj
    when Hash
      obj.each_with_object({}) { |(k,v),h| h[k.to_sym] = symbolize_keys_deep(v) }
    when Array
      obj.map { |v| symbolize_keys_deep(v) }
    else
      obj
    end
  end

  def to_kg(val)
    return nil if val.nil?
    return val.to_f if val.is_a?(Numeric)
    s = val.to_s
    if (m = s.match(/([0-9]+(?:\.[0-9]+)?)\s*kg/i))
      return m[1].to_f
    elsif (m = s.match(/([0-9]+(?:\.[0-9]+)?)\s*lb/i))
      return (m[1].to_f * 0.45359237)
    else
      return s.to_f
    end
  end
end
