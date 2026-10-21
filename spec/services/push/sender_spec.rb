# frozen_string_literal: true

require 'rails_helper'

# A "fila presa" de prod (21/10): os avisos saíam na hora, mas com a urgência 'normal' o FCM os segurava no
# Android em repouso; e sem timeout um endpoint lento prendia o job por 60 s.
RSpec.describe Push::Sender do
  let(:user) { create(:user) }
  let!(:sub) do
    PushSubscription.create!(user: user, endpoint: 'https://fcm.googleapis.com/fcm/send/abc',
                             p256dh_key: 'p256dh', auth_key: 'auth')
  end

  before do
    allow(described_class).to receive(:vapid_configured?).and_return(true)
  end

  it 'envia com urgência alta e com timeouts' do
    allow(WebPush).to receive(:payload_send)
    expect(described_class.call(user: user, title: 't', body: 'b')).to eq(1)
    expect(WebPush).to have_received(:payload_send)
      .with(hash_including(urgency: 'high', open_timeout: 5, read_timeout: 10))
  end

  it 'um timeout não derruba o envio: conta 0 e mantém a assinatura' do
    allow(WebPush).to receive(:payload_send).and_raise(Net::ReadTimeout)
    expect(described_class.call(user: user, title: 't', body: 'b')).to eq(0)
    expect(PushSubscription.exists?(sub.id)).to be(true)
  end
end
