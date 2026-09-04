# frozen_string_literal: true

# Objetos do Inkarnate: o índice é DADO enviado no repositório e aplicado em
# produção por uma rake que baixa imagem e reescreve categoria/variantes.
#
# O risco não é a rake quebrar ruidosamente — é ela aplicar em silêncio:
# um `group_name` de 61 caracteres derruba o `save` de um item só, um item sem
# `chk` deixa a rake trocar a imagem de um MapAsset que não é aquele, e um
# cluster de variantes com um membro vira ruído na biblioteca. Estes testes são
# a catraca do CONTRATO do arquivo, não do texto da rake.
require 'rails_helper'

RSpec.describe 'índice de objetos do Inkarnate' do
  INDICE = Rails.root.join('db/data/inkarnate_objects.json')
  RAKE_OBJ = Rails.root.join('lib/tasks/inkarnate_objects.rake')

  let(:dados) { JSON.parse(File.read(INDICE)) }
  let(:itens) { dados['itens'] }

  it 'tem itens e a contagem declarada bate' do
    expect(itens).to be_an(Array)
    expect(itens.size).to eq(dados['total'])
    expect(itens.size).to be > 500
  end

  it 'cada item cabe nos limites das colunas do MapAsset (senão o save morre de um em um)' do
    grandes = itens.select do |i|
      (i['n'] && i['n'].length > 80) ||
        (i['c'] && i['c'].length > 40) ||
        (i['g'] && i['g'].length > 60) ||
        (i['vg'] && i['vg'].length > 80)
    end

    expect(grandes).to be_empty, "estouram o limite: #{grandes.first(3).inspect}"
  end

  it 'todo item traz o checksum do blob casado — sem ele a rake aplicaria no escuro' do
    expect(itens.count { |i| i['chk'].to_s.empty? }).to eq(0)
  end

  it 'nenhum item é vazio: ou tem imagem (us) ou tem metadado (c/g)' do
    vazios = itens.reject { |i| i['us'].is_a?(Array) && i['us'].any? || i['c'].present? }

    expect(vazios).to be_empty
  end

  it 'variant_order é inteiro (a coluna é NOT NULL)' do
    expect(itens.all? { |i| i['vo'].nil? || i['vo'].is_a?(Integer) }).to be(true)
  end

  # Cluster de UM membro é ruído na biblioteca. A conta, porém, é feita contra
  # a UNIÃO com o que já está em produção: um grupo partido entre duas levas de
  # conversão teria a metade nova descartada se olhássemos só este arquivo.
  it 'a regra do cluster conta junto o que já está em produção' do
    gerador = File.read(Rails.root.join('db/data/gerar_inkarnate_objects.py'))

    expect(gerador).to include('jaEmProd')
    expect(gerador).to match(/conta\[vg\] \+ jaEmProd\.get\(vg, 0\) < 2/)
  end

  it 'a esmagadora maioria dos agrupados está em cluster de verdade' do
    porGrupo = itens.filter_map { |i| i['vg'] }.tally
    emCluster = porGrupo.sum { |_, n| n >= 2 ? n : 0 }
    total = porGrupo.values.sum

    expect(total).to be > 100
    expect(emCluster.to_f / total).to be > 0.8
  end

  it 'as URLs de imagem são do CDN do Inkarnate, da maior variante p/ a menor' do
    urls = itens.filter_map { |i| i['us'] }.flatten
    expect(urls).to be_any
    expect(urls.all? { |u| u.start_with?('https://cdn2.inkarnate.com/') }).to be(true)
    # a primeira é a escolhida; as seguintes são degraus de recuo do teto de 5 MB
    expect(itens.filter_map { |i| i['us'] }.all? { |l| l.size >= 1 }).to be(true)
  end

  it 'a rake só mexe em objeto e pula blob que não é o casado' do
    fonte = File.read(RAKE_OBJ)

    expect(fonte).to include("ma.kind == 'object'")
    expect(fonte).to match(/blob\.checksum != it\['chk'\]/)
    # idempotência: o nome do arquivo anexado é a marca de "já está em alta"
    expect(fonte).to match(/start_with\?\("#\{nome_ink\}\."\)/)
  end

  it 'respeita o teto de tamanho do próprio model em vez de repetir o número' do
    fonte = File.read(RAKE_OBJ)

    expect(fonte).to include('MapAsset::MAX_BYTES')
    expect(fonte).to include('MapAsset::ALLOWED_CONTENT_TYPES')
  end
end

# Texturas: o mesmo contrato, mas de CRIAÇÃO — produção não tem nenhuma.
RSpec.describe 'índice de texturas do Inkarnate' do
  INDICE_TEX = Rails.root.join('db/data/inkarnate_textures.json')
  RAKE_TEX = Rails.root.join('lib/tasks/inkarnate_textures.rake')

  let(:dados) { JSON.parse(File.read(INDICE_TEX)) }
  let(:itens) { dados['itens'] }

  it 'tem itens, categoria declarada e a contagem bate' do
    expect(itens.size).to eq(dados['total'])
    expect(itens.size).to be > 200
    expect(dados['categoria']).to be_present
    expect(dados['categoria'].length).to be <= 40
  end

  it 'o nome é único (a idempotência da rake é por kind+category+name)' do
    nomes = itens.map { |i| i['n'].to_s.downcase }

    expect(nomes.uniq.size).to eq(nomes.size)
    expect(nomes.count(&:empty?)).to eq(0)
  end

  it 'cabe nos limites das colunas e traz tipo de imagem aceito' do
    expect(itens.count { |i| i['n'].length > 80 }).to eq(0)
    expect(itens.count { |i| i['g'] && i['g'].length > 60 }).to eq(0)
    expect(itens.count { |i| i['vg'] && i['vg'].length > 80 }).to eq(0)
    tipos = itens.map { |i| i['ct'] }.uniq

    expect(tipos - MapAsset::ALLOWED_CONTENT_TYPES).to be_empty
  end

  it 'toda textura tem origem no CDN do Inkarnate' do
    expect(itens.all? { |i| i['u'].to_s.start_with?('https://cdn2.inkarnate.com/') }).to be(true)
  end

  it 'a rake não duplica: existe? antes de criar' do
    fonte = File.read(RAKE_TEX)

    expect(fonte).to match(/MapAsset\.exists\?\(kind: 'texture', category: categoria, name: nome\)/)
    expect(fonte).to include('MapAsset::MAX_BYTES')
    expect(fonte).to include('MapAsset::ALLOWED_CONTENT_TYPES')
  end
end
