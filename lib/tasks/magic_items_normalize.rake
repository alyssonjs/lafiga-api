# frozen_string_literal: true

namespace :magic_items do
  desc "Reaplica validação/normalização (raridade, categoria, tag 'magico') em todos os registos"
  task normalize_all: :environment do
    n = 0
    err = 0
    MagicItem.find_each do |m|
      m.save!
      n += 1
    rescue StandardError => e
      err += 1
      warn "[magic_items:normalize_all] #{m.slug}: #{e.message}"
    end
    puts "Atualizados #{n} magic items, #{err} erros."
  end
end
