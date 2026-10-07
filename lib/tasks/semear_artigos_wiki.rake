# frozen_string_literal: true

# Semeia a wiki a partir de `config/wiki_articles.yml` — o texto que até
# 07/10/2026 vivia escrito à mão em cada página do front.
#
#   bin/rails wiki:semear_artigos              # cria o que falta
#   DRY_RUN=1 bin/rails wiki:semear_artigos    # só relata
#   SECTION=gods bin/rails wiki:semear_artigos # uma seção
#
# ⚠️ IDEMPOTENTE E NÃO DESTRUTIVA, de propósito: artigo que já existe
# (section + slug) é DEIXADO EM PAZ. Rodar duas vezes não desfaz o que a mesa
# escreveu pelo lápis — e, como esta rake roda no deploy, sobrescrever seria
# apagar o trabalho do Editor a cada subida.
#
# Artigo APAGADO pelo Editor volta a nascer na próxima rodada (não há lápide
# no banco). É o preço de não guardar registro de remoção; se virar incômodo,
# o caminho é uma coluna `deleted_at`, não desligar a rake.
namespace :wiki do
  desc 'Semeia os artigos da wiki de config/wiki_articles.yml (não sobrescreve o que já existe). DRY_RUN=1 só relata.'
  task semear_artigos: :environment do
    seco = ENV['DRY_RUN'].present?
    caminho = Rails.root.join('config', 'wiki_articles.yml')
    abort "não achei #{caminho}" unless File.exist?(caminho)

    conteudo = YAML.safe_load(File.read(caminho))
    conteudo = conteudo.slice(ENV['SECTION']) if ENV['SECTION'].present?

    criados = 0
    mantidos = 0

    conteudo.each do |secao, artigos|
      Array(artigos).each_with_index do |artigo, idx|
        slug = artigo['id'].to_s
        if slug.blank?
          puts "⚠️  #{secao}: artigo sem id, pulado"
          next
        end

        if WikiArticle.in_section(secao).exists?(slug: slug)
          mantidos += 1
          next
        end

        criados += 1
        rotulo = artigo.values_at('name', 'guildName', 'title').compact.first || slug
        puts "#{seco ? '[DRY_RUN] ' : ''}#{secao} · #{rotulo} (#{slug})"
        next if seco

        WikiArticle.create!(section: secao, slug: slug, position: idx, data: artigo)
      end
    end

    puts "semear_artigos: #{criados} #{seco ? 'a criar' : 'criado(s)'}, #{mantidos} já existia(m)."
  end
end
