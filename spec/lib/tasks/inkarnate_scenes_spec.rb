# frozen_string_literal: true

# Cenas do Inkarnate importadas como BattleMaps.
#
# O que estes testes guardam não é o texto da rake: é a GEOMETRIA, que foi
# MEDIDA sobrepondo as caixas calculadas sobre o render do Inkarnate. Errar a
# régua não quebra nada ruidosamente — só faz cada objeto nascer no lugar
# errado, do tamanho errado, num mapa que parece quase certo.
require 'rails_helper'

RSpec.describe 'índice de cenas do Inkarnate' do
  INDICE_CENAS = Rails.root.join('db/data/inkarnate_scenes.json')
  RAKE_CENAS = Rails.root.join('lib/tasks/inkarnate_scenes_import.rake')
  GERADOR_CENAS = Rails.root.join('db/data/gerar_inkarnate_scenes.py')

  let(:dados) { JSON.parse(File.read(INDICE_CENAS)) }
  let(:cenas) { dados['cenas'] }
  let(:fonte) { File.read(RAKE_CENAS) }
  let(:gerador) { File.read(GERADOR_CENAS) }

  it 'tem cenas e a contagem declarada bate' do
    expect(cenas).to be_an(Array)
    expect(cenas.size).to eq(dados['total'])
    expect(cenas.size).to be > 5
  end

  it 'toda cena cabe nos limites do BattleMap (senão o save morre de uma em uma)' do
    cenas.each do |c|
      expect(c['largura']).to be_between(BattleMap::MIN_DIM, BattleMap::MAX_DIM),
                              "#{c['titulo']}: largura #{c['largura']}"
      expect(c['altura']).to be_between(BattleMap::MIN_DIM, BattleMap::MAX_DIM),
                             "#{c['titulo']}: altura #{c['altura']}"
      expect(c['titulo'].to_s.length).to be_between(1, 120)
    end
  end

  it 'a proporção do mapa em células segue a da cena — o fundo é ESTICADO na grade' do
    # o renderer desenha o fundo em width*cell x height*cell; se a razão
    # largura/altura divergir da cena, o terreno entra distorcido
    cenas.each do |c|
      next unless c['fundo_px'].is_a?(Array)

      razao_mapa = c['largura'].to_f / c['altura']
      razao_img = c['fundo_px'][0].to_f / c['fundo_px'][1]
      # o erro vem SÓ de arredondar para células inteiras (limitado a ~meia
      # célula); 4% relativo passa nisso e ainda pega régua trocada ou eixos
      # invertidos, que erram por dezenas de por cento
      erro = (razao_mapa - razao_img).abs / razao_img
      expect(erro).to be < 0.04,
                      "#{c['titulo']}: grade #{razao_mapa.round(3)} vs imagem #{razao_img.round(3)}"
    end
  end

  it 'todo token traz asset, posição e tamanho em CÉLULAS' do
    cenas.each do |c|
      c['tokens'].each do |t|
        expect(t['aid']).to be_a(Integer)
        expect(t['w']).to be > 0
        expect(t['h']).to be > 0
        expect(t['sub']).to be_between(-5, 5) if t['sub']
        expect(t['rot']).to be_between(0, 360) if t['rot']
      end
    end
  end

  it '⚠️ a régua é o GRID da cena, com a de 200 u/célula do catálogo como recuo' do
    # 200 é a régua MEDIDA do catálogo (assets "NxN" têm size.w = N*200); o grid
    # que o utilizador deixou na cena vence quando existe
    expect(gerador).to include('UNIDADES_POR_CELULA_PADRAO = 200.0')
    expect(gerador).to match(/def celula_da_cena/)
    expect(gerador).to match(/style'\) or \{\}\)\.get\('size'\)/)
  end

  it '⚠️ a âncora do stamp soma data.offset ESCALADO — foi assim que as caixas bateram na arte' do
    expect(gerador).to match(/e\.get\('x', 0\) \+ off\.get\('x', 0\) \* esc/)
    expect(gerador).to match(/e\.get\('y', 0\) \+ off\.get\('y', 0\) \* esc/)
  end

  it 'o replay entra nos cmd-composite e desfaz add/update/remove' do
    # sem achatar o composite, a grade e camadas inteiras somem do estado final
    expect(gerador).to match(/def achata/)
    expect(gerador).to match(/cmd-composite/)
    %w[cmd-entity-add cmd-entity-update cmd-entity-remove].each do |c|
      expect(gerador).to include(c)
    end
  end

  it '⚠️ a idempotência é pelo NOME DO ARQUIVO do fundo (ink-scene-<sid>)' do
    expect(fonte).to include('ink-scene-%')
    expect(fonte).to match(/ink-scene-\(\\d\+\)/)
    expect(fonte).to match(/reject \{ \|c\| presentes\.include\?\(c\['sid'\]\) \}/)
  end

  it '⚠️ o rake NÃO compõe imagem: produção não carrega libvips' do
    # a composição vive no gerador (PIL, local); aqui só se anexa o pronto
    expect(fonte).to match(/background_image\.attach/)
    expect(fonte).not_to match(/Vips|MiniMagick|ImageProcessing/)
    expect(gerador).to include('def compoe_fundo')
  end

  it 'o token nasce no shape que o front desenha (objeto de cenário, não criatura)' do
    expect(fonte).to include("'isObject' => true")
    expect(fonte).to include("'imageMode' => 'custom'")
    # o path tem de ser o MESMO que o serializer entrega ao front (é o que o
    # app grava ao carimbar) — o renderer usa customImageUrl cru como src
    expect(fonte).to include('/api/v1/admin/map_assets/#{ref[:id]}/image?v=#{ref[:blob]}')
    expect(File.read(Rails.root.join('app/services/map_asset_serializer.rb')))
      .to include('/api/v1/admin/map_assets/#{asset.id}/image?v=#{ver}')
    expect(fonte).to include("'objectWidth'")
    expect(fonte).to include("'objectHeight'")
  end

  it '⚠️ resolve os assets de UMA vez: um find_by por token seria N+1 com dezenas de milhares' do
    expect(fonte).not_to match(/MapAsset\.find_by/)
    expect(fonte).to match(/nomes = MapAsset\.where\(id:/)
  end

  it 'a sombra por stamp é convertida de unidades de cena para CÉLULAS' do
    # meta['shadow'] vem em unidades de cena; o token guarda em células
    expect(fonte).to match(/shadowBlurCells.*sombra\['b'\]\.to_f \/ u/m)
    expect(fonte).to include("tok['shadowMode'] = 'none'")
  end

  it '⚠️ SUBSTITUI não sobrescreve mapa que o Mestre editou depois do import' do
    expect(fonte).to match(/existente\.updated_at > existente\.created_at/)
    expect(fonte).to match(/counts\[:editado_preservado\]/)
    expect(fonte).to include("ENV['FORCE'] == '1'")
    # atualiza NO LUGAR: o id sobrevive, e com ele os vínculos de sessão
    expect(fonte).to match(/mapa = existente \|\| BattleMap\.new/)
  end

  it '⚠️ NENHUM objeto importado nasce escondido por zoom' do
    # Houve aqui uma atribuição automática de `zoomMin` por tamanho, para
    # aliviar os mapas-mundo. O utilizador viu e rejeitou: sumiço automático
    # confunde mais do que o custo que evita. O controlo por objeto continua
    # na interface — o que não pode voltar é o import decidir sozinho.
    expect(cenas.sum { |c| c['tokens'].count { |t| t['zmin'] } }).to eq(0)
    expect(gerador).not_to match(/DETALHE_FAIXAS/)
    expect(fonte).not_to match(/zoomMin/)
  end

  it '⚠️ a máscara da camada é o ALFA — ler a COR dela apaga o terreno inteiro' do
    # O RGB da máscara é preto puro em TODAS as cenas: a informação está só no
    # alfa. `convert("L")` devolvia 0 e sumiu com o continente do "Melee".
    # Máscara de paleta guarda a transparência em bytes, e só o RGBA a resolve.
    expect(gerador).to match(/def _alfa_da_mascara/)
    expect(gerador).to match(/convert\('RGBA'\)\.getchannel\('A'\)/)
    expect(gerador).not_to match(/convert\('L'\)/)
  end

  it '⚠️ a pilha das camadas vem do LOG (atIndex), não da ordem do array' do
    # `sceneLayers` não vem em z: o "Melee" traz [fg, bg], e compor na ordem do
    # array pintava o oceano por cima do continente. O nome também não serve —
    # há cenas com camada de pincel batizada com UUID ou `layer-brush-71`.
    expect(gerador).to match(/def ordem_das_camadas/)
    expect(gerador).to match(/cmd-layer-add/)
    expect(gerador).to match(/atIndex/)
    # a ordem é resolvida uma vez e REUSADA na máscara de terra
    expect(gerador).to match(/ordem = ordem_das_camadas\(cmds\)/)
    expect(gerador).to match(/compoe_fundo\(cena, caminho_fundo, ordem\)/)
  end

  it '⚠️ a silhueta de terra (semente da Ferramenta) só existe quando distingue terra de mar' do
    # máscara 100% opaca (mapa todo terra, "Arredores") viraria moldura na
    # borda; só 1%..99% opaca vira silhueta. Alfa = terra, ≤2048 px.
    expect(gerador).to match(/def salva_mascara_de_terra/)
    expect(gerador).to match(/0\.01 < opaco < 0\.99/)
    expect(fonte).to match(/mapa\.land_mask\.attach/)
    # <img> não manda JWT: a autz da rota é por sig, isenta do authorize_request
    controller = File.read(Rails.root.join('app/controllers/api/v1/player/battle_maps_controller.rb'))
    expect(controller).to match(/skip_before_action :authorize_request, only: %i\[background land_mask\]/)
  end

  it 'objeto sem arte na biblioteca NÃO vira token (seria retângulo vazio)' do
    expect(fonte).to match(/counts\[:token_sem_asset\]/)
    expect(gerador).to match(/resumo\['sem arte no catálogo'\]/)
  end
end
