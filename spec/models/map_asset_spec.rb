# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MapAsset, type: :model do
  let(:user) { create(:user) }

  it 'aceita asset válido com imagem anexada' do
    expect(build(:map_asset, user: user)).to be_valid
  end

  it 'exige name, kind válido e imagem' do
    expect(build(:map_asset, user: user, name: '')).not_to be_valid
    expect(build(:map_asset, user: user, kind: 'invalido')).not_to be_valid

    no_img = build(:map_asset, user: user)
    no_img.image.detach
    no_img.image = nil
    expect(no_img).not_to be_valid
    expect(no_img.errors[:image]).to be_present
  end

  it 'valida formato de color (hex #RRGGBB) e aceita em branco' do
    expect(build(:map_asset, user: user, color: 'verde')).not_to be_valid
    expect(build(:map_asset, user: user, color: '')).to be_valid
    expect(build(:map_asset, user: user, color: '#AABBCC')).to be_valid
  end

  it 'rejeita content-type não-imagem' do
    a = build(:map_asset, user: user)
    a.image.attach(
      io: StringIO.new('not-an-image'),
      filename: 'a.txt',
      content_type: 'text/plain',
    )
    expect(a).not_to be_valid
    expect(a.errors[:image]).to be_present
  end

  it 'scopes enabled/of_kind' do
    t = create(:map_asset, :texture, user: user)
    create(:map_asset, :stamp, user: user, enabled: false)
    expect(MapAsset.enabled.pluck(:id)).to eq([t.id])
    expect(MapAsset.of_kind('stamp').count).to eq(1)
  end
end
