# frozen_string_literal: true

# FASE 4 das magias — conjuração por RECURSO (o "2 Chi" do Monge das Sombras).
#
#   DRY_RUN=1 bundle exec rake dnd:seed_spell_sources_resource
#   bundle exec rake dnd:seed_spell_sources_resource
#
# ⚠️ O dado já existia e ninguém o lia. `subclass_overrides.yml` declara, na
# feature Artes Sombrias:
#
#     rules:
#       spells_with_ki:
#         cost_per_cast: 2
#         list: ["escuridão","visão no escuro","passos sem pegadas","silêncio"]
#
# Nada transformava isso em `SpellSource`. O resultado é que "Artes Sombrias"
# aparecia no catálogo de ações como TEXTO ("2 Chi") e a magia não se conjurava
# de lado nenhum — o monge não tem espaço de magia para gastar.
#
# A chave do recurso vem do SUFIXO (`spells_with_ki` → `ki`), que é a mesma
# chave do `config/class_resources.yml`. Escrito assim, uma subclasse futura com
# `spells_with_sorcery_points` entra sozinha.
#
# ⚠️ Só toca em `origin: 'derived'`: o que o mestre atrelar à mão sobrevive.
namespace :dnd do
  desc 'FASE 4 — atrela magias conjuradas por RECURSO (2 Chi do Monge das Sombras). DRY_RUN=1 relata.'
  task seed_spell_sources_resource: :environment do
    seco = ENV['DRY_RUN'].present?
    resolvedor = SpellResolver.new
    achados = []
    sem_catalogo = []
    sem_subclasse = []

    recursos_validos = begin
      YAML.load_file(Rails.root.join('config', 'class_resources.yml')).keys.map(&:to_s)
    rescue StandardError
      []
    end

    DndImportHelpers.merged_overrides.each do |klass_idx, subclasses|
      klass = Klass.find_by(api_index: klass_idx)
      next unless klass && subclasses.is_a?(Hash)

      subclasses.each do |sub_idx, raw|
        next if %w[boons invocations rules].include?(sub_idx.to_s)
        next unless raw.is_a?(Hash)

        data = raw.respond_to?(:with_indifferent_access) ? raw.with_indifferent_access : raw
        # ⚠️ Mesmo mapeamento do applier: a chave do YAML (`sombra`) não é o
        # `api_index` da subclasse (`caminho-da-sombra`). Reimplementá-lo aqui
        # criaria uma segunda tabela de nomes, que divergiria na primeira
        # subclasse nova.
        alvo_idx = DndImportHelpers::SUBCLASS_ALIASES.dig(klass_idx.to_s, sub_idx.to_s) || sub_idx
        sub = SubKlass.find_by(api_index: alvo_idx, klass_id: klass.id)

        Array(data[:levels]).each do |linha|
          next unless linha.is_a?(Hash)

          nivel = (linha[:level] || linha['level']).to_i
          Array(linha[:features]).each do |feature|
            next unless feature.is_a?(Hash)

            regras = feature[:rules] || feature['rules']
            next unless regras.is_a?(Hash)

            regras.each do |chave, corpo|
              m = chave.to_s.match(/\Aspells_with_(.+)\z/)
              next unless m && corpo.is_a?(Hash)

              recurso = m[1].to_s
              custo = (corpo[:cost_per_cast] || corpo['cost_per_cast']).to_i
              lista = Array(corpo[:list] || corpo['list'])
              next if lista.empty?

              if sub.nil?
                sem_subclasse << "#{klass_idx}/#{sub_idx} (#{alvo_idx})"
                next
              end

              lista.each do |nome|
                magia = resolvedor.resolve(nome.to_s)
                if magia.nil?
                  sem_catalogo << "#{sub.name}: #{nome.inspect}"
                  next
                end

                achados << {
                  sub: sub, spell: magia, recurso: recurso,
                  custo: custo.positive? ? custo : nil,
                  nivel: nivel.positive? ? nivel : nil,
                  feature: (feature[:name] || feature['name']).to_s,
                  recurso_conhecido: recursos_validos.include?(recurso)
                }
              end
            end
          end
        end
      end
    end

    if seco
      puts "[DRY RUN] #{achados.size} atrelagens por RECURSO derivadas:"
      achados.each do |a|
        marca = a[:recurso_conhecido] ? '' : '  ⚠️ recurso fora de class_resources.yml'
        puts format('  %-22s %-24s %s %s (nv classe %s)%s',
                    a[:sub].name, a[:spell].name, a[:custo], a[:recurso], a[:nivel], marca)
      end
      puts "\nmagias do YAML que o catálogo não tem: #{sem_catalogo.size}"
      sem_catalogo.each { |s| puts "  #{s}" }
      puts "subclasses não encontradas: #{sem_subclasse.uniq.size}"
      sem_subclasse.uniq.each { |s| puts "  #{s}" }
      next
    end

    criados = 0
    atualizados = 0
    ActiveRecord::Base.transaction do
      achados.each do |a|
        linha = SpellSource.find_or_initialize_by(
          source_type: 'SubKlass', source_id: a[:sub].id, spell_id: a[:spell].id
        )
        # ⚠️ Não rebaixa nem sobrescreve o que o mestre marcou como `manual`.
        next if linha.persisted? && linha.origin == 'manual'

        novo = linha.new_record?
        linha.origin = 'derived'
        linha.casting_mode = 'resource'
        linha.resource_key = a[:recurso]
        linha.resource_cost = a[:custo]
        linha.min_class_level = a[:nivel]
        # Conjurar por recurso não é "preparada": não ocupa lugar na lista.
        linha.always_prepared = false
        linha.notes = "feature: #{a[:feature]}"
        linha.save!
        novo ? criados += 1 : atualizados += 1
      end
    end

    puts "atrelagens por recurso: #{criados} criadas, #{atualizados} atualizadas"
    puts "  por recurso: #{achados.group_by { |a| a[:recurso] }.transform_values(&:size)}"
    puts "  magias sem catálogo: #{sem_catalogo.size}" if sem_catalogo.any?
  end
end
