namespace :magic_items do
  desc 'Import magic items from AideDD (filters page). Options: URL=..., FILE=..., LIMIT=100, DRY=1, FETCH_DETAIL=1, OVERWRITE=0, DELAY_MS=200'
  task import_aidedd: :environment do
    require 'nokogiri'
    require 'net/http'
    require 'uri'

    url = ENV['URL'] || 'https://www.aidedd.org/dnd-filters/magic-items.php'
    file = ENV['FILE']
    limit = (ENV['LIMIT'] || '0').to_i
    dry = !!ENV['DRY']
    fetch_detail = ENV.key?('FETCH_DETAIL') ? ENV['FETCH_DETAIL'].to_s != '0' : true
    overwrite = ENV['OVERWRITE'].to_s == '1'
    delay_ms = (ENV['DELAY_MS'] || '200').to_i

    doc = nil
    if file && File.exist?(file)
      puts "Reading local HTML file: #{file}"
      html = File.read(file)
      doc = Nokogiri::HTML(html)
    else
      puts "Fetching index: #{url}"
      doc = fetch_html(url)
    end

    rows = extract_rows(doc)
    if rows.empty?
      puts '[warn] No item rows found. Consider providing FILE=/path/to/page.html'
      next
    end
    puts "Found #{rows.length} candidate rows"

    processed = 0
    imported = 0
    rows.each do |row|
      break if limit > 0 && processed >= limit
      processed += 1

      link = (row.at_css('a') || {})
      name = link.text.to_s.strip
      href = link['href'] rescue nil
      next if name.empty?

      row_text = row.text.to_s.strip

      rarity = detect_rarity(row_text)
      category = detect_category(row_text)
      attn = detect_attunement(row_text)
      attn_note = detect_attunement_note(row_text)

      slug = to_slug(name)
      item = MagicItem.find_or_initialize_by(slug: slug)
      if item.persisted? && !overwrite
        puts "[skip] #{name} (exists)"
        next
      end

      item.name = name
      item.rarity = rarity
      item.category = category
      item.requires_attunement = attn
      item.attunement_note = attn_note
      item.source = 'AideDD'
      item.tags = [category, rarity].compact.map(&:to_s)

      if fetch_detail && href.present?
        begin
          item_url = absolutize(url, href)
          sleep(delay_ms / 1000.0) if delay_ms > 0
          ddoc = fetch_html(item_url)
          desc = extract_description(ddoc)
          item.description = desc if desc.present?
        rescue => e
          puts "[warn] detail fetch failed for #{name}: #{e.message}"
        end
      end

      if dry
        puts "[dry] #{name} → rarity=#{rarity} category=#{category} attunement=#{attn}"
      else
        begin
          item.save!
          imported += 1
          puts "[ok] #{name}"
        rescue => e
          puts "[fail] #{name}: #{e.message}"
        end
      end
    end

    puts "Imported #{imported} items (processed #{processed})"
  end

  def fetch_html(url)
    uri = URI(url)
    resp = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', read_timeout: 10, open_timeout: 5) do |http|
      req = Net::HTTP::Get.new(uri)
      req['User-Agent'] = 'lafiga-magic-items-importer/1.0'
      http.request(req)
    end
    raise "HTTP #{resp.code}" unless resp.is_a?(Net::HTTPSuccess)
    Nokogiri::HTML(resp.body)
  end

  def extract_rows(doc)
    # Try common structures: table with items
    cands = []
    cands += doc.css('table tbody tr')
    cands = doc.css('table tr') if cands.empty?
    # Fallback: list items with anchors inside main content
    if cands.empty?
      cands = doc.css('a').map { |a| a.ancestors('tr').first }.compact.uniq
    end
    # Keep rows that have a link and some td
    cands.select { |tr| tr.at_css('a') && tr.css('td,th').length > 1 }
  end

  def detect_rarity(text)
    t = text.downcase
    return 'artifact' if t.include?('artifact')
    return 'legendary' if t.include?('legendary')
    return 'very rare' if t.include?('very rare')
    return 'rare' if t.include?('rare')
    return 'uncommon' if t.include?('uncommon')
    return 'common' if t.include?('common')
    nil
  end

  def detect_category(text)
    t = text.downcase
    return 'weapon' if t.include?('weapon')
    return 'armor' if t.include?('armor')
    return 'shield' if t.include?('shield')
    return 'ring' if t.include?('ring')
    return 'rod' if t.include?('rod')
    return 'staff' if t.include?('staff')
    return 'wand' if t.include?('wand')
    return 'potion' if t.include?('potion')
    return 'scroll' if t.include?('scroll')
    return 'wondrous item' if t.include?('wondrous') || t.include?('wondrous item')
    nil
  end

  def detect_attunement(text)
    text.to_s.downcase.include?('attunement')
  end

  def detect_attunement_note(text)
    t = text.to_s
    m = t.match(/attunement\s*\(([^\)]+)\)/i)
    m ? m[1].strip : nil
  end

  def extract_description(doc)
    # Try common content containers
    nodes = []
    nodes += doc.css('article p')
    nodes = doc.css('#content p') if nodes.empty?
    nodes = doc.css('main p') if nodes.empty?
    text = nodes.map { |p| p.text.to_s.strip }.reject(&:empty?).join("\n\n")
    text.strip
  end

  def absolutize(base, href)
    bu = URI(base)
    hu = URI(href)
    hu = bu.merge(hu) unless hu.absolute?
    hu.to_s
  end

  def to_slug(text)
    I18n.transliterate(text.to_s).downcase.strip.gsub(/[^a-z0-9\-\s]/,'').gsub(/\s+/,'-').gsub(/-+/,'-')
  end
end

