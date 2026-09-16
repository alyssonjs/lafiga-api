# frozen_string_literal: true

namespace :subclasses do
  # ⚠️ RODAR ANTES de a página de sub-classes ir ao ar.
  #
  # O compêndio já deixava o mestre editar o TEXTO de uma feature de sub-classe
  # (`Admin::LevelFeatureEditor` marca `dm_customized`), mas isso vivia só em
  # `features` — o `levels_json`, que é a regra, seguia com o texto do livro.
  # Agora que gravar a regra dispara o sync com `update_descriptions: true`, o
  # primeiro Guardar na página passaria por cima dessas edições em silêncio.
  #
  # Esta rake empurra o texto editado PARA o `levels_json` e carimba `edited_at`
  # (que é, aliás, exatamente o que a guarda do import quer saber). Idempotente.
  #
  #   bundle exec rails subclasses:absorve_edicoes_dm            # relatório
  #   bundle exec rails subclasses:absorve_edicoes_dm APPLY=1    # grava
  desc 'Empurra o texto de features dm_customized para o levels_json da sub-classe (APPLY=1 grava)'
  task absorve_edicoes_dm: :environment do
    aplicar = ENV['APPLY'] == '1'
    puts "== subclasses:absorve_edicoes_dm (#{aplicar ? 'APLICANDO' : 'simulação — use APPLY=1'})"

    absorvidas = 0
    subs_tocadas = 0
    sem_casar = []

    SubKlass.includes(sub_klass_levels: :features).find_each do |sub|
      linhas = sub.linhas_de_nivel
      next if linhas.empty?

      mudou = false
      novas = linhas.map do |linha|
        nivel = linha['level'].to_i
        feats = Array(linha['features']).select { |f| f.is_a?(Hash) }
        next linha if feats.empty?

        registro_por_nivel = sub.sub_klass_levels.find { |l| l.level == nivel }
        editadas = Array(registro_por_nivel&.features).select { |f| f.respond_to?(:dm_customized) && f.dm_customized }
        next linha if editadas.empty?

        atualizadas = feats.map do |bruta|
          casada = editadas.find { |f| casa?(bruta, f) }
          next bruta if casada.nil?
          next bruta if bruta['name'].to_s == casada.name.to_s && bruta['description'].to_s == casada.description.to_s

          absorvidas += 1
          mudou = true
          puts "   #{sub.api_index} nv#{nivel}: #{casada.name.inspect}"
          bruta.merge('name' => casada.name, 'description' => casada.description.to_s)
        end

        # Feature editada que não casou com linha nenhuma: relatada, nunca
        # inventada no `levels_json` — pode ser uma feature legada duplicada.
        editadas.each do |f|
          sem_casar << "#{sub.api_index} nv#{nivel}: #{f.name}" if atualizadas.none? { |b| casa?(b, f) }
        end

        linha.merge('features' => atualizadas)
      end

      next unless mudou

      subs_tocadas += 1
      next unless aplicar

      sub.update!(levels_json: novas, edited_at: Time.current)
    end

    puts "\n== #{absorvidas} feature(s) absorvida(s) em #{subs_tocadas} sub-classe(s)"
    if sem_casar.any?
      puts "== #{sem_casar.size} feature(s) dm_customized SEM linha correspondente no levels_json:"
      sem_casar.first(30).each { |l| puts "   - #{l}" }
    end
    puts '== nada gravado (rode com APPLY=1)' unless aplicar
  end

  # Mesmo casamento do editor: `index` quando existe, senão nome normalizado.
  def casa?(bruta, feature)
    indice = bruta['index'].to_s
    return indice == feature.api_index.to_s if indice.present?

    normaliza(bruta['name']) == normaliza(feature.name)
  end

  def normaliza(texto)
    I18n.transliterate(texto.to_s).downcase.strip.gsub(/[^a-z0-9]+/, '-').gsub(/^-+|-+$/, '')
  end
end
