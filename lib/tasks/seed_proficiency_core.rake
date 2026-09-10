# frozen_string_literal: true

# FASE 0 do catálogo — PERÍCIA, SALVAGUARDA e ARMADURA.
#
#   bundle exec rake dnd:seed_proficiency_core            # aplica
#   DRY_RUN=1 bundle exec rake dnd:seed_proficiency_core  # só relata
#
# Os três tipos LIMPOS: nenhum tem grafias rivais de verdade, só vocabulários
# diferentes entre camadas — e é exatamente o que os apelidos resolvem.
#
#   PERÍCIA      — as 4 fontes concordam nas mesmas 18 (`SkillsCatalog`,
#                  `background_rules.rb`, `race_rules.yml`, fichas). ZERO
#                  divergência: o único problema é o front repetir a lista em
#                  30 arquivos, o que é a fase 1.
#   SALVAGUARDA  — DUAS grafias: `Klass.saving_throws` guarda por extenso
#                  ("Destreza"), a ficha guarda a abreviação ("DES").
#   ARMADURA     — DUAS: a ficha guarda slug inglês ("light"), `race_rules.yml`
#                  guarda pt-BR ("leve"). O rótulo exibido é um terceiro
#                  ("Armaduras Leves"), e é ele o canônico.
namespace :dnd do
  # ⚠️ Derivada do `SkillsCatalog`, que é a fonte que o seed do backend já usa,
  # e NÃO de uma lista nova. Duas listas para a mesma coisa foi o que criou as
  # quatro grafias de "Veículos terrestres".
  PERICIAS_ATRIBUTO = {
    'Acrobacia' => 'dex', 'Arcanismo' => 'int', 'Atletismo' => 'str',
    'Atuação' => 'cha', 'Enganação' => 'cha', 'Furtividade' => 'dex',
    'História' => 'int', 'Intimidação' => 'cha', 'Intuição' => 'wis',
    'Investigação' => 'int', 'Lidar com Animais' => 'wis', 'Medicina' => 'wis',
    'Natureza' => 'int', 'Percepção' => 'wis', 'Persuasão' => 'cha',
    'Prestidigitação' => 'dex', 'Religião' => 'int', 'Sobrevivência' => 'wis',
  }.freeze

  # nome canônico (por extenso) => [abreviação da ficha, slug]
  SALVAGUARDAS = {
    'Força' => %w[FOR str], 'Destreza' => %w[DES dex], 'Constituição' => %w[CON con],
    'Inteligência' => %w[INT int], 'Sabedoria' => %w[SAB wis], 'Carisma' => %w[CAR cha],
  }.freeze

  # rótulo EXIBIDO (canônico), sub-categoria, apelidos
  # ⚠️ O SINGULAR ("armadura leve") entra porque é assim que os grants de
  # subclasse grafam — `teurgia-mistica` nv2 concede "armadura leve". Sem ele,
  # a associação ficava órfã em silêncio.
  ARMADURAS = [
    ['Armaduras Leves',   'light',  ['light', 'light-armor', 'leve', 'leves', 'armadura leve']],
    ['Armaduras Médias',  'medium', ['medium', 'medium-armor', 'media', 'média', 'medias', 'médias', 'armadura média']],
    ['Armaduras Pesadas', 'heavy',  ['heavy', 'heavy-armor', 'pesada', 'pesadas', 'armadura pesada']],
    ['Escudos',           'shield', %w[shield shields escudo]],
  ].freeze

  desc 'FASE 0 — semeia PERÍCIA, SALVAGUARDA e ARMADURA (DRY_RUN=1 relata)'
  task seed_proficiency_core: :environment do
    seco = ENV['DRY_RUN'].present?
    criados = atualizados = apelidos = 0

    poe = lambda do |prefixo, nome, categoria, sub, extras, meta|
      idx = "#{prefixo}-#{Proficiency.normalize(nome).tr(' ', '-')}"
      p = Proficiency.find_or_initialize_by(api_index: idx)
      novo = p.new_record?
      p.assign_attributes(name: nome, category: categoria, sub_category: sub,
                          metadata: meta || {}, source: 'PHB', published: true)
      if seco
        puts "  #{novo ? 'CRIARIA' : 'atualizaria'} #{idx.ljust(34)} #{nome}"
      else
        p.save!
        ([nome] + Array(extras)).each do |a|
          antes = ProficiencyAlias.count
          p.add_alias!(a)
          apelidos += 1 if ProficiencyAlias.count > antes
        end
      end
      novo ? criados += 1 : atualizados += 1
    end

    ActiveRecord::Base.transaction do
      PERICIAS_ATRIBUTO.each { |nome, attr| poe.call('skill', nome, 'skill', nil, [], { 'ability' => attr }) }
      SALVAGUARDAS.each do |nome, (abrev, slug)|
        poe.call('save', nome, 'saving_throw', nil, [abrev, slug], { 'abbrev' => abrev, 'ability' => slug })
      end
      ARMADURAS.each { |nome, sub, extras| poe.call('armor', nome, 'armor', sub, extras, nil) }
      raise ActiveRecord::Rollback if seco
    end

    puts "\n#{seco ? '[DRY RUN] ' : ''}core: #{criados} criados, #{atualizados} já existiam, #{apelidos} apelidos novos"
    unless seco
      %w[skill saving_throw armor].each { |c| puts "  #{c.ljust(14)} #{Proficiency.of(c).count}" }
    end
  end
end
