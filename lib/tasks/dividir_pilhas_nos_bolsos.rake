# frozen_string_literal: true

# Pilhas ANTIGAS de consumível penduradas num bolso só — de antes de 30/09/2026,
# quando o bolso de fora passou a levar UMA unidade por vez (a regra do slot de
# consumível do cinto). Divide em linhas de 1, uma por bolso LIVRE da mesma
# bolsa; o que não couber volta para fora, fundido na pilha gêmea solta.
#
#   DRY_RUN=1 bin/rails dnd:dividir_pilhas_nos_bolsos   # só relata
#   SHEET_ID=85 bin/rails dnd:dividir_pilhas_nos_bolsos  # uma ficha
#
# Idempotente: depois de rodar, nenhuma pilha de consumível sobra num bolso.
namespace :dnd do
  desc 'Divide pilhas de consumível penduradas num bolso só (um por bolso). DRY_RUN=1 só relata.'
  task dividir_pilhas_nos_bolsos: :environment do
    seco = ENV['DRY_RUN'].present?
    ponteiro = SheetItem::BAG_SLOT_CONTAINER_PROP
    rel = SheetItem.where('quantity > 1').where('(props_json ->> ?) IS NOT NULL', ponteiro)
    rel = rel.where(sheet_id: ENV['SHEET_ID']) if ENV['SHEET_ID'].present?

    # Quantas unidades vão para bolsos livres da MESMA bolsa e quantas saem.
    # O DRY_RUN não grava: desconta à mão os bolsos que as pilhas anteriores
    # ocupariam, senão duas pilhas a disputar o último bolso cabiam as duas.
    reservados = Hash.new(0)
    planejar = lambda do |linha|
      bolsa_id = linha.stored_on_bag_slot_id
      bolsa = SheetItem.find_by(id: bolsa_id)
      ocupados = SheetItem.where(sheet_id: linha.sheet_id).where("props_json ->> '#{ponteiro}' = ?", bolsa_id.to_s).count
      livres = [(bolsa&.bag_slot_count || 0) - ocupados - reservados[bolsa_id.to_s], 0].max
      extras = linha.quantity - 1
      nos_bolsos = [extras, livres].min
      reservados[bolsa_id.to_s] += nos_bolsos if seco
      [bolsa&.item_name || bolsa_id, nos_bolsos, extras - nos_bolsos]
    end
    relatar = lambda do |linha, onde, nos_bolsos, pra_fora|
      puts "#{seco ? '[DRY_RUN] ' : ''}ficha #{linha.sheet_id} · #{linha.item_name} ×#{linha.quantity} " \
           "no bolso de #{onde}: #{nos_bolsos} em bolsos livres, #{pra_fora} para fora"
    end

    divididas = 0
    rel.find_each do |linha|
      next unless SheetItems::StowOnBeltService.slot_kind_for(linha) == 'consumable'

      # DRY_RUN só LÊ — sem transação nem trava: roda em prod com a mesa a jogar.
      if seco
        relatar.call(linha, *planejar.call(linha))
        divididas += 1
        next
      end

      SheetItem.transaction do
        # Mesma ordem de trava do resto da casa: ficha antes das linhas.
        Sheet.find(linha.sheet_id).lock!
        linha.lock!
        next unless linha.quantity > 1

        onde, nos_bolsos, pra_fora = planejar.call(linha)
        relatar.call(linha, onde, nos_bolsos, pra_fora)
        divididas += 1

        nos_bolsos.times do
          nova = linha.dup
          nova.quantity = 1
          nova.save!
        end

        if pra_fora.positive?
          fora = linha.dup
          props = (linha.props_json || {}).deep_dup.stringify_keys
          props.delete(ponteiro)
          fora.props_json = props
          fora.quantity = pra_fora
          gemea = SheetItem.stackable_match_for(fora)
          gemea ? gemea.update!(quantity: gemea.quantity + pra_fora) : fora.save!
        end

        linha.update!(quantity: 1)
      end
    end

    puts "dividir_pilhas_nos_bolsos: #{divididas} pilha(s) #{seco ? 'a dividir' : 'divididas'}."
  end
end
