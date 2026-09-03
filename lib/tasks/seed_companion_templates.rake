# Semeia o CATALOGO DE COMPANHEIROS a partir dos modelos que viviam hardcoded
# no front (`companionTemplates.ts`).
#
#   bundle exec rake dnd:seed_companion_templates          # DRY RUN
#   APPLY=1 bundle exec rake dnd:seed_companion_templates  # aplica
#   APPLY=1 FORCE=1 ... # re-sincroniza os que ja existem (sobrescreve)
#
# Idempotente pelo `slug`. Por padrao NAO toca no que ja existe — depois do
# primeiro seed o Mestre passa a editar pelo compendio, e um re-run nao pode
# desfazer o que ele ajustou. FORCE=1 e o escape consciente.
namespace :dnd do
  desc 'Importa os modelos de companheiro do JSON de seed. APPLY=1 aplica.'
  task seed_companion_templates: :environment do
    aplicar = ENV['APPLY'].to_s == '1'
    forcar  = ENV['FORCE'].to_s == '1'
    puts(aplicar ? '== APLICANDO ==' : '== DRY RUN (use APPLY=1 para aplicar) ==')
    puts('== FORCE: sobrescreve os existentes ==') if forcar

    caminho = Rails.root.join('db', 'seeds', 'companion_templates.json')
    unless File.exist?(caminho)
      puts "  arquivo nao encontrado: #{caminho}"
      next
    end

    linhas = JSON.parse(File.read(caminho))
    criados = 0
    atualizados = 0
    pulados = 0

    linhas.each do |linha|
      slug = linha['slug'].to_s
      existente = CompanionTemplate.find_by(slug: slug)

      if existente && !forcar
        pulados += 1
        next
      end

      atributos = linha.slice(
        'slug', 'name', 'companion_type', 'origin', 'origin_spell_id',
        'origin_class_feature', 'creature_type', 'size', 'ac', 'hp_max',
        'speed', 'speed_modes', 'prof_bonus', 'carry_capacity', 'stats', 'attacks',
        'special_actions', 'flags', 'skill_proficiencies', 'save_proficiencies',
        'description', 'source'
      )

      if existente
        puts "  ~ #{slug} (#{linha['companion_type']}) #{linha['name']}"
        atualizados += 1
        existente.update!(atributos) if aplicar
      else
        puts "  + #{slug} (#{linha['companion_type']}) #{linha['name']}"
        criados += 1
        CompanionTemplate.create!(atributos) if aplicar
      end
    end

    puts
    puts "  criados: #{criados} | atualizados: #{atualizados} | ja existiam: #{pulados}"
    puts "  total no banco: #{CompanionTemplate.count}" if aplicar
  end
end
