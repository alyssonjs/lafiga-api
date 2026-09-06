# frozen_string_literal: true

# Dedupe dos objetos que entraram duas vezes na biblioteca.
#
# O risco aqui não é a rake explodir: é ela remover o registro certo do jeito
# errado. Um objeto posicionado num mapa guarda o asset em DUAS referências
# dentro do jsonb (`assetId` e a URL embutida em `customImageUrl`) e em DUAS
# tabelas (`battle_maps` e a vertente por mesa `schedule_battle_maps`). Trocar
# uma e esquecer a outra não quebra nada ruidosamente — deixa o objeto invisível
# no mapa de alguém que está jogando. Estes testes são a catraca do que NÃO pode
# acontecer.
require 'rails_helper'

RSpec.describe 'dedupe de objetos do Inkarnate' do
  RAKE_DEDUPE = Rails.root.join('lib/tasks/inkarnate_objects_dedupe.rake')

  let(:fonte) { File.read(RAKE_DEDUPE) }

  it '⚠️ reaponta o token ANTES de remover — nunca a ordem inversa' do
    reaponta = fonte.index('reapontar_tokens(pid, va.id, url_nova) if aplica')
    destroi  = fonte.index('registro.destroy')

    expect(reaponta).to be < destroi
  end

  it '⚠️ conta as DUAS tabelas de token, não só battle_maps' do
    # a poda antiga só olha `battle_maps`; um objeto que só existe na vertente
    # da sessão seria lido como livre
    expect(fonte).to match(/TABELAS_COM_TOKEN = \{ 'battle_maps' => 'tokens', 'schedule_battle_maps' => 'tokens' \}/)
    expect(fonte).to include("jsonb_array_elements(coalesce(m.#{'#{coluna}'}, '[]'::jsonb))")
  end

  it '⚠️ relê o uso depois de reapontar e preserva o que ainda estiver referenciado' do
    expect(fonte).to match(/if uso_atual\(pid\)\.positive\?/)
    expect(fonte).to match(/counts\[:em_uso_preservado\]/)
    releitura = fonte.index('if uso_atual(pid).positive?')
    destroi = fonte.index('registro.destroy')
    expect(releitura).to be < destroi
  end

  it 'destrutivo exige APPLY=1 — sem ele só conta' do
    expect(fonte).to match(/aplica = ENV\['APPLY'\] == '1'/)
    conta = fonte.index('counts[:removeria]')
    destroi = fonte.index('registro.destroy')
    expect(conta).to be < destroi
    expect(fonte).to match(/unless aplica\n\s+counts\[:removeria\] \+= 1\n/)
  end

  it '⚠️ "maior" é RESOLUÇÃO lida do arquivo, não byte_size' do
    # medido em produção: nos 195 grupos com arquivos diferentes a resolução é
    # idêntica — byte_size só mede compressão, e o "maior" em bytes é a leva
    # antiga, justo a que não tem objeto posicionado
    expect(fonte).to include('download_chunk(0...64)')
    expect(fonte).to include("\\x89PNG")
    expect(fonte).to include('area = (d = px[r[\'blob_id\']]) ? d[0].to_i * d[1].to_i : 0')
    # e não pode chamar conversor de imagem: produção não tem libvips
    expect(fonte).not_to match(/Vips|MiniMagick|ImageProcessing/)
  end

  it '⚠️ o vencedor não REGRIDE de metadado (a sombra da leva antiga não se perde)' do
    expect(fonte).to match(/meta_novo = perdedores\.reduce/)
    expect(fonte).to include('(outro.meta || {}).merge(acc)')
    funde = fonte.index('counts[:metadado_fundido]')
    destroi = fonte.index('registro.destroy')
    expect(funde).to be < destroi
  end

  it 'arte própria do Mestre fica fora — reusa a lista da poda, não redefine' do
    expect(fonte).to include('ma.category NOT IN')
    expect(fonte).to include('CATEGORIAS_DO_MESTRE')
    expect(fonte).not_to match(/CATEGORIAS_DO_MESTRE\s*=/)
  end

  it 'não remove registro cujo blob é compartilhado com outro anexo' do
    # `destroy` purga o arquivo: se outro registro aponta p/ o mesmo blob, a
    # imagem some de quem ficou
    expect(fonte).to match(/counts\[:blob_compartilhado_preservado\]/)
  end
end

# O ponto mais delicado merece teste de COMPORTAMENTO, não de texto: o token é
# reescrito de verdade e o que não é do asset removido continua intacto.
RSpec.describe 'dedupe — reapontamento de token', type: :model do
  before(:all) do
    require 'rake'
    Rails.application.load_tasks unless Rake::Task.task_defined?('inkarnate:objects_dedupe')
  end

  let(:velho) { create(:map_asset, kind: 'object', category: 'Fantasy Regional') }
  let(:novo)  { create(:map_asset, kind: 'object', category: 'Fantasy Regional') }
  let(:alheio) { create(:map_asset, kind: 'object', category: 'Fantasy Regional') }
  let(:url_nova) { "/api/v1/admin/map_assets/#{novo.id}/image?v=#{novo.image.blob.id}" }

  def token(id, asset, url)
    { 'id' => id, 'name' => 'Árvore', 'x' => 1, 'y' => 1, 'size' => 1, 'isObject' => true,
      'imageMode' => 'custom', 'assetId' => asset.id, 'customImageUrl' => url }
  end

  it 'troca assetId E a URL embutida, e não encosta no token de outro asset' do
    mapa = create(:battle_map, tokens: [
                    token('t1', velho, "/api/v1/admin/map_assets/#{velho.id}/image?v=1"),
                    token('t2', alheio, "/api/v1/admin/map_assets/#{alheio.id}/image?v=2"),
                  ])

    reapontar_tokens(velho.id, novo.id, url_nova)

    t1, t2 = mapa.reload.tokens
    expect(t1['assetId']).to eq(novo.id)
    expect(t1['customImageUrl']).to eq(url_nova)
    expect(t2['assetId']).to eq(alheio.id)
    expect(t2['customImageUrl']).to include("/map_assets/#{alheio.id}/image")
  end

  it 'preserva imagem custom que não é do asset removido (data URL não vira link)' do
    mapa = create(:battle_map, tokens: [token('t1', velho, 'data:image/png;base64,AAAA')])

    reapontar_tokens(velho.id, novo.id, url_nova)

    t1 = mapa.reload.tokens.first
    expect(t1['assetId']).to eq(novo.id)
    expect(t1['customImageUrl']).to eq('data:image/png;base64,AAAA')
  end

  it '⚠️ enxerga e reescreve também a vertente da sessão (schedule_battle_maps)' do
    mapa = create(:battle_map)
    vertente = ScheduleBattleMap.create!(
      schedule: create(:schedule), battle_map: mapa,
      tokens: [token('t1', velho, "/api/v1/admin/map_assets/#{velho.id}/image?v=1")],
    )

    expect(uso_atual(velho.id)).to eq(1)
    reapontar_tokens(velho.id, novo.id, url_nova)

    expect(vertente.reload.tokens.first['assetId']).to eq(novo.id)
    expect(vertente.tokens.first['customImageUrl']).to eq(url_nova)
    expect(uso_atual(velho.id)).to eq(0)
  end

  it 'a URL que a rake grava é a mesma que o serializer produz para o vencedor' do
    # se divergirem, o token aponta p/ um path que o front não sabe montar
    expect(url_nova).to eq(MapAssetSerializer.serialize(novo)[:imageUrl])
  end
end
