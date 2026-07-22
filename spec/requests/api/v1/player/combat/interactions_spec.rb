# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Player::Combat::InteractionsController', type: :request do
  let(:dm_role)     { Role.find_or_create_by!(name: 'DM') }
  let(:player_role) { Role.find_or_create_by!(name: 'Player') }

  let(:dm)       { create(:user, role: dm_role) }
  let(:attacker_user) { create(:user, role: player_role) }
  let(:defender_user) { create(:user, role: player_role) }
  let(:outsider) { create(:user, role: player_role) }

  let(:schedule) { create(:schedule) }
  let!(:attacker_char) { create(:character, user: attacker_user, group: schedule.group) }
  let!(:defender_char) { create(:character, user: defender_user, group: schedule.group) }

  let!(:cs) { create(:combat_state, schedule: schedule, active: true, round: 1, current_turn_index: 0) }

  let(:dm_headers)       { bearer_headers_for(dm) }
  let(:attacker_headers) { bearer_headers_for(attacker_user) }
  let(:defender_headers) { bearer_headers_for(defender_user) }
  let(:outsider_headers) { bearer_headers_for(outsider) }

  let(:base) { "/api/v1/player/schedules/#{schedule.id}/combat" }

  def capture_envelopes
    envelopes = []
    allow(ActionCable.server).to receive(:broadcast).and_wrap_original do |m, stream_name, data|
      envelopes << data.deep_stringify_keys
      m.call(stream_name, data)
    end
    yield
    envelopes
  end

  def upsert_body(extra = {})
    {
      interaction: {
        kind: 'contest',
        source_id: attacker_char.id.to_s,
        target_ids: [defender_char.id.to_s],
        label: 'Empurrão',
        attacker_roll: { total: 18, formula: '1d20+5', skill: 'Atletismo' },
      }.merge(extra),
    }
  end

  describe 'PUT /combat/active_interaction (upsert)' do
    it 'cria a interação de disputa pelo DM com fase roll e defensor pendente' do
      put "#{base}/active_interaction", params: upsert_body, headers: dm_headers, as: :json
      expect(response).to have_http_status(:ok)

      ai = response.parsed_body['active_interaction']
      expect(ai['kind']).to eq('contest')
      expect(ai['phase']).to eq('roll')
      expect(ai['source_id']).to eq(attacker_char.id.to_s)
      expect(ai['target_ids']).to eq([defender_char.id.to_s])
      expect(ai['label']).to eq('Empurrão')

      pending = ai['pending_responders']
      expect(pending.size).to eq(1)
      expect(pending.first).to include(
        'character_id' => defender_char.id.to_s,
        'need' => 'roll_contest',
        'responded' => false,
      )

      contest = ai['contest']
      expect(contest['attacker_skill']).to eq('Atletismo')
      expect(contest['defender_skill_options']).to match_array(%w[Atletismo Acrobacia])
      expect(contest['attacker_roll']).to include('total' => 18)
      expect(contest['defender_roll']).to be_nil
      expect(contest['outcome']).to be_nil

      expect(cs.reload.active_interaction['phase']).to eq('roll')
    end

    it 'permite o jogador dono do PC atacante criar a interação' do
      put "#{base}/active_interaction", params: upsert_body, headers: attacker_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['active_interaction']['source_id']).to eq(attacker_char.id.to_s)
    end

    it 'broadcasts state_changed carregando active_interaction' do
      envelopes = capture_envelopes do
        put "#{base}/active_interaction", params: upsert_body, headers: dm_headers, as: :json
      end
      expect(response).to have_http_status(:ok)

      st = envelopes.find { |h| h['event'] == 'state_changed' }
      expect(st).to be_present
      expect(st['payload']['active_interaction']).to be_present
      expect(st['payload']['active_interaction']['kind']).to eq('contest')
    end

    it '403 para um jogador que não é dono do PC atacante nem DM' do
      put "#{base}/active_interaction", params: upsert_body, headers: defender_headers, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(cs.reload.active_interaction).to be_nil
    end

    it '422 para payload inválido (sem source_id)' do
      put "#{base}/active_interaction",
          params: { interaction: { kind: 'contest', target_ids: [defender_char.id.to_s] } },
          headers: dm_headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it '422 quando o combate não está activo' do
      cs.update_column(:active, false)
      put "#{base}/active_interaction", params: upsert_body, headers: dm_headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it '401 sem auth' do
      put "#{base}/active_interaction", params: upsert_body, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /combat/active_interaction/respond' do
    before do
      put "#{base}/active_interaction", params: upsert_body, headers: dm_headers, as: :json
    end

    let(:respond_body) do
      {
        character_id: defender_char.id.to_s,
        defender_roll: { total: 14, formula: '1d20+2', skill: 'Acrobacia' },
      }
    end

    it 'o defensor responde, resolve o contest e avança para hit_determined' do
      post "#{base}/active_interaction/respond", params: respond_body, headers: defender_headers, as: :json
      expect(response).to have_http_status(:ok)

      ai = response.parsed_body['active_interaction']
      expect(ai['phase']).to eq('hit_determined')
      expect(ai['contest']['defender_roll']).to include('total' => 14, 'skill' => 'Acrobacia')
      # atacante 18 > defensor 14 → source_wins
      expect(ai['contest']['outcome']).to eq('source_wins')
      expect(ai['pending_responders'].first['responded']).to be true
    end

    it 'empate faz o defensor vencer (target_wins)' do
      post "#{base}/active_interaction/respond",
           params: { character_id: defender_char.id.to_s, defender_roll: { total: 18, skill: 'Atletismo' } },
           headers: defender_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['active_interaction']['contest']['outcome']).to eq('target_wins')
    end

    it 'o DM também pode responder pelo defensor' do
      post "#{base}/active_interaction/respond", params: respond_body, headers: dm_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['active_interaction']['phase']).to eq('hit_determined')
    end

    it 'broadcasts state_changed na resposta' do
      envelopes = capture_envelopes do
        post "#{base}/active_interaction/respond", params: respond_body, headers: defender_headers, as: :json
      end
      st = envelopes.find { |h| h['event'] == 'state_changed' }
      expect(st['payload']['active_interaction']['phase']).to eq('hit_determined')
    end

    it '403 quando quem responde não é o defensor pendente nem DM' do
      post "#{base}/active_interaction/respond", params: respond_body, headers: attacker_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it '422 quando não há interação activa' do
      cs.update_column(:active_interaction, nil)
      post "#{base}/active_interaction/respond", params: respond_body, headers: defender_headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it '422 para defender_roll inválido' do
      post "#{base}/active_interaction/respond",
           params: { character_id: defender_char.id.to_s, defender_roll: { skill: 'Acrobacia' } },
           headers: defender_headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'DELETE /combat/active_interaction (clear)' do
    before do
      put "#{base}/active_interaction", params: upsert_body, headers: dm_headers, as: :json
    end

    it 'limpa a interação pelo DM e devolve null' do
      delete "#{base}/active_interaction", headers: dm_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['active_interaction']).to be_nil
      expect(cs.reload.active_interaction).to be_nil
    end

    it 'permite o dono do PC atacante limpar' do
      delete "#{base}/active_interaction", headers: attacker_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(cs.reload.active_interaction).to be_nil
    end

    it 'broadcasts state_changed ao limpar' do
      envelopes = capture_envelopes do
        delete "#{base}/active_interaction", headers: dm_headers, as: :json
      end
      st = envelopes.find { |h| h['event'] == 'state_changed' }
      expect(st).to be_present
      expect(st['payload']['active_interaction']).to be_nil
    end

    it '403 para outsider que não é DM nem dono do atacante' do
      delete "#{base}/active_interaction", headers: defender_headers, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(cs.reload.active_interaction).to be_present
    end

    it 'é idempotente: 200 mesmo sem interação activa' do
      cs.update_column(:active_interaction, nil)
      delete "#{base}/active_interaction", headers: dm_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['active_interaction']).to be_nil
    end
  end

  # ---- Ataque de Oportunidade (kind: opportunity_attack) ---------------------
  #
  # Topologia: o MOVER é o PC do TURNO ATUAL (position == current_turn_index).
  # O REATOR é quem ganha a reação (source_id). O reator é o pending responder.
  # O dano é aplicado SERVER-SIDE no respond contra o AC FRESCO do mover.
  describe 'Ataque de Oportunidade' do
    # Mover = PC do attacker_user, no turno atual (position 0).
    let!(:mover_cc) do
      create(:combat_combatant, :pc,
             combat_state: cs, combatable: attacker_char,
             position: 0, ac: 15, hp_current: 20, hp_max: 20)
    end

    # Reator NPC (do DM) — para o caminho do DM responder por NPC.
    let!(:reactor_npc) { create(:combat_npc, schedule: schedule) }
    let!(:reactor_npc_cc) do
      create(:combat_combatant, :npc,
             combat_state: cs, combatable: reactor_npc, position: 1)
    end

    # Reator PC (do defender_user) — para o caminho do jogador-reator responder.
    let!(:reactor_pc_cc) do
      create(:combat_combatant, :pc,
             combat_state: cs, combatable: defender_char, position: 2)
    end

    def oa_upsert_body(reactor_identity:, mover_identity:, owned_by_dm:, mover_combatant_id: nil)
      {
        interaction: {
          kind: 'opportunity_attack',
          source_id: reactor_identity.to_s,
          target_ids: [mover_identity.to_s],
          pending_responders: [
            { character_id: reactor_identity.to_s, need: 'offer_reaction', owned_by_dm: owned_by_dm, responded: false },
          ],
          opportunity_attack: {
            mover_token_id: 'tok-mover',
            mover_name: mover_cc.name,
            mover_combatant_id: mover_combatant_id,
            reactor_token_id: 'tok-reactor',
            reactor_name: 'Reator',
            attacks: [{ name: 'Espada Longa', damage_type: 'cortante' }],
            npc_attacks: [],
            ignores_disengage: false,
            oa_at_disadvantage: false,
          },
        },
      }
    end

    describe 'PUT (upsert)' do
      it 'DM faz upsert de OA (reator = NPC do DM) → 200' do
        body = oa_upsert_body(reactor_identity: reactor_npc_cc.combatable_id, mover_identity: mover_cc.combatable_id,
                              owned_by_dm: true, mover_combatant_id: mover_cc.id)
        put "#{base}/active_interaction", params: body, headers: dm_headers, as: :json
        expect(response).to have_http_status(:ok)
        ai = response.parsed_body['active_interaction']
        expect(ai['kind']).to eq('opportunity_attack')
        expect(ai['phase']).to eq('roll')
        expect(ai['pending_responders'].first['need']).to eq('offer_reaction')
      end

      it 'jogador-mover (dono do PC do turno) faz upsert de OA cujo reator é NPC → 200' do
        body = oa_upsert_body(reactor_identity: reactor_npc_cc.combatable_id, mover_identity: mover_cc.combatable_id,
                              owned_by_dm: true, mover_combatant_id: mover_cc.id)
        put "#{base}/active_interaction", params: body, headers: attacker_headers, as: :json
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['active_interaction']['kind']).to eq('opportunity_attack')
      end

      it '403 quando quem dispara o OA não é DM nem dono do PC do turno' do
        body = oa_upsert_body(reactor_identity: reactor_npc_cc.combatable_id, mover_identity: mover_cc.combatable_id,
                              owned_by_dm: true, mover_combatant_id: mover_cc.id)
        put "#{base}/active_interaction", params: body, headers: outsider_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    describe 'POST (respond) — dano server-side' do
      context 'reator NPC respondido pelo DM' do
        before do
          body = oa_upsert_body(reactor_identity: reactor_npc_cc.combatable_id, mover_identity: mover_cc.combatable_id,
                                owned_by_dm: true, mover_combatant_id: mover_cc.id)
          put "#{base}/active_interaction", params: body, headers: dm_headers, as: :json
        end

        it 'hit:true (Mestre confirma ACERTO) → active_interaction limpa (nil); HP cai; reação consumida; log combat criado — independe da CA' do
          # roll BAIXO de propósito (10 < CA 15): a decisão é do Mestre, não da CA.
          expect do
            post "#{base}/active_interaction/respond",
                 params: { character_id: reactor_npc_cc.combatable_id.to_s, opportunity_attack: { roll: { total: 10 }, damage: 7, hit: true } },
                 headers: dm_headers, as: :json
          end.to change { schedule.session_logs.where(kind: :combat).count }.by(1)
          expect(response).to have_http_status(:ok)

          # F0 — respond LIMPA server-side: active_interaction vira null (o front
          # observa null, não 'resolved').
          expect(response.parsed_body['active_interaction']).to be_nil
          expect(cs.reload.active_interaction).to be_nil

          expect(mover_cc.reload.hp_current).to eq(13)        # 20 - 7
          expect(reactor_npc_cc.reload.actions_used['reaction']).to be true

          log = schedule.session_logs.where(kind: :combat).order(:created_at).last
          expect(log.message).to include('ACERTOU')
          expect(log.message).to include('7 de dano')
        end

        it 'mitiga por tipo — mover imune ao damage_type do rider (cortante) sofre 0' do
          # O rider armazenado na interação é `attacks: [{ damage_type: 'cortante' }]`.
          # O DamageService (server-side) lê esse tipo → mover imune a cortante = 0.
          create(:sheet, character: attacker_char, hp_current: 20, hp_max: 20,
                 metadata: { 'damage_immunities' => ['cortante'] })

          post "#{base}/active_interaction/respond",
               params: { character_id: reactor_npc_cc.combatable_id.to_s, opportunity_attack: { roll: { total: 18 }, damage: 7, hit: true } },
               headers: dm_headers, as: :json
          expect(response).to have_http_status(:ok)
          expect(mover_cc.reload.hp_current).to eq(20) # imune → 0 dano
        end

        it 'hit:false (Mestre marca ERRO) → miss; active_interaction limpa; HP não cai; log ERROU; reação consumida — independe da CA' do
          # roll ALTO de propósito (18 >= CA 15): mesmo assim o Mestre errou.
          post "#{base}/active_interaction/respond",
               params: { character_id: reactor_npc_cc.combatable_id.to_s, opportunity_attack: { roll: { total: 18 }, damage: 7, hit: false } },
               headers: dm_headers, as: :json
          expect(response).to have_http_status(:ok)
          expect(response.parsed_body['active_interaction']).to be_nil
          expect(cs.reload.active_interaction).to be_nil
          expect(mover_cc.reload.hp_current).to eq(20)
          expect(reactor_npc_cc.reload.actions_used['reaction']).to be true

          log = schedule.session_logs.where(kind: :combat).order(:created_at).last
          expect(log.message).to include('ERROU')
        end

        it 'ignored:true → active_interaction limpa; HP não cai; reação NÃO consumida; log "abriu mão"' do
          post "#{base}/active_interaction/respond",
               params: { character_id: reactor_npc_cc.combatable_id.to_s, opportunity_attack: { roll: { total: 18 }, damage: 7, ignored: true } },
               headers: dm_headers, as: :json
          expect(response).to have_http_status(:ok)
          expect(response.parsed_body['active_interaction']).to be_nil
          expect(cs.reload.active_interaction).to be_nil
          expect(mover_cc.reload.hp_current).to eq(20)
          # Ignorar = não reagiu → não gasta reação.
          expect(reactor_npc_cc.reload.actions_used['reaction']).to be false

          log = schedule.session_logs.where(kind: :combat).order(:created_at).last
          expect(log.message).to include('abriu mão')
        end

        it 'idempotente: segundo respond não reaplica dano nem cria segundo log' do
          # 1º respond: Mestre confirma acerto → aplica dano, cria log e LIMPA.
          expect do
            post "#{base}/active_interaction/respond",
                 params: { character_id: reactor_npc_cc.combatable_id.to_s, opportunity_attack: { roll: { total: 18 }, damage: 7, hit: true } },
                 headers: dm_headers, as: :json
          end.to change { schedule.session_logs.where(kind: :combat).count }.by(1)
          expect(response).to have_http_status(:ok)
          expect(cs.reload.active_interaction).to be_nil

          # 2º respond (sequencial): interação já nil → no-op idempotente. Não há
          # 5xx, não reaplica dano e não cria segundo log.
          expect do
            post "#{base}/active_interaction/respond",
                 params: { character_id: reactor_npc_cc.combatable_id.to_s, opportunity_attack: { roll: { total: 18 }, damage: 7, hit: true } },
                 headers: dm_headers, as: :json
          end.not_to change { schedule.session_logs.where(kind: :combat).count }
          expect(response.status).to be < 500
          expect(mover_cc.reload.hp_current).to eq(13)        # aplicou só uma vez
        end

        it 'broadcasts: combatant_upserted(mover) → state_changed(nil) → log_appended' do
          envelopes = capture_envelopes do
            post "#{base}/active_interaction/respond",
                 params: { character_id: reactor_npc_cc.combatable_id.to_s, opportunity_attack: { roll: { total: 18 }, damage: 7, hit: true } },
                 headers: dm_headers, as: :json
          end
          events = envelopes.map { |e| e['event'] }
          expect(events).to include('combatant_upserted', 'state_changed', 'log_appended')

          st = envelopes.find { |h| h['event'] == 'state_changed' }
          expect(st['payload']['active_interaction']).to be_nil

          log_ev = envelopes.find { |h| h['event'] == 'log_appended' }
          expect(log_ev['payload']['message']).to include('ACERTOU')
        end
      end

      context 'reator PC respondido pelo dono FORA do seu turno' do
        before do
          body = oa_upsert_body(reactor_identity: reactor_pc_cc.combatable_id, mover_identity: mover_cc.combatable_id,
                                owned_by_dm: false, mover_combatant_id: mover_cc.id)
          put "#{base}/active_interaction", params: body, headers: attacker_headers, as: :json
          expect(response).to have_http_status(:ok)
        end

        it 'dono do PC reator (fora do turno dele) responde com hit:true → HP do mover cai; interação limpa; reação consumida' do
          # current_turn_index = 0 (mover). O reator (defender_char) está em position 2 → fora do turno.
          post "#{base}/active_interaction/respond",
               params: { character_id: reactor_pc_cc.combatable_id.to_s, opportunity_attack: { roll: { total: 16 }, damage: 5, hit: true } },
               headers: defender_headers, as: :json
          expect(response).to have_http_status(:ok)
          expect(response.parsed_body['active_interaction']).to be_nil
          expect(cs.reload.active_interaction).to be_nil
          expect(mover_cc.reload.hp_current).to eq(15)        # 20 - 5
          expect(reactor_pc_cc.reload.actions_used['reaction']).to be true
        end

        it 'miss com hit:false → interação limpa, HP inalterado, reação consumida' do
          post "#{base}/active_interaction/respond",
               params: { character_id: reactor_pc_cc.combatable_id.to_s, opportunity_attack: { roll: { total: 16 }, damage: 5, hit: false } },
               headers: defender_headers, as: :json
          expect(response).to have_http_status(:ok)
          expect(response.parsed_body['active_interaction']).to be_nil
          expect(cs.reload.active_interaction).to be_nil
          expect(mover_cc.reload.hp_current).to eq(20)
          expect(reactor_pc_cc.reload.actions_used['reaction']).to be true
        end

        it '403 quando quem responde não é o reator pendente nem DM' do
          post "#{base}/active_interaction/respond",
               params: { character_id: reactor_pc_cc.combatable_id.to_s, opportunity_attack: { roll: { total: 16 }, damage: 5, hit: true } },
               headers: outsider_headers, as: :json
          expect(response).to have_http_status(:forbidden)
          expect(mover_cc.reload.hp_current).to eq(20)
        end
      end
    end
  end

  describe 'serialização em GET combat_state' do
    it 'inclui active_interaction no payload do combat_state' do
      put "#{base}/active_interaction", params: upsert_body, headers: dm_headers, as: :json
      get "/api/v1/player/schedules/#{schedule.id}/combat_state", headers: defender_headers
      expect(response).to have_http_status(:ok)
      ai = response.parsed_body['combat_state']['active_interaction']
      expect(ai).to be_present
      expect(ai['pending_responders'].first['character_id']).to eq(defender_char.id.to_s)
    end

    it 'active_interaction é null quando não há interação' do
      get "/api/v1/player/schedules/#{schedule.id}/combat_state", headers: defender_headers
      expect(response.parsed_body['combat_state']['active_interaction']).to be_nil
    end
  end
end
