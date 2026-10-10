# frozen_string_literal: true

require 'rails_helper'
require 'ripper'

# O DETERMINISMO do mundo (plano D11; L0.4). Em `app/services/mundo/**`, nada lê o relógio da máquina, sorteia por
# conta própria ou faz conta com ponto flutuante: é o que garante que reprocessar a agenda dá o mesmo resultado. O
# agora vem de quem chama; o dado virá do `Dados::Fonte` (L0.6).
#
# A conferência lê os tokens do Ruby (`Ripper`), então um comentário ou um texto que cite `Time.now` não conta.
RSpec.describe 'o determinismo de app/services/mundo' do
  # [linha, o que achou] de cada uso proibido
  def violacoes(codigo)
    ignorados = %i[on_sp on_nl on_ignored_nl on_comment on_embdoc_beg on_embdoc on_embdoc_end]
    tokens = Ripper.lex(codigo).reject { |t| ignorados.include?(t[1]) }
    tokens.each_with_index.filter_map do |((linha, _), tipo, texto), i|
      seguinte = tokens[i + 1]&.dig(1) == :on_period ? tokens[i + 2]&.dig(2) : nil
      motivo =
        case tipo
        when :on_float then "ponto flutuante (#{texto})"
        when :on_const
          if %w[Random SecureRandom Float].include?(texto) then texto
          elsif texto == 'Time' && %w[current now zone].include?(seguinte) then "Time.#{seguinte}"
          elsif %w[Date DateTime].include?(texto) && %w[today current now].include?(seguinte) then "#{texto}.#{seguinte}"
          end
        when :on_ident then texto if %w[rand srand shuffle sample to_f].include?(texto)
        end
      [linha, motivo] if motivo
    end
  end

  arquivos = Dir[Rails.root.join('app/services/mundo/**/*.rb').to_s].sort

  it 'tem o que conferir' do
    expect(arquivos.size).to be >= 5
  end

  arquivos.each do |arquivo|
    it(arquivo.delete_prefix("#{Rails.root}/")) do
      expect(violacoes(File.read(arquivo))).to eq([])
    end
  end

  it 'a conferência pega o que deve e deixa o resto' do
    codigo = <<~RUBY
      x = Time.current
      y = rand(3)
      z = 1.5
      w = a.to_f
      q = SecureRandom.hex
      d = Date.today
      ok = Time.at(1, 500, :millisecond) # Time.now num comentário não conta
      texto = "rand e Time.now num texto também não"
    RUBY
    expect(violacoes(codigo).map(&:first)).to eq([1, 2, 3, 4, 5, 6])
  end
end
