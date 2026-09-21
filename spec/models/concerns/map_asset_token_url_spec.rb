# frozen_string_literal: true

# A URL do token da biblioteca.
#
# O endpoint da imagem responde com cache IMUTÁVEL, então o `?v=` é o único
# jeito de o navegador largar a arte velha. Com o id do ASSET no `v=` a URL
# nunca muda: o Mestre troca a arte e quem já tinha visto o token continua
# vendo a antiga, sem erro nenhum na tela. Estes testes são a catraca de que o
# `v=` acompanha a IMAGEM.
require 'rails_helper'

RSpec.describe MapAssetTokenUrl do
  let(:asset) { create(:map_asset, kind: 'object', category: 'Meus') }

  def troca_a_arte(asset)
    asset.image.attach(io: StringIO.new("\x89PNG\r\n\x1a\noutra-arte"), filename: 'nova.png',
                       content_type: 'image/png')
    asset.reload
  end

  def consultas
    n = 0
    sub = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      n += 1 unless %w[SCHEMA CACHE].include?(payload[:name])
    end
    yield
    n
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end

  describe '.for (pelo id)' do
    it 'o v= é o id do BLOB — a mesma URL que a biblioteca serve' do
      url = described_class.for(asset.id)

      expect(url).to eq("/api/v1/admin/map_assets/#{asset.id}/image?v=#{asset.image.blob.id}")
      expect(url).to eq(MapAssetSerializer.serialize(asset)[:imageUrl])
    end

    it '⚠️ trocar a arte do asset MUDA a URL (senão o cache imutável serve a velha)' do
      antes = described_class.for(asset.id)
      troca_a_arte(asset)

      expect(described_class.for(asset.id)).not_to eq(antes)
      expect(described_class.for(asset.id)).to end_with("?v=#{asset.image.blob.id}")
    end

    it 'sem asset: nil para id vazio, recuo para o id quando o asset sumiu' do
      expect(described_class.for(nil)).to be_nil
      expect(described_class.for('')).to be_nil
      expect(described_class.for(999_999)).to eq('/api/v1/admin/map_assets/999999/image?v=999999')
    end
  end

  describe '.for_asset (registro já carregado)' do
    it 'com o anexo pré-carregado não consulta o banco' do
      carregado = MapAsset.preload(:image_attachment).find(asset.id)

      url = nil
      expect(consultas { url = described_class.for_asset(carregado.id, carregado) }).to eq(0)
      expect(url).to eq(described_class.for(asset.id))
    end

    it 'asset apagado (associação nil) recua para o id, sem consulta' do
      expect(consultas { described_class.for_asset(42, nil) }).to eq(0)
      expect(described_class.for_asset(42, nil)).to eq('/api/v1/admin/map_assets/42/image?v=42')
      expect(described_class.for_asset(nil, nil)).to be_nil
    end
  end

  # As quatro cópias da linha viraram este módulo; a quinta não pode voltar.
  it 'ninguém mais monta a URL do asset com o id no v=' do
    fontes = Dir[Rails.root.join('app/**/*.rb')].map { |f| [f, File.read(f)] }
    copias = fontes.select { |_, src| src.include?('image?v=#{token_map_asset_id}') }

    expect(copias.map(&:first)).to be_empty
  end
end
