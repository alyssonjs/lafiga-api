#!/usr/bin/env ruby
# frozen_string_literal: true

# Monta config/dnd_translations.features.pt.yml a partir de:
# - dnd_translations.todo.yml (inglês fonte)
# - config/dnd_translations.pt_bodies_by_md5.json  (md5 do corpo EN -> texto PT)
# - config/dnd_translations.pt_titles_by_md5.json (md5 do título EN -> título PT)
#
# Uso: ruby api/scripts/build_dnd_features_pt.rb

require 'digest'
require 'json'
require 'yaml'

ROOT = File.expand_path('..', __dir__)
CONFIG = File.join(ROOT, 'config')
TODO = File.join(CONFIG, 'dnd_translations.todo.yml')
BODIES_PT = File.join(CONFIG, 'dnd_translations.pt_bodies_by_md5.json')
TITLES_PT = File.join(CONFIG, 'dnd_translations.pt_titles_by_md5.json')
OUT = File.join(CONFIG, 'dnd_translations.features.pt.yml')

def load_md5_json(path)
  return {} unless File.exist?(path)

  raw = JSON.parse(File.read(path))
  raw.transform_keys(&:to_s).transform_values { |v| v.to_s }
end

body_pt = load_md5_json(BODIES_PT)
title_pt = load_md5_json(TITLES_PT)

todo = YAML.load_file(TODO) || {}
fd_en = (todo['feature_descs'] || {}).transform_keys(&:to_s)
ft_en = (todo['features'] || {}).transform_keys(&:to_s)

missing_bodies = []
feature_descs = {}
fd_en.each do |key, en_val|
  canon = en_val.to_s.strip
  d = Digest::MD5.hexdigest(canon)
  pt = body_pt[d]
  pt = pt&.strip
  if pt.nil? || pt.empty?
    missing_bodies << key
    next
  end
  feature_descs[key] = pt
end

missing_titles = []
features = {}
ft_en.each do |key, en_title|
  canon = en_title.to_s.strip
  d = Digest::MD5.hexdigest(canon)
  pt = title_pt[d]
  pt = pt&.strip
  if pt.nil? || pt.empty?
    missing_titles << key
    next
  end
  features[key] = pt
end

data = {
  'features' => features.sort.to_h,
  'feature_descs' => feature_descs.sort.to_h,
}
yaml = data.to_yaml(line_width: -1)
File.write(OUT, "# Gerado por scripts/build_dnd_features_pt.rb — edite os JSON *_by_md5 e rode o script.\n#{yaml}")

warn "[build_dnd_features_pt] feature_descs: #{feature_descs.size}/#{fd_en.size} (faltam #{missing_bodies.size})"
warn "[build_dnd_features_pt] features: #{features.size}/#{ft_en.size} (faltam #{missing_titles.size})"
if missing_bodies.any?
  warn 'Chaves feature_descs sem PT (primeiras 25):'
  missing_bodies.take(25).each { |k| warn "  - #{k}" }
end
if missing_titles.any?
  warn 'Chaves features sem PT (primeiras 25):'
  missing_titles.take(25).each { |k| warn "  - #{k}" }
end

exit(missing_bodies.empty? && missing_titles.empty? ? 0 : 2)
