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

# Poda: o único jeito de a biblioteca ficar só com arte em alta. Destrutivo em
# produção, então o que estes testes guardam é o que NÃO pode acontecer.
RSpec.describe 'poda de objetos sem alta' do
  RAKE_PRUNE = Rails.root.join('lib/tasks/inkarnate_objects_prune.rake')

  let(:fonte) { File.read(RAKE_PRUNE) }

  it '⚠️ nunca remove objeto POSICIONADO num mapa (o token guarda só o assetId)' do
    # sem chave estrangeira, apagar o asset deixa o objeto no mapa apontando
    # p/ imagem que não existe mais
    expect(fonte).to include("jsonb_array_elements(coalesce(bm.tokens, '[]'::jsonb))")
    expect(fonte).to match(/if em_uso\.include\?\(ma\.id\)/)
    expect(fonte).to match(/counts\[:em_uso_preservado\]/)
  end

  it 'só mira objeto SEM arte em alta' do
    expect(fonte).to match(/where\(kind: 'object'\)/)
    expect(fonte).to match(/where\.not\('active_storage_blobs\.filename LIKE \?', 'ink-%'\)/)
  end

  it 'destrutivo exige APPLY=1 — sem ele só conta' do
    expect(fonte).to match(/aplica = ENV\['APPLY'\] == '1'/)
    conta = fonte.index('counts[:removeria]')
    destroi = fonte.index('ma.destroy')
    expect(conta).to be < destroi
    expect(fonte).to match(/unless aplica\n\s+counts\[:removeria\] \+= 1\n\s+next/)
  end
end

RSpec.describe 'poda — arte própria do Mestre fica fora' do
  let(:fonte) { File.read(Rails.root.join('lib/tasks/inkarnate_objects_prune.rake')) }

  it 'a categoria "Meus" nunca entra na mira', :aggregate_failures do
    # o que ele enviou não veio do catálogo: "sem alta" ali não é descartável
    expect(fonte).to match(/CATEGORIAS_DO_MESTRE = \['Meus'\]\.freeze/)
    expect(fonte).to match(/where\.not\(category: CATEGORIAS_DO_MESTRE\)/)
  end
end

# Importação do catálogo INTEIRO: a biblioteca tinha ~18% do que a conta
# acessa, e o que faltava eram os itens, não a qualidade deles.
RSpec.describe 'índice do catálogo do Inkarnate' do
  INDICE_CAT = Rails.root.join('db/data/inkarnate_catalog.json')
  RAKE_CAT = Rails.root.join('lib/tasks/inkarnate_catalog_import.rake')

  let(:dados) { JSON.parse(File.read(INDICE_CAT)) }
  let(:itens) { dados['itens'] }
  let(:fonte) { File.read(RAKE_CAT) }

  it 'traz o catálogo inteiro, em muitos packs e categorias' do
    expect(itens.size).to eq(dados['total'])
    expect(itens.size).to be > 10_000
    expect(itens.map { |i| i['c'] }.uniq.size).to be >= 5
    expect(itens.map { |i| [i['c'], i['g']] }.uniq.size).to be > 50
  end

  it 'cabe nos limites das colunas do MapAsset' do
    expect(itens.count { |i| i['n'].to_s.length > 80 }).to eq(0)
    expect(itens.count { |i| i['c'].to_s.length > 40 }).to eq(0)
    expect(itens.count { |i| i['g'].to_s.length > 60 }).to eq(0)
    expect(itens.count { |i| i['vg'] && i['vg'].length > 80 }).to eq(0)
    expect(itens.count { |i| i['n'].to_s.strip.empty? }).to eq(0)
  end

  it 'o nome é único dentro de (categoria, pack) — o catálogo repete título entre variantes' do
    chaves = itens.map { |i| [i['c'], i['g'], i['n'].downcase] }

    expect(chaves.uniq.size).to eq(chaves.size)
  end

  it 'toda imagem vem do CDN do Inkarnate, com um degrau de recuo p/ o teto de 5 MB' do
    urls = itens.flat_map { |i| i['us'] }
    expect(urls.all? { |u| u.start_with?('https://cdn2.inkarnate.com/') }).to be(true)
    expect(itens.count { |i| i['us'].size > 2 }).to eq(0)
  end

  it '⚠️ a idempotência é pelo NOME DO ARQUIVO (ink-<assetId>), não pelo nome do item' do
    # é o que deixa rodar em pedaços e retomar, e o que impede duplicar o que a
    # conversão anterior já trouxe
    expect(fonte).to match(/SELECT filename FROM active_storage_blobs WHERE filename LIKE 'ink-%'/)
    expect(fonte).to include('ink-(\\d+)')
    expect(fonte).to match(/reject \{ \|i\| presentes\.include\?\(i\['aid'\]\) \}/)
  end

  it 'respeita os limites do próprio model em vez de repetir os números' do
    expect(fonte).to include('MapAsset::MAX_BYTES')
    expect(fonte).to include('MapAsset::ALLOWED_CONTENT_TYPES')
  end
end
