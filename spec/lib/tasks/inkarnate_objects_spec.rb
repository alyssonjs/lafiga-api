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
    expect(fonte).to include('SELECT filename FROM active_storage_blobs WHERE filename LIKE ?')
    expect(fonte).to include('#{prefixo}-(\\d+)')
    expect(fonte).to match(/reject \{ \|i\| presentes\.include\?\(i\['aid'\]\) \}/)
  end

  it 'respeita os limites do próprio model em vez de repetir os números' do
    expect(fonte).to include('MapAsset::MAX_BYTES')
    expect(fonte).to include('MapAsset::ALLOWED_CONTENT_TYPES')
  end
end

# Catálogo de TEXTURAS: a mesma história dos objetos — a biblioteca tinha o
# recorte importado à mão (243) contra 707 no catálogo.
RSpec.describe 'índice do catálogo de texturas' do
  INDICE_TEXCAT = Rails.root.join('db/data/inkarnate_textures_catalog.json')
  RAKE_IMPORT = Rails.root.join('lib/tasks/inkarnate_catalog_import.rake')

  let(:dados) { JSON.parse(File.read(INDICE_TEXCAT)) }
  let(:itens) { dados['itens'] }
  let(:fonte) { File.read(RAKE_IMPORT) }

  it 'traz o catálogo inteiro, em muitos packs' do
    expect(itens.size).to eq(dados['total'])
    expect(itens.size).to be > 600
    expect(itens.map { |i| [i['c'], i['g']] }.uniq.size).to be > 40
  end

  it '⚠️ a categoria é o ESTILO, não "Terrenos"', :aggregate_failures do
    # com 54 packs numa categoria só, o "Core" de Fantasy World e o de
    # Watercolor Cities colidiriam na mesma subcategoria
    expect(itens.map { |i| i['c'] }.uniq.size).to be >= 5
    expect(itens.map { |i| i['c'] }).not_to include('Terrenos')
  end

  it 'o nome é único dentro de (categoria, pack)' do
    chaves = itens.map { |i| [i['c'], i['g'], i['n'].downcase] }

    expect(chaves.uniq.size).to eq(chaves.size)
  end

  it 'cabe nos limites das colunas e vem do CDN do Inkarnate' do
    expect(itens.count { |i| i['n'].to_s.length > 80 }).to eq(0)
    expect(itens.count { |i| i['c'].to_s.length > 40 }).to eq(0)
    expect(itens.count { |i| i['g'].to_s.length > 60 }).to eq(0)
    expect(itens.flat_map { |i| i['us'] }.all? { |u| u.start_with?('https://cdn2.inkarnate.com/') }).to be(true)
  end

  # Em x2 (1024²) cada célula ficava com ~13 px: a textura cobre 80 células por
  # repetição em 100%, como no Inkarnate, e só o x8 (4096²) aguenta isso.
  it '⚠️ mira o nível x8 do CDN, com o x4 como degrau de recuo p/ o teto de 5 MB', :aggregate_failures do
    expect(dados['alvo_px']).to eq(4096)
    x8 = {
      594921 => 'https://cdn2.inkarnate.com/sb6xbgafkwtevzpqz0847q8c8me5', # Green Light (terra padrão)
      594920 => 'https://cdn2.inkarnate.com/465ql508yz3jkl8e3mxkq6dfnwp8', # Water (água padrão)
      573870 => 'https://cdn2.inkarnate.com/4lau8epmpbmshphq9u5y9vco03ho', # Grass
      573872 => 'https://cdn2.inkarnate.com/t39pltd0w7d8z2kbyjttg8zkr70b', # Dirt
    }
    porAid = itens.index_by { |i| i['aid'] }
    x8.each { |aid, url| expect(porAid.fetch(aid)['us'].first).to eq(url) }
    # a esmagadora maioria traz o recuo; só quem não tem x4 no CDN fica com 1 URL
    expect(itens.count { |i| i['us'].size == 2 }).to be > (itens.size * 0.95)
  end

  it '⚠️ o prefixo do arquivo separa textura de objeto — e `inktex-` não casa com `ink-%`' do
    # é o que impede a poda de objetos de mirar uma textura
    expect(fonte).to match(/prefixo = \{ 'texture' => 'inktex', 'path' => 'inkpath' \}\.fetch\(kind, 'ink'\)/)
    expect('inktex-123.png').not_to start_with('ink-')
    expect(fonte).to match(/kind: kind,/)
  end
end

# Caminhos (Shape/Path tool): o asset do Inkarnate é uma RECEITA, não imagem.
RSpec.describe 'índice do catálogo de caminhos' do
  INDICE_PATHS = Rails.root.join('db/data/inkarnate_paths_catalog.json')

  let(:dados) { JSON.parse(File.read(INDICE_PATHS)) }
  let(:itens) { dados['itens'] }
  let(:fonte) { File.read(Rails.root.join('lib/tasks/inkarnate_catalog_import.rake')) }

  it 'resolve a receita: o que fica no índice é a URL do TILE que se repete' do
    gerador = File.read(Rails.root.join('db/data/gerar_inkarnate_paths_catalog.py'))

    expect(gerador).to include('stampStroke')
    expect(gerador).to include('strokeAssetId')
    expect(itens.size).to eq(dados['total'])
    expect(itens.size).to be > 300
    expect(itens.flat_map { |i| i['us'] }.all? { |u| u.start_with?('https://cdn2.inkarnate.com/') }).to be(true)
  end

  it 'guarda a PROPORÇÃO do tile — é ela que dá a largura natural do traço' do
    expect(itens.all? { |i| i['w'].to_i.positive? && i['h'].to_i.positive? }).to be(true)
    # tiles de caminho são longos: repetem na horizontal
    expect(itens.count { |i| i['w'].to_i > i['h'].to_i }).to be > (itens.size * 0.8)
  end

  it 'a ponta (cap) entra quando existe, e a falta dela não derruba o item' do
    comCap = itens.count { |i| i['cap'] }
    expect(comCap).to be > 200
    expect(comCap).to be < itens.size
  end

  it 'o rake conhece o KIND path, com prefixo próprio de arquivo' do
    expect(fonte).to match(/%w\[object texture path\]/)
    expect(fonte).to match(/'path' => 'inkpath'/)
  end

  it '⚠️ o "já presentes" é contado ANTES do LIMIT (senão o corte se disfarça de importado)' do
    antes = fonte.index('já presentes')
    depois = fonte.index('pendentes = limit.positive?')
    expect(antes).to be < depois
  end
end
