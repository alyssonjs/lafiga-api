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

        # REGRESSÃO: o mover só é necessário p/ APLICAR DANO. No IGNORAR (e no ERRO)
        # o HP do mover não é tocado — um mover não-resolvível NÃO pode dar 422 e
        # travar a reação. Era o bug: ignorar o 1.º AO dava 422 "mover combatant não
        # encontrado", a interação não limpava e o 2.º AO nunca abria.
        it 'ignored:true LIMPA a interação mesmo com o mover NÃO resolvível (não dá 422)' do
          mover_cc.destroy! # torna o mover irresolúvel (find_by id + por identidade → nil)
          post "#{base}/active_interaction/respond",
               params: { character_id: reactor_npc_cc.combatable_id.to_s, opportunity_attack: { roll: { total: 18 }, damage: 7, ignored: true } },
               headers: dm_headers, as: :json
          expect(response).to have_http_status(:ok)
          expect(response.parsed_body['active_interaction']).to be_nil
          expect(cs.reload.active_interaction).to be_nil
        end

        it 'hit:false (ERRO) LIMPA a interação mesmo com o mover NÃO resolvível (não dá 422)' do
          mover_cc.destroy!
          post "#{base}/active_interaction/respond",
               params: { character_id: reactor_npc_cc.combatable_id.to_s, opportunity_attack: { roll: { total: 5 }, damage: 7, hit: false } },
               headers: dm_headers, as: :json
          expect(response).to have_http_status(:ok)
          expect(cs.reload.active_interaction).to be_nil
        end

        # REGRESSÃO: o front (resolveTargetIdentity) identifica o reator de AO como
        # `npc-<CombatNpc.id>` (ex.: 'npc-47'). `resolve_combatant_by_identity` tem
        # de resolver esse esquema — senão o reator NPC não é achado e a reação NÃO
        # é consumida (bug: AO do NPC não gastava a reação → reagia de novo na mesma
        # rodada). Aqui o reator é enviado como 'npc-<id>' e o miss deve consumir.
        it 'reator NPC por `npc-<id>` (esquema do front): miss consome a reação' do
          npc_ident = "npc-#{reactor_npc_cc.combatable_id}"
          put "#{base}/active_interaction",
              params: oa_upsert_body(reactor_identity: npc_ident, mover_identity: mover_cc.combatable_id,
                                     owned_by_dm: true, mover_combatant_id: mover_cc.id),
              headers: dm_headers, as: :json
          expect(response).to have_http_status(:ok)

          post "#{base}/active_interaction/respond",
               params: { character_id: npc_ident, opportunity_attack: { roll: { total: 5 }, damage: 0, hit: false } },
               headers: dm_headers, as: :json
          expect(response).to have_http_status(:ok)
          expect(reactor_npc_cc.reload.actions_used['reaction']).to be true # reação CONSUMIDA
          expect(cs.reload.active_interaction).to be_nil
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

      # REGRESSÃO: o EMIT às vezes carimba owned_by_dm:true num PC de JOGADOR (o mover que
      # dispara o OA não conhece o dono exato do reator). owned_by_dm NÃO é gate de autz — o
      # DONO REAL do PC responder tem que conseguir responder/ignorar, senão a interação
      # fica presa e trava a hotbar do mover ("ambos ignoraram, hotbar continuou bloqueada").
      context 'reator PC com owned_by_dm carimbado TRUE por engano (regressão)' do
        before do
          body = oa_upsert_body(reactor_identity: reactor_pc_cc.combatable_id, mover_identity: mover_cc.combatable_id,
                                owned_by_dm: true, mover_combatant_id: mover_cc.id)
          put "#{base}/active_interaction", params: body, headers: dm_headers, as: :json
          expect(response).to have_http_status(:ok)
          expect(cs.reload.active_interaction['pending_responders'].first['owned_by_dm']).to be true
        end

        it 'o DONO REAL do PC reator IGNORA → 200 + interação limpa (destrava a hotbar do mover)' do
          post "#{base}/active_interaction/respond",
               params: { character_id: reactor_pc_cc.combatable_id.to_s, opportunity_attack: { roll: { total: 0 }, damage: 0, ignored: true } },
               headers: defender_headers, as: :json
          expect(response).to have_http_status(:ok)
          expect(response.parsed_body['active_interaction']).to be_nil
          expect(cs.reload.active_interaction).to be_nil
          expect(mover_cc.reload.hp_current).to eq(20)                        # ignorar não aplica dano
          expect(reactor_pc_cc.reload.actions_used['reaction']).to be_falsey  # ignorar não consome reação
        end

        it 'ainda 403 para quem NÃO é o dono do reator nem DM' do
          post "#{base}/active_interaction/respond",
               params: { character_id: reactor_pc_cc.combatable_id.to_s, opportunity_attack: { roll: { total: 0 }, damage: 0, ignored: true } },
               headers: outsider_headers, as: :json
          expect(response).to have_http_status(:forbidden)
          expect(cs.reload.active_interaction).to be_present
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

  # ---- Frustrar Conjuração (kind: hostile_casting) ---------------------------
  # Fluxo 2 fases: (1) o Mestre declara a conjuração hostil de um NPC → o
  # Desistente PC vira pending `offer_reaction`; (2a) o reator frustra (gasta
  # reação server-side, avança p/ arbitragem do Mestre) ou ignora (não gasta);
  # (2b) o Mestre arbitra o TR do conjurador → magia falha (frustrada) ou prossegue.
  describe 'Frustrar Conjuração' do
    let!(:caster_npc) { create(:combat_npc, schedule: schedule) }
    let!(:caster_cc) do
      create(:combat_combatant, :npc, combat_state: cs, combatable: caster_npc, position: 0)
    end
    # Reator Desistente = PC do defender_user.
    let!(:desistente_cc) do
      create(:combat_combatant, :pc, combat_state: cs, combatable: defender_char, position: 1)
    end

    def hc_upsert_body(caster_identity:, reactor_identity:)
      {
        interaction: {
          kind: 'hostile_casting',
          source_id: caster_identity.to_s,
          target_ids: [reactor_identity.to_s],
          pending_responders: [
            { character_id: reactor_identity.to_s, need: 'offer_reaction', owned_by_dm: false, responded: false },
          ],
          hostile_casting: { caster_id: caster_identity.to_s, caster_name: 'Cultista', spell_name: 'Enfeitiçar Pessoa', spell_level: 1, dc: 14 },
        },
      }
    end

    describe 'PUT (upsert)' do
      it 'o DM declara a conjuração → fase declared, reator pendente offer_reaction' do
        put "#{base}/active_interaction",
            params: hc_upsert_body(caster_identity: caster_cc.combatable_id, reactor_identity: defender_char.id),
            headers: dm_headers, as: :json
        expect(response).to have_http_status(:ok)
        ai = response.parsed_body['active_interaction']
        expect(ai['kind']).to eq('hostile_casting')
        expect(ai['phase']).to eq('declared')
        expect(ai['pending_responders'].first['need']).to eq('offer_reaction')
        expect(ai['hostile_casting']['caster_name']).to eq('Cultista')
        expect(ai['hostile_casting']['dc']).to eq(14)
      end

      it '403 para jogador — só o Mestre declara conjuração de NPC' do
        put "#{base}/active_interaction",
            params: hc_upsert_body(caster_identity: caster_cc.combatable_id, reactor_identity: defender_char.id),
            headers: defender_headers, as: :json
        expect(response).to have_http_status(:forbidden)
        expect(cs.reload.active_interaction).to be_nil
      end
    end

    describe 'POST (respond) — 2 fases' do
      before do
        put "#{base}/active_interaction",
            params: hc_upsert_body(caster_identity: caster_cc.combatable_id, reactor_identity: defender_char.id),
            headers: dm_headers, as: :json
      end

      it 'reator frustra (fase 1): consome reação e avança p/ arbitragem do Mestre' do
        post "#{base}/active_interaction/respond",
             params: { character_id: defender_char.id.to_s, hostile_casting: { frustrate: true } },
             headers: defender_headers, as: :json
        expect(response).to have_http_status(:ok)
        ai = response.parsed_body['active_interaction']
        expect(ai['phase']).to eq('roll')
        expect(ai['pending_responders'].first['need']).to eq('arbitrate')
        expect(ai['pending_responders'].first['owned_by_dm']).to be true
        expect(desistente_cc.reload.actions_used['reaction']).to be true
      end

      it 'reator ignora (fase 1): NÃO consome reação e limpa a interação' do
        post "#{base}/active_interaction/respond",
             params: { character_id: defender_char.id.to_s, hostile_casting: { ignored: true } },
             headers: defender_headers, as: :json
        expect(response).to have_http_status(:ok)
        expect(cs.reload.active_interaction).to be_nil
        expect(desistente_cc.reload.actions_used['reaction']).to be_falsey
      end

      it 'Mestre arbitra FALHA no TR (fase 2): magia frustrada, limpa + log' do
        post "#{base}/active_interaction/respond",
             params: { character_id: defender_char.id.to_s, hostile_casting: { frustrate: true } },
             headers: defender_headers, as: :json
        expect do
          post "#{base}/active_interaction/respond",
               params: { character_id: caster_cc.combatable_id.to_s, hostile_casting: { saved: false } },
               headers: dm_headers, as: :json
        end.to change { schedule.session_logs.count }.by_at_least(1)
        expect(response).to have_http_status(:ok)
        expect(cs.reload.active_interaction).to be_nil
      end

      it 'Mestre arbitra SUCESSO no TR (fase 2): magia prossegue, limpa' do
        post "#{base}/active_interaction/respond",
             params: { character_id: defender_char.id.to_s, hostile_casting: { frustrate: true } },
             headers: defender_headers, as: :json
        post "#{base}/active_interaction/respond",
             params: { character_id: caster_cc.combatable_id.to_s, hostile_casting: { saved: true } },
             headers: dm_headers, as: :json
        expect(response).to have_http_status(:ok)
        expect(cs.reload.active_interaction).to be_nil
      end

      it '403 quando outro jogador (não o reator pendente) tenta frustrar' do
        post "#{base}/active_interaction/respond",
             params: { character_id: defender_char.id.to_s, hostile_casting: { frustrate: true } },
             headers: attacker_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # ---- Consentimento de Alvo (kind: target_consent) --------------------------
  # Um conjurador (PC do attacker_user) mira o PC do defender_user com magia
  # voluntária/benéfica → o DONO do alvo (defender) decide aceitar/recusar (M2).
  # Recusar/cancelar não consome nada (F3.6). Aversão à Magia auto-recusa (F3.1,
  # o front pré-seleciona recusar; aqui testamos o cano genérico).
  describe 'Consentimento de Alvo' do
    def tc_upsert_body(caster_identity:, target_identity:, auto_refuse: true)
      {
        interaction: {
          kind: 'target_consent',
          source_id: caster_identity.to_s,
          target_ids: [target_identity.to_s],
          pending_responders: [
            { character_id: target_identity.to_s, need: 'consent', owned_by_dm: false, responded: false },
          ],
          target_consent: { caster_id: caster_identity.to_s, caster_name: 'Clériga', spell_name: 'Bênção', beneficial: true, auto_refuse: auto_refuse },
        },
      }
    end

    describe 'PUT (upsert)' do
      it 'o dono do PC conjurador declara → fase declared, alvo pendente consent' do
        put "#{base}/active_interaction",
            params: tc_upsert_body(caster_identity: attacker_char.id, target_identity: defender_char.id),
            headers: attacker_headers, as: :json
        expect(response).to have_http_status(:ok)
        ai = response.parsed_body['active_interaction']
        expect(ai['kind']).to eq('target_consent')
        expect(ai['pending_responders'].first['need']).to eq('consent')
        expect(ai['target_consent']['auto_refuse']).to be true
      end

      it 'o DM também pode declarar' do
        put "#{base}/active_interaction",
            params: tc_upsert_body(caster_identity: attacker_char.id, target_identity: defender_char.id),
            headers: dm_headers, as: :json
        expect(response).to have_http_status(:ok)
      end
    end

    describe 'POST (respond) — dono do alvo decide (M2)' do
      before do
        put "#{base}/active_interaction",
            params: tc_upsert_body(caster_identity: attacker_char.id, target_identity: defender_char.id),
            headers: attacker_headers, as: :json
      end

      it 'o dono do alvo RECUSA (F3.1): limpa + log; nada consumido (F3.6)' do
        expect do
          post "#{base}/active_interaction/respond",
               params: { character_id: defender_char.id.to_s, target_consent: { refuse: true } },
               headers: defender_headers, as: :json
        end.to change { schedule.session_logs.count }.by_at_least(1)
        expect(response).to have_http_status(:ok)
        expect(cs.reload.active_interaction).to be_nil
      end

      it 'o dono do alvo ACEITA: limpa + log' do
        post "#{base}/active_interaction/respond",
             params: { character_id: defender_char.id.to_s, target_consent: { accept: true } },
             headers: defender_headers, as: :json
        expect(response).to have_http_status(:ok)
        expect(cs.reload.active_interaction).to be_nil
      end

      it '403 quando quem responde não é o dono do alvo (M2) nem DM' do
        post "#{base}/active_interaction/respond",
             params: { character_id: defender_char.id.to_s, target_consent: { refuse: true } },
             headers: attacker_headers, as: :json
        expect(response).to have_http_status(:forbidden)
        expect(cs.reload.active_interaction).to be_present
      end

      it '422 sem accept nem refuse' do
        post "#{base}/active_interaction/respond",
             params: { character_id: defender_char.id.to_s, target_consent: {} },
             headers: defender_headers, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  # ---- Fortitude Instintiva (kind: instinctive_fortitude) --------------------
  # O Bárbaro Furioso Imortal (PC do defender_user) cai a 0 PV. QUEM APLICOU o
  # dano (o atacante do turno atual, ou o DM) declara a interação → o DONO do PC
  # caído (defender) decide (M2): aceitar entra em Fúria + volta a 1 PV + consome
  # a reação (F14.4, server-side); recusar não consome nada. M3: NPC → DM.
  describe 'Fortitude Instintiva' do
    # Atacante no turno atual (position 0 = current_turn_index) → pode iniciar.
    let!(:attacker_cc) do
      create(:combat_combatant, :pc,
             combat_state: cs, combatable: attacker_char,
             position: 0, ac: 15, hp_current: 20, hp_max: 20)
    end

    # Bárbaro CAÍDO (PC do defender_user): 0 PV, Morrendo, 1 falha de TR de morte.
    let!(:downed_cc) do
      create(:combat_combatant, :pc,
             combat_state: cs, combatable: defender_char,
             position: 1, hp_current: 0, hp_max: 30,
             death_saves: { 'successes' => 0, 'failures' => 1 })
    end

    def if_upsert_body(reactor_identity:, owned_by_dm: false)
      {
        interaction: {
          kind: 'instinctive_fortitude',
          source_id: reactor_identity.to_s,
          target_ids: [reactor_identity.to_s],
          pending_responders: [
            { character_id: reactor_identity.to_s, need: 'offer_reaction', owned_by_dm: owned_by_dm, responded: false },
          ],
          instinctive_fortitude: { downed_name: 'Grog' },
        },
      }
    end

    describe 'PUT (upsert)' do
      it 'o atacante do turno atual declara → fase declared, caído pendente offer_reaction' do
        put "#{base}/active_interaction",
            params: if_upsert_body(reactor_identity: defender_char.id),
            headers: attacker_headers, as: :json
        expect(response).to have_http_status(:ok)
        ai = response.parsed_body['active_interaction']
        expect(ai['kind']).to eq('instinctive_fortitude')
        expect(ai['phase']).to eq('declared')
        expect(ai['source_id']).to eq(defender_char.id.to_s)
        expect(ai['pending_responders'].first['need']).to eq('offer_reaction')
        expect(ai['instinctive_fortitude']['downed_name']).to eq('Grog')
      end

      it 'o DM também pode declarar (M3: caído NPC)' do
        put "#{base}/active_interaction",
            params: if_upsert_body(reactor_identity: defender_char.id, owned_by_dm: true),
            headers: dm_headers, as: :json
        expect(response).to have_http_status(:ok)
      end

      it '403 quando quem declara não é o atacante do turno nem DM' do
        put "#{base}/active_interaction",
            params: if_upsert_body(reactor_identity: defender_char.id),
            headers: outsider_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    describe 'POST (respond) — dono do caído decide (M2)' do
      before do
        put "#{base}/active_interaction",
            params: if_upsert_body(reactor_identity: defender_char.id),
            headers: attacker_headers, as: :json
      end

      it 'ACEITA: HP=1, sai de Morrendo, entra em Fúria, consome a reação (F14.4); limpa + log' do
        expect do
          post "#{base}/active_interaction/respond",
               params: { character_id: defender_char.id.to_s, instinctive_fortitude: { accept: true } },
               headers: defender_headers, as: :json
        end.to change { schedule.session_logs.count }.by_at_least(1)
        expect(response).to have_http_status(:ok)

        downed_cc.reload
        expect(downed_cc.hp_current).to eq(1)
        expect(downed_cc.is_dead).to be false
        expect(downed_cc.is_stabilized).to be false
        expect(downed_cc.death_saves).to eq('successes' => 0, 'failures' => 0) # resetado
        expect(downed_cc.turn_state['rageRoundsRemaining']).to eq(10)
        expect(downed_cc.actions_used['reaction']).to be true # F14.4: reação consumida
        expect(cs.reload.active_interaction).to be_nil
      end

      it 'RECUSA: nada é consumido (HP 0, reação livre); permanece Morrendo; limpa + log' do
        post "#{base}/active_interaction/respond",
             params: { character_id: defender_char.id.to_s, instinctive_fortitude: { decline: true } },
             headers: defender_headers, as: :json
        expect(response).to have_http_status(:ok)

        downed_cc.reload
        expect(downed_cc.hp_current).to eq(0)
        expect(downed_cc.actions_used['reaction']).to be false
        expect(downed_cc.turn_state['rageRoundsRemaining']).to be_nil
        expect(cs.reload.active_interaction).to be_nil
      end

      it '403 quando quem responde não é o dono do caído (M2) nem DM' do
        post "#{base}/active_interaction/respond",
             params: { character_id: defender_char.id.to_s, instinctive_fortitude: { accept: true } },
             headers: attacker_headers, as: :json
        expect(response).to have_http_status(:forbidden)
        expect(cs.reload.active_interaction).to be_present
      end

      it '422 sem accept nem decline' do
        post "#{base}/active_interaction/respond",
             params: { character_id: defender_char.id.to_s, instinctive_fortitude: {} },
             headers: defender_headers, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'Fúria Protetora: Trocar de Lugar (protective_swap)' do
    # Atacante = NPC do DM, no turno atual (position 0 = current_turn_index).
    let!(:attacker_npc) { create(:combat_npc, schedule: schedule) }
    let!(:attacker_npc_cc) do
      create(:combat_combatant, :npc, combat_state: cs, combatable: attacker_npc, position: 0)
    end
    # Protetor = PC do defender_user (reator).
    let!(:protector_cc) do
      create(:combat_combatant, :pc, combat_state: cs, combatable: defender_char,
             position: 1, ac: 18, hp_current: 30, hp_max: 30)
    end
    # Aliado (alvo original) = PC do outsider.
    let!(:ally_char) { create(:character, user: outsider, group: schedule.group) }
    let!(:ally_cc) do
      create(:combat_combatant, :pc, combat_state: cs, combatable: ally_char,
             position: 2, ac: 14, hp_current: 12, hp_max: 12)
    end

    def ps_upsert_body
      {
        interaction: {
          kind: 'protective_swap',
          source_id: defender_char.id.to_s,
          pending_responders: [
            { character_id: defender_char.id.to_s, need: 'offer_reaction', owned_by_dm: false, responded: false },
          ],
          protective_swap: {
            reactor_char_id: defender_char.id.to_s,
            ally_char_id: ally_char.id.to_s,
            ally_owned_by_dm: false,
            attacker_token_id: 'tk-foe',
            ally_token_id: 'tk-ally',
            reactor_token_id: 'tk-prot',
            attack_meta: { name: 'Machado', caster_name: 'Ogro', bonus: '+5', damage: '1d12+3', damage_type: 'cortante' },
          },
        },
      }
    end

    def respond_body(char_id, accept:)
      decision = accept ? { accept: true } : { decline: true }
      { character_id: char_id.to_s, protective_swap: decision }
    end

    describe 'PUT (upsert)' do
      it 'DM declara o swap (atacante NPC) → 200, fase awaiting_protector' do
        put "#{base}/active_interaction", params: ps_upsert_body, headers: dm_headers, as: :json
        expect(response).to have_http_status(:ok)
        ai = response.parsed_body['active_interaction']
        expect(ai['kind']).to eq('protective_swap')
        expect(ai['phase']).to eq('awaiting_protector')
        expect(ai['pending_responders'].first['character_id']).to eq(defender_char.id.to_s)
        expect(ai['pending_responders'].first['need']).to eq('offer_reaction')
      end

      it '403 quando quem declara não é DM nem dono do PC do turno atual' do
        put "#{base}/active_interaction", params: ps_upsert_body, headers: outsider_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    describe 'POST (respond) — 2 fases' do
      before do
        put "#{base}/active_interaction", params: ps_upsert_body, headers: dm_headers, as: :json
      end

      it 'Protetor aceita → fase awaiting_consent com o aliado pendente (need consent)' do
        post "#{base}/active_interaction/respond",
             params: respond_body(defender_char.id, accept: true), headers: defender_headers, as: :json
        expect(response).to have_http_status(:ok)
        ai = response.parsed_body['active_interaction']
        expect(ai['phase']).to eq('awaiting_consent')
        expect(ai['pending_responders'].first['character_id']).to eq(ally_char.id.to_s)
        expect(ai['pending_responders'].first['need']).to eq('consent')
      end

      it 'Protetor recusa → resolved/declined sem consumir reação' do
        post "#{base}/active_interaction/respond",
             params: respond_body(defender_char.id, accept: false), headers: defender_headers, as: :json
        ai = response.parsed_body['active_interaction']
        expect(ai['phase']).to eq('resolved')
        expect(ai['protective_swap']['outcome']).to eq('declined')
        expect(protector_cc.reload.actions_used['reaction']).to be_falsey
      end

      it 'fluxo completo: Protetor aceita → aliado consente → consome reação + resolved/accepted' do
        post "#{base}/active_interaction/respond",
             params: respond_body(defender_char.id, accept: true), headers: defender_headers, as: :json
        post "#{base}/active_interaction/respond",
             params: respond_body(ally_char.id, accept: true), headers: outsider_headers, as: :json
        ai = response.parsed_body['active_interaction']
        expect(ai['phase']).to eq('resolved')
        expect(ai['protective_swap']['outcome']).to eq('accepted')
        expect(protector_cc.reload.actions_used['reaction']).to be true
        # Houserule "1 reação por RODADA": grava o marcador SERVER-OWNED da rodada
        # do uso (sem ele, o reset defensivo do front recarregaria a reação).
        expect(protector_cc.reload.turn_state['reactionUsedRound']).to eq(cs.round)
      end

      it 'aliado recusa o consentimento → resolved/declined sem consumir reação' do
        post "#{base}/active_interaction/respond",
             params: respond_body(defender_char.id, accept: true), headers: defender_headers, as: :json
        post "#{base}/active_interaction/respond",
             params: respond_body(ally_char.id, accept: false), headers: outsider_headers, as: :json
        ai = response.parsed_body['active_interaction']
        expect(ai['phase']).to eq('resolved')
        expect(ai['protective_swap']['outcome']).to eq('declined')
        expect(protector_cc.reload.actions_used['reaction']).to be_falsey
      end

      it 'outsider não pode responder pelo Protetor (não é dono)' do
        post "#{base}/active_interaction/respond",
             params: respond_body(defender_char.id, accept: true), headers: outsider_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'Defensor da Tribo (tribe_defender)' do
    # Atacante/aplicador = NPC do DM, no turno atual (position 0).
    let!(:td_attacker_npc) { create(:combat_npc, schedule: schedule) }
    let!(:td_attacker_cc) do
      create(:combat_combatant, :npc, combat_state: cs, combatable: td_attacker_npc, position: 0)
    end
    # Defensor = PC do defender_user (reator).
    let!(:td_defender_cc) do
      create(:combat_combatant, :pc, combat_state: cs, combatable: defender_char,
             position: 1, ac: 18, hp_current: 40, hp_max: 40)
    end
    # Aliado caído = PC do outsider.
    let!(:td_ally_char) { create(:character, user: outsider, group: schedule.group) }
    let!(:td_ally_cc) do
      create(:combat_combatant, :pc, combat_state: cs, combatable: td_ally_char,
             position: 2, ac: 14, hp_current: 0, hp_max: 12)
    end

    def td_upsert_body
      {
        interaction: {
          kind: 'tribe_defender',
          source_id: defender_char.id.to_s,
          pending_responders: [
            { character_id: defender_char.id.to_s, need: 'offer_reaction', owned_by_dm: false, responded: false },
          ],
          tribe_defender: {
            defender_char_id: defender_char.id.to_s,
            ally_char_id: td_ally_char.id.to_s,
            ally_owned_by_dm: false,
            defender_token_id: 'tk-def',
            ally_token_id: 'tk-ally',
            downed_name: 'Aliado',
          },
        },
      }
    end

    def td_respond_body(char_id, accept:)
      decision = accept ? { accept: true } : { decline: true }
      { character_id: char_id.to_s, tribe_defender: decision }
    end

    describe 'PUT (upsert)' do
      it 'DM/aplicador declara → 200, fase declared, Defensor pendente' do
        put "#{base}/active_interaction", params: td_upsert_body, headers: dm_headers, as: :json
        expect(response).to have_http_status(:ok)
        ai = response.parsed_body['active_interaction']
        expect(ai['kind']).to eq('tribe_defender')
        expect(ai['phase']).to eq('declared')
        expect(ai['pending_responders'].first['character_id']).to eq(defender_char.id.to_s)
      end

      it '403 quando quem declara não é DM, dono do turno nem dono do Defensor' do
        put "#{base}/active_interaction", params: td_upsert_body, headers: outsider_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    describe 'POST (respond)' do
      before do
        put "#{base}/active_interaction", params: td_upsert_body, headers: dm_headers, as: :json
      end

      it 'Defensor aceita → consome a reação + marca guardingAlly (atômico) + resolved/accepted' do
        post "#{base}/active_interaction/respond",
             params: td_respond_body(defender_char.id, accept: true), headers: defender_headers, as: :json
        ai = response.parsed_body['active_interaction']
        expect(ai['phase']).to eq('resolved')
        expect(ai['tribe_defender']['outcome']).to eq('accepted')
        # Reação E guardingAlly no MESMO update — o front não repatcha actions_used.
        expect(td_defender_cc.reload.actions_used['reaction']).to be true
        expect(td_defender_cc.reload.turn_state['guardingAlly']).to eq('tk-ally')
      end

      it 'Defensor recusa → resolved/declined sem consumir reação' do
        post "#{base}/active_interaction/respond",
             params: td_respond_body(defender_char.id, accept: false), headers: defender_headers, as: :json
        ai = response.parsed_body['active_interaction']
        expect(ai['phase']).to eq('resolved')
        expect(ai['tribe_defender']['outcome']).to eq('declined')
        expect(td_defender_cc.reload.actions_used['reaction']).to be_falsey
      end

      it 'outsider não pode responder pelo Defensor' do
        post "#{base}/active_interaction/respond",
             params: td_respond_body(defender_char.id, accept: true), headers: outsider_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
