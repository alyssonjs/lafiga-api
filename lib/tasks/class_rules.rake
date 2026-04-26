# frozen_string_literal: true

namespace :class_rules do
  desc 'Imprime JSON (formato klasses.rules) a partir de ClassRules::CLASS_RULES. Uso: bin/rails "class_rules:dump_sample[fighter]" (zsh: aspas obrigatorias).'
  task :dump_sample, [:api_index] => :environment do |_t, args|
    api = (args[:api_index].presence || 'fighter').to_sym
    rule = ClassRules::CLASS_RULES[api]
    unless rule
      $stderr.puts "class_rules:dump_sample — não há ClassRules::CLASS_RULES[#{api.inspect}]. Chaves exemplo: :fighter, :wizard, :cleric"
      exit 1
    end
    out = rule.deep_stringify_keys
    puts JSON.pretty_generate(out)
    puts
    puts '# Copie o JSON acima para klasses.rules (api_index deve coincidir com :id do objeto).'
    puts "# saving_throws: códigos em EN (ex. str, dex) — o provider traduz na leitura."
  end

  desc 'Valida JSON de stdin ou ficheiro contra KlassDbRulesContract. Uso: bin/rails class_rules:validate_rules[path/to.json]'
  task :validate_rules, [:path] => :environment do |_t, args|
    path = args[:path]
    raw =
      if path.present?
        File.read(Rails.root.join(path))
      else
        $stdin.read
      end
    if raw.strip.empty?
      $stderr.puts 'class_rules:validate_rules — forneça ficheiro ou redirecione stdin.'
      exit 1
    end
    data = JSON.parse(raw)
    KlassDbRulesContract.validate!(data)
    lo = KlassDbRulesContract.validate_loose(data)
    puts 'OK: chaves obrigatórias presentes.'
    if lo[:missing_recommended].any?
      puts "Aviso: recomendáveis em falta (homebrew frágil no wizard): #{lo[:missing_recommended].join(', ')}"
    end
  rescue JSON::ParserError => e
    $stderr.puts "JSON inválido: #{e.message}"
    exit 1
  rescue ArgumentError => e
    $stderr.puts e.message
    exit 1
  end
end
