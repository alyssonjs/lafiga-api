# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SessionFeedChannel, type: :channel do
  let(:dm_role)     { Role.find_or_create_by!(name: 'DM') }
  let(:player_role) { Role.find_or_create_by!(name: 'Player') }

  let(:dm)        { create(:user, role: dm_role) }
  let(:player)    { create(:user, role: player_role) }
  let(:outsider)  { create(:user, role: player_role) }

  let(:schedule)  { create(:schedule) }
  let!(:player_character) { create(:character, user: player, group: schedule.group) }

  def token_for(user) = JsonWebToken.encode(user_id: user.id)

  let(:valid_chat) do
    {
      'kind' => 'chat',
      'id' => 'msg-1',
      'timestamp' => 1_700_000_000_000,
      'sessionId' => schedule.id.to_s,
      'senderName' => 'Alice',
      'senderRole' => 'player',
      'text' => 'Olá',
    }
  end

  let(:valid_roll) do
    {
      'kind' => 'roll',
      'id' => 'roll-1',
      'timestamp' => 1_700_000_000_001,
      'sessionId' => schedule.id.to_s,
      'playerName' => 'Alice',
      'characterName' => 'PC',
      'type' => 'attack',
      'label' => 'Espada',
      'total' => 18,
      'breakdown' => '1d20+4',
    }
  end

  it 'subscribes a member of the group to the feed stream' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from("session_feed_#{schedule.id}")
  end

  it 'subscribes when schedule_id uses api-NN UI prefix (same as GameSession URL id)' do
    subscribe(token: token_for(player), schedule_id: "api-#{schedule.id}")
    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from("session_feed_#{schedule.id}")
  end

  it 'subscribes the DM (site-wide)' do
    subscribe(token: token_for(dm), schedule_id: schedule.id)
    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from("session_feed_#{schedule.id}")
  end

  it 'subscribes an outsider (hub read — mirrors SessionRealtimeChannel)' do
    subscribe(token: token_for(outsider), schedule_id: schedule.id)
    expect(subscription).to be_confirmed
  end

  it 'rejects when the schedule does not exist' do
    subscribe(token: token_for(player), schedule_id: 999_999)
    expect(subscription).to be_rejected
  end

  it 'rejects when the JWT is missing' do
    subscribe(token: '', schedule_id: schedule.id)
    expect(subscription).to be_rejected
  end

  it 'rejects when the JWT is blacklisted' do
    token = token_for(player)
    ValidateJwtToken.create!(token: token)
    subscribe(token: token, schedule_id: schedule.id)
    expect(subscription).to be_rejected
  end

  it 'broadcasts a normalized chat item on feed_item' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    expect do
      perform :feed_item, item: valid_chat
    end.to have_broadcasted_to("session_feed_#{schedule.id}").with(
      a_hash_including('kind' => 'chat', 'text' => 'Olá', 'sessionId' => schedule.id.to_s),
    )
  end

  it 'broadcasts chat with cardAccentColor when valid hex' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    chat = valid_chat.merge('cardAccentColor' => '#9b59b6')
    expect do
      perform :feed_item, item: chat
    end.to have_broadcasted_to("session_feed_#{schedule.id}").with(
      a_hash_including('kind' => 'chat', 'cardAccentColor' => '#9b59b6'),
    )
  end

  it 'strips invalid cardAccentColor from chat' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    chat = valid_chat.merge('cardAccentColor' => 'javascript:alert(1)')
    expect do
      perform :feed_item, item: chat
    end.to have_broadcasted_to("session_feed_#{schedule.id}").with(
      satisfy { |p| p['kind'] == 'chat' && p['text'] == 'Olá' && !p.key?('cardAccentColor') },
    )
  end

  it 'broadcasts a normalized roll item on feed_item' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    expect do
      perform :feed_item, item: valid_roll
    end.to have_broadcasted_to("session_feed_#{schedule.id}").with(
      a_hash_including('kind' => 'roll', 'total' => 18),
    )
  end

  it 'preserva revealAt curto para persistir o resultado antes da animação terminar' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    roll = valid_roll.merge('revealAt' => valid_roll['timestamp'] + 1_650)

    expect do
      perform :feed_item, item: roll
    end.to have_broadcasted_to("session_feed_#{schedule.id}").with(
      a_hash_including('kind' => 'roll', 'revealAt' => valid_roll['timestamp'] + 1_650),
    )

    expect(SessionFeedItem.find_by!(schedule: schedule, client_id: 'roll-1').payload['revealAt'])
      .to eq(valid_roll['timestamp'] + 1_650)
  end

  it 'preserva savePrompt em roll type save (card de prompt de TR, substitui o modal)' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    save_roll = valid_roll.merge(
      'type' => 'save',
      'total' => 0,
      'label' => 'Niva → Gargula · TR CON CD 15',
      'savePrompt' => { 'dc' => 15, 'ability' => 'con', 'targetName' => 'Gargula', 'sourceName' => 'Niva', 'mode' => 'apply-on-fail' },
    )
    expect do
      perform :feed_item, item: save_roll
    end.to have_broadcasted_to("session_feed_#{schedule.id}").with(
      a_hash_including(
        'kind' => 'roll',
        'type' => 'save',
        'savePrompt' => a_hash_including('dc' => 15, 'ability' => 'con', 'targetName' => 'Gargula', 'mode' => 'apply-on-fail'),
      ),
    )
  end

  it 'ignora savePrompt com dc inválido / mode fora do whitelist' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    save_roll = valid_roll.merge(
      'type' => 'save', 'total' => 0,
      'savePrompt' => { 'dc' => 'xx', 'ability' => 'con', 'targetName' => 'Gargula', 'mode' => 'hack' },
    )
    expect do
      perform :feed_item, item: save_roll
    end.to have_broadcasted_to("session_feed_#{schedule.id}").with(
      satisfy { |p| p['kind'] == 'roll' && !p.key?('savePrompt') },
    )
  end

  it 'preserva damageLines (quebra por tipo) numa rolagem de dano — card per-tipo cross-device' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    dmg_roll = valid_roll.merge(
      'type' => 'damage',
      'label' => 'Niva → Gnaels · dano Mangual',
      'total' => 12,
      'breakdown' => 'd8[4]+3 + (1d8 fogo)[5]',
      'damageType' => 'concussao',
      'damageLines' => [
        { 'type' => 'concussao', 'raw' => 7, 'final' => 7, 'mult' => 1 },
        { 'type' => 'fogo', 'raw' => 5, 'final' => 5, 'mult' => 1 },
      ],
    )
    expect do
      perform :feed_item, item: dmg_roll
    end.to have_broadcasted_to("session_feed_#{schedule.id}").with(
      a_hash_including(
        'kind' => 'roll',
        'type' => 'damage',
        'damageLines' => [
          a_hash_including('type' => 'concussao', 'raw' => 7, 'final' => 7),
          a_hash_including('type' => 'fogo', 'raw' => 5, 'final' => 5),
        ],
      ),
    )
  end

  it 'não anexa damageLines em rolagem que não seja de dano' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    atk = valid_roll.merge(
      'type' => 'attack',
      'damageLines' => [{ 'type' => 'fogo', 'raw' => 5, 'final' => 5, 'mult' => 1 }],
    )
    expect do
      perform :feed_item, item: atk
    end.to have_broadcasted_to("session_feed_#{schedule.id}").with(
      satisfy { |p| p['kind'] == 'roll' && !p.key?('damageLines') },
    )
  end

  it 'relaya damage_mitigation com lines pós-mitigação (Fúria: concussão ÷2, fogo intacto)' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    mit = {
      'kind' => 'damage_mitigation',
      'id' => 'dmit-1',
      'timestamp' => 1_700_000_000_002,
      'sessionId' => schedule.id.to_s,
      'rollGroupId' => 'dmg-abc',
      'mitigatedTotal' => 8,
      'tag' => 'RESISTÊNCIA',
      'lines' => [
        { 'type' => 'concussao', 'raw' => 7, 'final' => 3, 'mult' => 0.5 },
        { 'type' => 'fogo', 'raw' => 5, 'final' => 5, 'mult' => 1 },
      ],
    }
    expect do
      perform :feed_item, item: mit
    end.to have_broadcasted_to("session_feed_#{schedule.id}").with(
      a_hash_including(
        'kind' => 'damage_mitigation',
        'rollGroupId' => 'dmg-abc',
        'mitigatedTotal' => 8,
        'tag' => 'RESISTÊNCIA',
        'lines' => [
          a_hash_including('type' => 'concussao', 'raw' => 7, 'final' => 3, 'mult' => 0.5),
          a_hash_including('type' => 'fogo', 'raw' => 5, 'final' => 5, 'mult' => 1.0),
        ],
      ),
    )
  end

  it 'relaya roll_total_adjusted (Inspiração Bárdica somada depois do d20)' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    adj = {
      'kind' => 'roll_total_adjusted',
      'id' => 'radj-1',
      'timestamp' => 1_700_000_000_010,
      'sessionId' => schedule.id.to_s,
      'rollGroupId' => 'rg-abc',
      'adjustedTotal' => 17,
      'adjustedBreakdown' => '(1d20) 9 + (3) 3 = 12 + (Inspiração d6) 5 = 17',
      'tag' => 'INSPIRAÇÃO d6',
    }
    expect do
      perform :feed_item, item: adj
    end.to have_broadcasted_to("session_feed_#{schedule.id}").with(
      a_hash_including(
        'kind' => 'roll_total_adjusted',
        'rollGroupId' => 'rg-abc',
        'adjustedTotal' => 17,
        'tag' => 'INSPIRAÇÃO d6',
      ),
    )
  end

  it 'descarta roll_total_adjusted sem rollGroupId ou com total não numérico' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    base = {
      'kind' => 'roll_total_adjusted',
      'id' => 'radj-2',
      'timestamp' => 1_700_000_000_011,
      'sessionId' => schedule.id.to_s,
      'adjustedTotal' => 17,
    }
    expect { perform :feed_item, item: base }
      .not_to have_broadcasted_to("session_feed_#{schedule.id}")
    expect { perform :feed_item, item: base.merge('rollGroupId' => 'rg-x', 'adjustedTotal' => 'muito') }
      .not_to have_broadcasted_to("session_feed_#{schedule.id}")
  end

  it 'saneia damage_mitigation: mult fora de {0,0.5,1,2} vira 1 e linha malformada é descartada' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    mit = {
      'kind' => 'damage_mitigation',
      'id' => 'dmit-2',
      'timestamp' => 1_700_000_000_003,
      'sessionId' => schedule.id.to_s,
      'rollGroupId' => 'dmg-xyz',
      'mitigatedTotal' => 4,
      'tag' => 'RESISTÊNCIA',
      'lines' => [
        { 'type' => 'fogo', 'raw' => 5, 'final' => 5, 'mult' => 3 }, # mult inválido → 1.0
        { 'raw' => 2, 'final' => 2, 'mult' => 1 },                    # sem type → descartada
      ],
    }
    expect do
      perform :feed_item, item: mit
    end.to have_broadcasted_to("session_feed_#{schedule.id}").with(
      satisfy do |p|
        p['kind'] == 'damage_mitigation' &&
          p['lines'] == [{ 'type' => 'fogo', 'raw' => 5, 'final' => 5, 'mult' => 1.0 }]
      end,
    )
  end

  it 'descarta damage_mitigation sem rollGroupId' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    mit = {
      'kind' => 'damage_mitigation', 'id' => 'dmit-3',
      'timestamp' => 1_700_000_000_004, 'sessionId' => schedule.id.to_s,
      'mitigatedTotal' => 8, 'tag' => 'RESISTÊNCIA',
    }
    expect do
      perform :feed_item, item: mit
    end.not_to have_broadcasted_to("session_feed_#{schedule.id}")
  end

  it 'broadcasts chat with sticker data URL (tiny png)' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    png_b64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='
    data_url = "data:image/png;base64,#{png_b64}"
    sticker_chat = {
      'kind' => 'chat',
      'id' => 'msg-sticker-data',
      'timestamp' => 1_700_000_000_004,
      'sessionId' => schedule.id.to_s,
      'senderName' => 'Alice',
      'senderRole' => 'player',
      'text' => '',
      'stickerUrl' => data_url,
    }
    expect do
      perform :feed_item, item: sticker_chat
    end.to have_broadcasted_to("session_feed_#{schedule.id}").with(
      a_hash_including('kind' => 'chat', 'stickerUrl' => data_url, 'text' => ''),
    )
  end

  it 'does not broadcast chat when sticker data URL is not a real image' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    fake_png = Base64.strict_encode64('not-a-real-png-bytes!!')
    sticker_chat = {
      'kind' => 'chat',
      'id' => 'msg-sticker-bad',
      'timestamp' => 1_700_000_000_005,
      'sessionId' => schedule.id.to_s,
      'senderName' => 'Alice',
      'senderRole' => 'player',
      'text' => '',
      'stickerUrl' => "data:image/png;base64,#{fake_png}",
    }
    expect do
      perform :feed_item, item: sticker_chat
    end.not_to have_broadcasted_to("session_feed_#{schedule.id}")
  end

  it 'broadcasts chat with gif and empty text' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    gif_chat = {
      'kind' => 'chat',
      'id' => 'msg-gif',
      'timestamp' => 1_700_000_000_003,
      'sessionId' => schedule.id.to_s,
      'senderName' => 'Alice',
      'senderRole' => 'player',
      'text' => '',
      'gifUrl' => 'https://media.tenor.com/abc123/example.gif',
    }
    expect do
      perform :feed_item, item: gif_chat
    end.to have_broadcasted_to("session_feed_#{schedule.id}").with(
      a_hash_including('kind' => 'chat', 'gifUrl' => 'https://media.tenor.com/abc123/example.gif', 'text' => ''),
    )
  end

  it 'broadcasts roll_pending for suspense phase' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    pending = {
      'kind' => 'roll_pending',
      'id' => 'roll-pending-rg1',
      'rollGroupId' => 'rg-1',
      'timestamp' => 1_700_000_000_002,
      'sessionId' => schedule.id.to_s,
      'playerName' => 'Mestre',
      'characterName' => 'Grog',
      'type' => 'skill',
      'label' => 'Intimidacao',
    }
    expect do
      perform :feed_item, item: pending
    end.to have_broadcasted_to("session_feed_#{schedule.id}").with(
      a_hash_including('kind' => 'roll_pending', 'rollGroupId' => 'rg-1', 'label' => 'Intimidacao'),
    )
  end

  it 'broadcasts attack rolls with attackHitOutcome so the DM sees pending via ActionCable' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    roll = valid_roll.merge(
      'rollGroupId' => 'rg-atk-1',
      'attackHitOutcome' => 'pending',
      'targetAC' => 17,
      'targetTokenId' => 'tok-target',
      'attackerTokenId' => 'tok-attacker',
      'projectile' => { 'id' => 'projectile-arrow', 'kind' => 'arrow', 'itemName' => 'Flecha' },
    )
    expect do
      perform :feed_item, item: roll
    end.to have_broadcasted_to("session_feed_#{schedule.id}").with(
      a_hash_including(
        'kind' => 'roll',
        'type' => 'attack',
        'rollGroupId' => 'rg-atk-1',
        'attackHitOutcome' => 'pending',
        'targetAC' => 17,
        'targetTokenId' => 'tok-target',
        'attackerTokenId' => 'tok-attacker',
        'projectile' => a_hash_including('id' => 'projectile-arrow', 'kind' => 'arrow'),
      ),
    )
  end

  it 'broadcasts attack_hit_resolution from the DM to all clients' do
    SessionFeed::Persist.call(
      schedule_id: schedule.id,
      normalized: valid_roll.merge('rollGroupId' => 'rg-atk-1', 'attackHitOutcome' => 'pending'),
    )
    subscribe(token: token_for(dm), schedule_id: schedule.id)
    resolution = {
      'kind' => 'attack_hit_resolution',
      'id' => 'ahr-1',
      'timestamp' => 1_700_000_000_006,
      'sessionId' => schedule.id.to_s,
      'rollGroupId' => 'rg-atk-1',
      'outcome' => 'hit',
    }
    expect do
      perform :feed_item, item: resolution
    end.to have_broadcasted_to("session_feed_#{schedule.id}").with(
      a_hash_including(
        'kind' => 'attack_hit_resolution',
        'rollGroupId' => 'rg-atk-1',
        'outcome' => 'hit',
      ),
    )
  end

  it 'relaya dodge target/attacker no ERRO (miss)' do
    SessionFeed::Persist.call(
      schedule_id: schedule.id,
      normalized: valid_roll.merge('id' => 'roll-atk-2', 'rollGroupId' => 'rg-atk-2', 'attackHitOutcome' => 'pending'),
    )
    subscribe(token: token_for(dm), schedule_id: schedule.id)
    resolution = {
      'kind' => 'attack_hit_resolution', 'id' => 'ahr-2', 'timestamp' => 1_700_000_000_007,
      'sessionId' => schedule.id.to_s, 'rollGroupId' => 'rg-atk-2', 'outcome' => 'miss',
      'dodgeTargetTokenId' => 'tok-alvo', 'dodgeAttackerTokenId' => 'tok-atk',
    }
    expect do
      perform :feed_item, item: resolution
    end.to have_broadcasted_to("session_feed_#{schedule.id}").with(
      a_hash_including('dodgeTargetTokenId' => 'tok-alvo', 'dodgeAttackerTokenId' => 'tok-atk'),
    )
  end

  it 'descarta dodge target/attacker no ACERTO (hit)' do
    SessionFeed::Persist.call(
      schedule_id: schedule.id,
      normalized: valid_roll.merge('id' => 'roll-atk-3', 'rollGroupId' => 'rg-atk-3', 'attackHitOutcome' => 'pending'),
    )
    subscribe(token: token_for(dm), schedule_id: schedule.id)
    resolution = {
      'kind' => 'attack_hit_resolution', 'id' => 'ahr-3', 'timestamp' => 1_700_000_000_008,
      'sessionId' => schedule.id.to_s, 'rollGroupId' => 'rg-atk-3', 'outcome' => 'hit',
      'dodgeTargetTokenId' => 'tok-alvo', 'dodgeAttackerTokenId' => 'tok-atk',
    }
    expect do
      perform :feed_item, item: resolution
    end.to have_broadcasted_to("session_feed_#{schedule.id}").with(
      satisfy { |p| p['outcome'] == 'hit' && !p.key?('dodgeTargetTokenId') && !p.key?('dodgeAttackerTokenId') },
    )
  end


  it 'rejeita confirmacao de acerto enviada por jogador' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    resolution = {
      'kind' => 'attack_hit_resolution', 'id' => 'ahr-player', 'timestamp' => 1_700_000_000_009,
      'sessionId' => schedule.id.to_s, 'rollGroupId' => 'rg-player', 'outcome' => 'hit',
    }

    expect do
      perform :feed_item, item: resolution
    end.not_to have_broadcasted_to("session_feed_#{schedule.id}")
  end

  %w[hit miss].each do |outcome|
    it "resolve projectile on #{outcome} by roll group before broadcasting" do
      battle_map = create(:battle_map, user: dm)
      schedule.update!(battle_map: battle_map)
      allow(BattleMapProjectiles).to receive(:resolve!).and_return(
        'id' => 'projectile-arrow', 'kind' => 'arrow', 'state' => 'landed', 'outcome' => outcome
      )
      SessionFeed::Persist.call(
        schedule_id: schedule.id,
        normalized: valid_roll.merge('id' => "roll-arrow-#{outcome}", 'rollGroupId' => 'rg-arrow', 'attackHitOutcome' => 'pending'),
      )
      subscribe(token: token_for(dm), schedule_id: schedule.id)
      resolution = {
        'kind' => 'attack_hit_resolution', 'id' => "ahr-arrow-#{outcome}",
        'timestamp' => 1_700_000_000_010, 'sessionId' => schedule.id.to_s,
        'rollGroupId' => 'rg-arrow', 'projectileId' => 'projectile-arrow', 'outcome' => outcome,
      }

      expect do
        perform :feed_item, item: resolution
      end.to have_broadcasted_to("session_feed_#{schedule.id}").with(
        a_hash_including('projectileId' => 'projectile-arrow', 'outcome' => outcome),
      )
      expect(BattleMapProjectiles).to have_received(:resolve!).with(
        map: battle_map,
        user: dm,
        projectile_id: 'projectile-arrow',
        roll_group_id: 'rg-arrow',
        outcome: outcome,
      )
    end
  end

  it 'relaya save_prompt_resolved para todos os clientes (resolução de TR)' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    item = {
      'kind' => 'save_prompt_resolved',
      'id' => 'spr-1',
      'timestamp' => 1_700_000_000_009,
      'sessionId' => schedule.id.to_s,
      'rollGroupId' => 'rg-tr-1',
    }
    expect do
      perform :feed_item, item: item
    end.to have_broadcasted_to("session_feed_#{schedule.id}").with(
      a_hash_including('kind' => 'save_prompt_resolved', 'rollGroupId' => 'rg-tr-1'),
    )
  end

  it 'descarta save_prompt_resolved sem rollGroupId' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    item = {
      'kind' => 'save_prompt_resolved', 'id' => 'spr-2',
      'timestamp' => 1_700_000_000_010, 'sessionId' => schedule.id.to_s,
    }
    expect do
      perform :feed_item, item: item
    end.not_to have_broadcasted_to("session_feed_#{schedule.id}")
  end

  it 'relaya aoe_preview (move) recomputável com sender_id autoritativo' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    item = {
      'kind' => 'aoe_preview', 'id' => 'aoep-1', 'timestamp' => 1_700_000_000_011,
      'sessionId' => schedule.id.to_s, 'casterId' => 'tok-bb', 'phase' => 'move',
      'shape' => 'sphere', 'sizeFt' => 30, 'originCol' => 9, 'originRow' => 5,
      'dirCol' => 9, 'dirRow' => 5, 'color' => '#C93B3B', 'spellName' => 'Bola de Fogo',
      'clientId' => 'cli-abc123',
    }
    expect do
      perform :feed_item, item: item
    end.to have_broadcasted_to("session_feed_#{schedule.id}").with(
      a_hash_including(
        'kind' => 'aoe_preview', 'casterId' => 'tok-bb', 'shape' => 'sphere',
        'originCol' => 9, 'phase' => 'move', 'senderId' => player.id.to_s,
        'clientId' => 'cli-abc123',
      ),
    )
  end

  it 'relaya aoe_preview (end) só com casterId p/ limpar o fantasma' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    item = {
      'kind' => 'aoe_preview', 'id' => 'aoep-2', 'timestamp' => 1_700_000_000_012,
      'sessionId' => schedule.id.to_s, 'casterId' => 'tok-bb', 'phase' => 'end',
    }
    expect do
      perform :feed_item, item: item
    end.to have_broadcasted_to("session_feed_#{schedule.id}").with(
      a_hash_including('kind' => 'aoe_preview', 'casterId' => 'tok-bb', 'phase' => 'end'),
    )
  end

  it 'descarta aoe_preview (move) com forma inválida' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    item = {
      'kind' => 'aoe_preview', 'id' => 'aoep-3', 'timestamp' => 1_700_000_000_013,
      'sessionId' => schedule.id.to_s, 'casterId' => 'tok-bb', 'phase' => 'move',
      'shape' => 'triangulo', 'sizeFt' => 30, 'originCol' => 1, 'originRow' => 1,
    }
    expect do
      perform :feed_item, item: item
    end.not_to have_broadcasted_to("session_feed_#{schedule.id}")
  end

  it 'relaya oa_threat (move) com célula viva + ids de ameaça + clientId' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    item = {
      'kind' => 'oa_threat', 'id' => 'oat-1', 'timestamp' => 1_700_000_000_020,
      'sessionId' => schedule.id.to_s, 'draggedTokenId' => 'tok-mover', 'phase' => 'move',
      'dragCol' => 7, 'dragRow' => 4, 'dragDistanceFt' => 15.0, 'threatTokenIds' => %w[tok-e1 tok-e2],
      'clientId' => 'cli-xyz',
    }
    expect do
      perform :feed_item, item: item
    end.to have_broadcasted_to("session_feed_#{schedule.id}").with(
      a_hash_including(
        'kind' => 'oa_threat', 'draggedTokenId' => 'tok-mover', 'dragCol' => 7,
        'phase' => 'move', 'threatTokenIds' => %w[tok-e1 tok-e2], 'dragDistanceFt' => 15.0,
        'senderId' => player.id.to_s, 'clientId' => 'cli-xyz',
      ),
    )
  end

  it 'relaya oa_threat (end) só com draggedTokenId p/ limpar as setas' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    item = {
      'kind' => 'oa_threat', 'id' => 'oat-2', 'timestamp' => 1_700_000_000_021,
      'sessionId' => schedule.id.to_s, 'draggedTokenId' => 'tok-mover', 'phase' => 'end',
    }
    expect do
      perform :feed_item, item: item
    end.to have_broadcasted_to("session_feed_#{schedule.id}").with(
      a_hash_including('kind' => 'oa_threat', 'draggedTokenId' => 'tok-mover', 'phase' => 'end'),
    )
  end

  it 'descarta oa_threat sem draggedTokenId' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    item = {
      'kind' => 'oa_threat', 'id' => 'oat-3', 'timestamp' => 1_700_000_000_022,
      'sessionId' => schedule.id.to_s, 'phase' => 'move', 'dragCol' => 1, 'dragRow' => 1,
    }
    expect do
      perform :feed_item, item: item
    end.not_to have_broadcasted_to("session_feed_#{schedule.id}")
  end

  it 'relaya spell_fx (FX de área) com elemento/forma/bounds + sender_id autoritativo' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    item = {
      'kind' => 'spell_fx', 'id' => 'sfx-1', 'timestamp' => 1_700_000_000_030,
      'sessionId' => schedule.id.to_s, 'element' => 'fire', 'shape' => 'circle',
      'col' => 12, 'row' => 8, 'cells' => 4, 'direction' => 0,
      'bounds' => { 'minCol' => 8, 'minRow' => 4, 'maxCol' => 16, 'maxRow' => 12 },
      'clientId' => 'cli-xyz',
    }
    expect do
      perform :feed_item, item: item
    end.to have_broadcasted_to("session_feed_#{schedule.id}").with(
      a_hash_including(
        'kind' => 'spell_fx', 'element' => 'fire', 'shape' => 'circle',
        'col' => 12, 'row' => 8, 'cells' => 4.0, 'senderId' => player.id.to_s,
        'clientId' => 'cli-xyz',
        'bounds' => a_hash_including('minCol' => 8, 'maxRow' => 12),
      ),
    )
  end

  it 'descarta spell_fx com elemento OU forma inválidos' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    bad_element = {
      'kind' => 'spell_fx', 'id' => 'sfx-2', 'timestamp' => 1_700_000_000_031,
      'sessionId' => schedule.id.to_s, 'element' => 'plasma', 'shape' => 'circle',
      'col' => 1, 'row' => 1, 'cells' => 3,
    }
    bad_shape = bad_element.merge('id' => 'sfx-3', 'element' => 'fire', 'shape' => 'blob')
    expect do
      perform :feed_item, item: bad_element
      perform :feed_item, item: bad_shape
    end.not_to have_broadcasted_to("session_feed_#{schedule.id}")
  end

  it 'does not broadcast junk kind' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    expect do
      perform :feed_item, item: { 'kind' => 'system', 'text' => 'x' }
    end.not_to have_broadcasted_to("session_feed_#{schedule.id}")
  end

  it 'does not broadcast when rate limited' do
    subscribe(token: token_for(player), schedule_id: schedule.id)
    allow(SessionFeed::RateLimit).to receive(:allow?).and_return(false)
    expect do
      perform :feed_item, item: valid_chat
    end.not_to have_broadcasted_to("session_feed_#{schedule.id}")
  end

  describe 'floating_fx (números de dano flutuantes, efêmero)' do
    let(:valid_fx) do
      {
        'kind' => 'floating_fx',
        'id' => 'fx-1',
        'timestamp' => 1_700_000_000_010,
        'sessionId' => schedule.id.to_s,
        'tokenId' => 'token-abc',
        'floats' => [{ 'type' => 'cortante', 'value' => 3 }, { 'type' => 'fogo', 'value' => 5 }],
        'fxKind' => 'damage',
        'durationMs' => 1_200,
      }
    end

    it 'relaya o FX normalizado a todos os subscribers' do
      subscribe(token: token_for(player), schedule_id: schedule.id)
      expect do
        perform :feed_item, item: valid_fx
      end.to have_broadcasted_to("session_feed_#{schedule.id}").with(
        a_hash_including(
          'kind' => 'floating_fx',
          'tokenId' => 'token-abc',
          'floats' => [{ 'type' => 'cortante', 'value' => 3 }, { 'type' => 'fogo', 'value' => 5 }],
          'fxKind' => 'damage',
        ),
      )
    end

    it 'coage value para inteiro e limita a quantidade de floats' do
      subscribe(token: token_for(player), schedule_id: schedule.id)
      many = (1..20).map { |i| { 'type' => 'fogo', 'value' => "#{i}" } }
      fx = valid_fx.merge('floats' => many)
      expect do
        perform :feed_item, item: fx
      end.to have_broadcasted_to("session_feed_#{schedule.id}").with(
        satisfy do |p|
          p['kind'] == 'floating_fx' &&
            p['floats'].length == SessionFeedChannel::MAX_FX_FLOATS &&
            p['floats'].all? { |f| f['value'].is_a?(Integer) }
        end,
      )
    end

    it 'não relaya quando floats está vazio' do
      subscribe(token: token_for(player), schedule_id: schedule.id)
      expect do
        perform :feed_item, item: valid_fx.merge('floats' => [])
      end.not_to have_broadcasted_to("session_feed_#{schedule.id}")
    end

    it 'não relaya quando falta tokenId' do
      subscribe(token: token_for(player), schedule_id: schedule.id)
      expect do
        perform :feed_item, item: valid_fx.merge('tokenId' => '')
      end.not_to have_broadcasted_to("session_feed_#{schedule.id}")
    end

    it 'faz clamp de durationMs fora do limite e default de fxKind inválido' do
      subscribe(token: token_for(player), schedule_id: schedule.id)
      fx = valid_fx.merge('durationMs' => 999_999, 'fxKind' => 'explode')
      expect do
        perform :feed_item, item: fx
      end.to have_broadcasted_to("session_feed_#{schedule.id}").with(
        a_hash_including('durationMs' => SessionFeedChannel::DEFAULT_FX_DURATION_MS, 'fxKind' => 'damage'),
      )
    end

    it 'NÃO persiste (efêmero, fora de SessionFeedItem::KINDS)' do
      subscribe(token: token_for(player), schedule_id: schedule.id)
      expect { perform :feed_item, item: valid_fx }
        .not_to change(SessionFeedItem, :count)
    end

    it 'relaya attackFx (FX de ataque melee) quando o par de tokenIds é válido' do
      subscribe(token: token_for(player), schedule_id: schedule.id)
      fx = valid_fx.merge('attackFx' => { 'attackerTokenId' => 'tok-atk', 'targetTokenId' => 'tok-alvo' })
      expect do
        perform :feed_item, item: fx
      end.to have_broadcasted_to("session_feed_#{schedule.id}").with(
        a_hash_including(
          'attackFx' => { 'attackerTokenId' => 'tok-atk', 'targetTokenId' => 'tok-alvo' },
        ),
      )
    end

    it 'descarta attackFx incompleto (sem attackerTokenId) mas relaya o resto' do
      subscribe(token: token_for(player), schedule_id: schedule.id)
      fx = valid_fx.merge('attackFx' => { 'targetTokenId' => 'tok-alvo' })
      expect do
        perform :feed_item, item: fx
      end.to have_broadcasted_to("session_feed_#{schedule.id}").with(
        satisfy { |p| p['kind'] == 'floating_fx' && !p.key?('attackFx') },
      )
    end
  end

  describe 'persistência (SessionFeed::Persist)' do
    it 'cria SessionFeedItem para chat válido' do
      subscribe(token: token_for(player), schedule_id: schedule.id)
      expect { perform :feed_item, item: valid_chat }
        .to change(SessionFeedItem, :count).by(1)

      item = SessionFeedItem.find_by(schedule_id: schedule.id, client_id: 'msg-1')
      expect(item).to be_present
      expect(item.kind).to eq('chat')
      expect(item.payload['text']).to eq('Olá')
    end

    it 'não persiste quando rate limited' do
      subscribe(token: token_for(player), schedule_id: schedule.id)
      allow(SessionFeed::RateLimit).to receive(:allow?).and_return(false)
      expect { perform :feed_item, item: valid_chat }
        .not_to change(SessionFeedItem, :count)
    end

    it 'não persiste payload com kind inválido' do
      subscribe(token: token_for(player), schedule_id: schedule.id)
      expect { perform :feed_item, item: { 'kind' => 'system', 'text' => 'x' } }
        .not_to change(SessionFeedItem, :count)
    end

    it 'não confirma no broadcast quando a persistência levanta' do
      subscribe(token: token_for(player), schedule_id: schedule.id)
      allow(SessionFeed::Persist).to receive(:call).and_raise(StandardError.new('boom'))
      expect { perform :feed_item, item: valid_chat }
        .not_to have_broadcasted_to("session_feed_#{schedule.id}")
    end

    it 'reenvio conflitante da mesma rolagem transmite o primeiro resultado persistido' do
      subscribe(token: token_for(player), schedule_id: schedule.id)
      perform :feed_item, item: valid_roll

      expect do
        perform :feed_item, item: valid_roll.merge('total' => 2, 'breakdown' => 'retry obsoleto')
      end.to have_broadcasted_to("session_feed_#{schedule.id}").with(
        a_hash_including('kind' => 'roll', 'id' => 'roll-1', 'total' => 18),
      )
    end
  end
end
