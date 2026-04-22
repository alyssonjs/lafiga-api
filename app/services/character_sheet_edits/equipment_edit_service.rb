module CharacterSheetEdits
  # Bug B6 do relatorio de auditoria de steps: este service era um "thin
  # passthrough" — apenas gravava metadata.equipment.{mode,choices,generic} e
  # imprimia warning ("inventario ao vivo nao alterado"). Em modo edit, isso
  # criava um descompasso: o usuario abria o step Equipment, trocava de
  # `class-preset` para `gold` (ou refazia escolhas), salvava e a UI mostrava
  # as novas selecoes — mas o inventario do personagem nao mudava nada.
  #
  # Solucao desta versao:
  #   1. Sempre persiste o metadata (preserva preferencias e roundtrip do
  #      wizard).
  #   2. Aceita opcionalmente `equipmentPicks` (array de itens ja resolvidos
  #      pelo front), que triggera reprovision IDEMPOTENTE de `SheetItem`s
  #      auto-provisionados (source='class'), preservando os items que o
  #      jogador adicionou via UI (CRUD live de inventario, sem
  #      provisioning_run_id no props_json).
  #   3. Quando `equipmentPicks` NAO vem, mantem comportamento legado de
  #      passthrough + warning — isso garante compat com clientes antigos que
  #      so editam preferencia.
  #
  # O CRUD de inventario continua funcionando normalmente via
  # `/api/v1/player/sheets/:id/sheet_items` (esses items NAO carregam
  # `provisioning_run_id` e logo NUNCA sao tocados aqui).
  class EquipmentEditService < BaseSheetEditService
    META_EQUIPMENT_KEYS = %w[equipmentMode equipmentChoices equipmentGenericSelections startingGoldRolled].freeze

    def step_key = 'equipment'

    def read
      meta = sheet.metadata || {}
      {
        'equipmentMode'    => meta.dig('equipment', 'mode'),
        'equipmentChoices' => Array(meta.dig('equipment', 'choices')),
        'equipmentGenericSelections' => meta.dig('equipment', 'generic') || {},
        'startingGoldRolled' => meta.dig('equipment', 'startingGoldRolled')
      }
    end

    protected

    def apply!
      persist_metadata!
      reprovisioned = reprovision_items_if_picks_given!
      sheet.save!
      return if reprovisioned

      warn!('inventario ao vivo nao alterado: envie `equipmentPicks` para reprovisionar ' \
            'ou use os endpoints de SheetItem para editar itens manualmente')
    end

    private

    def persist_metadata!
      meta = (sheet.metadata || {}).deep_stringify_keys
      eq = (meta['equipment'] || {}).deep_dup
      eq['mode'] = data['equipmentMode'] if data.key?('equipmentMode')
      eq['choices'] = Array(data['equipmentChoices']) if data.key?('equipmentChoices')
      eq['generic'] = data['equipmentGenericSelections'] if data.key?('equipmentGenericSelections')
      eq['startingGoldRolled'] = data['startingGoldRolled'] if data.key?('startingGoldRolled')
      meta['equipment'] = eq
      sheet.metadata = meta
    end

    # Substitui o lote de SheetItems com source='class' provisionados pelo
    # wizard, preservando customizacoes (`equipped`/`slot`/`notes`) e itens
    # adicionados manualmente pelo jogador (sem `provisioning_run_id`).
    #
    # Retorna `true` quando reprovision foi realizado (mesmo que tenha
    # inserido 0 linhas — ex.: payload zerou os picks intencionalmente).
    # Retorna `false` quando o caller nao pediu reprovision.
    #
    # NOTA: a logica e identica a `CharacterProvisioningService#reprovision_items!`.
    # Mantemos duplicada por enquanto porque o original e private; em batch
    # futuro extrair para `Equipment::ReprovisionItemsService`.
    def reprovision_items_if_picks_given!
      return false unless data.key?('equipmentPicks')
      raw = data['equipmentPicks']
      return false unless raw.is_a?(Array)

      run_id = SecureRandom.uuid
      now = Time.current

      prior = SheetItem
              .where(sheet_id: sheet.id, source: 'class')
              .where("props_json ? 'provisioning_run_id'")
              .to_a
      # Indexamos por DUAS chaves pra ser robusto contra a divergencia entre
      # `item_index` no DB (auto-populado pelo callback `resolve_catalog_item`)
      # e o payload do front (que historicamente nao envia item_index). A
      # primeira chave que bater no lookup vence.
      overrides = {}
      prior.each do |it|
        snap = { equipped: it.equipped, slot: it.slot, notes: it.notes }
        overrides[[it.item_index, it.item_name]] = snap
        overrides[[nil, it.item_name]] ||= snap
      end

      # ZX5 do segundo audit: antes era `delete_all` SEGUIDO de `insert_all`
      # SEM transacao + `rescue StandardError => warn + return false`. Se
      # qualquer coisa entre o delete e o insert (build da row, validacao
      # de coluna, falha de DB transient) levantasse, o rescue silenciava
      # a exception e o usuario perdia o inventario inteiro com so um warn
      # nao-bloqueante. O wrapper externo em BaseSheetEditService#call ja
      # esta dentro de uma `ActiveRecord::Base.transaction`, mas o rescue
      # local engole a exception ANTES dela subir, entao a outer tx commita
      # com itens deletados. Solucao: savepoint com `requires_new: true`,
      # forcar rollback do savepoint quando a exception ocorre dentro do
      # bloco — restaura prior items e mantem o resto do PATCH (metadata)
      # intacto.
      reprovisioned_rows = nil
      ActiveRecord::Base.transaction(requires_new: true) do
        SheetItem
          .where(sheet_id: sheet.id, source: 'class')
          .where("props_json ? 'provisioning_run_id'")
          .delete_all

        rows = raw.map do |it|
          attrs = it.is_a?(Hash) ? it.deep_stringify_keys : {}
          next if attrs.empty?
          item_index = attrs['item_index'] || attrs['index']
          item_name  = (attrs['item_name'] || attrs['name']).to_s
          next if item_name.blank? && item_index.blank?
          ovr = overrides[[item_index, item_name]] || overrides[[nil, item_name]]
          props = (attrs['props'] || attrs['props_json'] || {})
          props = props.deep_stringify_keys if props.is_a?(Hash)
          props = {} unless props.is_a?(Hash)
          props['provisioning_run_id'] = run_id
          {
            sheet_id: sheet.id,
            item_index: item_index,
            item_name: item_name,
            category: attrs['category'],
            quantity: (attrs['quantity'] || 1).to_i,
            equipped: ovr ? ovr[:equipped] : !!attrs['equipped'],
            slot: ovr&.dig(:slot) || attrs['slot'],
            source: 'class',
            props_json: props,
            notes: ovr&.dig(:notes),
            created_at: now,
            updated_at: now
          }
        end.compact

        SheetItem.insert_all(rows) if rows.any?
        reprovisioned_rows = rows.size
      end

      Rails.logger.info(
        "EquipmentEditService: reprovisioned #{reprovisioned_rows} 'class' items for sheet #{sheet.id} " \
        "(run=#{run_id}, prior=#{prior.size}, preserved=#{overrides.size})"
      )
      true
    rescue StandardError => e
      # Savepoint ja sofreu rollback automatico (Postgres fecha o subtransaction
      # ao receber exception). Prior items continuam INTACTOS porque a
      # transacao interna nunca foi commitada. So reportamos para a UI.
      warn!("reprovision de equipment falhou: #{e.class}: #{e.message}")
      Rails.logger.warn "EquipmentEditService: reprovision failed: #{e.class}: #{e.message}"
      false
    end
  end
end
