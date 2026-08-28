# frozen_string_literal: true

require 'rails_helper'

# O feed da sessão tem TRÊS canais: Geral (todos), Equipe (jogadores, sem o
# Mestre) e Mestre (rolagens secretas, só ele).
#
# O filtro é SQL, no servidor. Esconder no cliente não esconderia nada — a
# mensagem já teria chegado ao navegador de quem não devia ver.
RSpec.describe 'Feed da sessão — canais', type: :request do
  let(:mestre)   { create(:user) }
  let(:jogadora) { create(:user) }
  let(:colega)   { create(:user) }
  let(:forasteiro) { create(:user) }

  let(:group) { create(:group, name: 'Mesa Canal', dm_user_id: mestre.id) }
  let!(:pc_jogadora) { create(:character, user: jogadora, group: group, name: 'Ana') }
  let!(:pc_colega)   { create(:character, user: colega, group: group, name: 'Beto') }

  let(:schedule) { create(:schedule, group: group) }

  def item!(audience, texto, sched: schedule)
    SessionFeedItem.create!(
      schedule: sched, kind: 'chat', client_id: "c-#{audience}-#{texto.parameterize}-#{sched.id}",
      audience: audience, posted_at: Time.current,
      payload: { 'kind' => 'chat', 'id' => "c-#{audience}", 'text' => texto, 'audience' => audience },
    )
  end

  def textos_para(user)
    get "/api/v1/player/schedules/#{schedule.id}/session_feed_items",
        headers: bearer_headers_for(user), as: :json
    expect(response).to have_http_status(:ok)
    response.parsed_body['items'].map { |i| i['text'] }
  end

  before do
    item!('all', 'geral')
    item!('players', 'plano da equipe')
    item!('dm', 'rolagem secreta')
  end

  it 'a jogadora vê o Geral e a Equipe' do
    expect(textos_para(jogadora)).to match_array(['geral', 'plano da equipe'])
  end

  it 'REGRESSAO: o Mestre NAO recebe o chat da equipe' do
    expect(textos_para(mestre)).not_to include('plano da equipe')
  end

  it 'o Mestre vê o Geral e o proprio caderno secreto' do
    expect(textos_para(mestre)).to match_array(['geral', 'rolagem secreta'])
  end

  it 'REGRESSAO: a jogadora NAO recebe as rolagens secretas do Mestre' do
    expect(textos_para(jogadora)).not_to include('rolagem secreta')
  end

  it 'quem nao e da mesa so ve o Geral' do
    expect(textos_para(forasteiro)).to eq(['geral'])
  end

  it 'REGRESSAO: o chat NAO recomeça do zero na sessao seguinte' do
    anterior = create(:schedule, group: group, status: :completed)
    item!('all', 'combinado da sessao passada', sched: anterior)
    item!('players', 'plano antigo da equipe', sched: anterior)

    textos = textos_para(jogadora)

    expect(textos).to include('combinado da sessao passada')
    expect(textos).to include('plano antigo da equipe')
  end

  it 'a herança respeita o canal: o Mestre nao herda a equipe da sessao passada' do
    anterior = create(:schedule, group: group, status: :completed)
    item!('players', 'plano antigo da equipe', sched: anterior)

    expect(textos_para(mestre)).not_to include('plano antigo da equipe')
  end

  it 'REGRESSAO: sessao de OUTRA mesa nao vaza para esta' do
    outra = create(:schedule, group: create(:group, name: 'Outra Mesa'))
    item!('all', 'assunto alheio', sched: outra)

    expect(textos_para(jogadora)).not_to include('assunto alheio')
  end
end

RSpec.describe SessionFeed::Audience do
  let(:mestre) { create(:user) }
  let(:jogadora) { create(:user) }
  let(:group) { create(:group, name: 'Mesa Audience', dm_user_id: mestre.id) }
  let!(:pc) { create(:character, user: jogadora, group: group) }
  let(:schedule) { create(:schedule, group: group) }

  it 'o Mestre da mesa nao e da equipe, mesmo tendo personagem nela' do
    create(:character, user: mestre, group: group, name: 'PC do Mestre')

    expect(described_class.team_member?(schedule, mestre)).to be(false)
    expect(described_class.table_dm?(schedule, mestre)).to be(true)
  end

  it 'REGRESSAO: papel de DM nao tira ninguem da equipe de OUTRA mesa' do
    # A EQUIPE continua a ser por mesa (`groups.dm_user_id`): quem tem papel de
    # DM e joga na mesa dos outros continua no chat da equipe dela.
    papel_dm = create(:role, name: 'DM') rescue Role.find_or_create_by!(name: 'DM')
    convidado = create(:user, role: papel_dm)
    create(:character, user: convidado, group: group, name: 'Convidado')

    expect(described_class.team_member?(schedule, convidado)).to be(true)
    expect(described_class.readable(schedule, convidado)).to include('players')
  end

  it 'quem tem PAPEL de Mestre le o caderno secreto de qualquer mesa' do
    # Bug de prod (sessao 79): o Mestre conduzia a sessao de uma mesa criada
    # por outra pessoa — entrava com todas as ferramentas de Mestre (mapa,
    # fichas e combate autorizam pelo PAPEL) e a aba Mestre do chat sumia,
    # porque so o feed exigia `groups.dm_user_id`.
    papel_dm = create(:role, name: 'DM') rescue Role.find_or_create_by!(name: 'DM')
    outro_mestre = create(:user, role: papel_dm)

    expect(described_class.table_dm?(schedule, outro_mestre)).to be(true)
    expect(described_class.readable(schedule, outro_mestre)).to include('dm')
    expect(described_class.may_write?(schedule, outro_mestre, 'dm')).to be(true)
  end

  it 'o dono da mesa mantem o caderno mesmo sem papel de DM' do
    # `dm_user_id` segue valendo como segundo caminho.
    expect(Group.user_is_dm?(mestre)).to be(false)
    expect(described_class.table_dm?(schedule, mestre)).to be(true)
  end

  it 'REGRESSAO: jogador sem papel de Mestre continua fora do caderno secreto' do
    expect(described_class.readable(schedule, jogadora)).not_to include('dm')
    expect(described_class.may_write?(schedule, jogadora, 'dm')).to be(false)
  end

  it 'escrever num canal exige poder le-lo' do
    expect(described_class.may_write?(schedule, jogadora, 'players')).to be(true)
    expect(described_class.may_write?(schedule, jogadora, 'dm')).to be(false)
    expect(described_class.may_write?(schedule, mestre, 'players')).to be(false)
    expect(described_class.may_write?(schedule, mestre, 'dm')).to be(true)
  end

  it 'sessao sem grupo nao tem equipe nem caderno' do
    # `Schedule` exige grupo na prática; a guarda existe para o caminho em que
    # a associação não resolve (sessão avulsa/sandbox). Testada sem gravar.
    solta = Schedule.new(group: nil)

    expect(described_class.readable(solta, jogadora)).to eq(['all'])
    expect(described_class.team_member?(solta, jogadora)).to be(false)
  end
end
