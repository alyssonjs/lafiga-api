# frozen_string_literal: true

require 'rails_helper'
require 'rake'

# A rake que traz para o banco o texto que vivia escrito no front.
#
# O que se prova aqui é sobretudo o que ela NÃO faz: rodar de novo não pode
# desfazer o que o Editor escreveu pelo lápis — e ela roda a cada deploy.
RSpec.describe 'wiki:semear_artigos' do
  before(:all) do
    Rake::Task.clear
    Rails.application.load_tasks
  end

  def rodar(env = {})
    env.each { |k, v| ENV[k] = v }
    Rake::Task['wiki:semear_artigos'].reenable
    expect { Rake::Task['wiki:semear_artigos'].invoke }.to output(/semear_artigos/).to_stdout
  ensure
    env.each_key { |k| ENV.delete(k) }
  end

  it 'semeia a seção pedida a partir do YAML' do
    rodar('SECTION' => 'gods')

    deuses = WikiArticle.in_section('gods')
    expect(deuses.count).to be > 0
    expect(deuses.ordered.first.data['name']).to be_present
  end

  it 'DRY_RUN só relata — não grava nada' do
    rodar('SECTION' => 'gods', 'DRY_RUN' => '1')

    expect(WikiArticle.count).to eq(0)
  end

  it '⚠️ rodar de novo NÃO desfaz o que a mesa reescreveu' do
    rodar('SECTION' => 'gods')
    artigo = WikiArticle.in_section('gods').ordered.first
    artigo.update!(data: artigo.data.merge('lore' => 'Reescrito pelo Editor.'))

    rodar('SECTION' => 'gods')

    expect(artigo.reload.data['lore']).to eq('Reescrito pelo Editor.')
  end

  it 'cria só o que falta' do
    rodar('SECTION' => 'gods')
    antes = WikiArticle.in_section('gods').count
    WikiArticle.in_section('gods').ordered.first.destroy!

    rodar('SECTION' => 'gods')

    expect(WikiArticle.in_section('gods').count).to eq(antes)
  end
end
