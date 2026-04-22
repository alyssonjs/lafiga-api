module CharacterSheetEdits
  # General step em modo edit: persiste o nome no `Character` (coluna canonica)
  # e os campos NPC/player/notes em `sheet.metadata['general']` (jsonb).
  #
  # Por que metadata e nao colunas dedicadas? `playerName`, `isNPC`, `npcRole`,
  # `npcFaction`, `npcLocation`, `npcStatus`, `dmNotes` so existem em
  # `draft_data` durante a criacao — nao ha colunas no `Character` nem no
  # `Sheet`. Antes do fix B1.1 do relatorio de auditoria de steps, esse service
  # silenciosamente descartava todos esses campos em edit (so `name` chegava ao
  # banco) e `read` devolvia `isNPC: false` hardcoded. Agora roundtripamos via
  # metadata.
  class GeneralEditService < BaseSheetEditService
    GENERAL_META_KEYS = %w[playerName isNPC npcRole npcFaction npcLocation npcStatus dmNotes].freeze

    def step_key = 'general'

    def read
      gen = (sheet.metadata || {}).dig('general') || {}
      {
        'name'         => character.name,
        'level'        => sheet.current_level,
        'playerName'   => gen['playerName'],
        'isNPC'        => !!gen['isNPC'],
        'npcRole'      => gen['npcRole'],
        'npcFaction'   => gen['npcFaction'],
        'npcLocation'  => gen['npcLocation'],
        'npcStatus'    => gen['npcStatus'],
        'dmNotes'      => gen['dmNotes']
      }
    end

    protected

    def apply!
      character.name = data['name'] if data.key?('name')
      character.save! if character.changed?

      return unless GENERAL_META_KEYS.any? { |k| data.key?(k) }

      # ZE7 do segundo audit: read-modify-write em jsonb era last-write-wins entre
      # PATCHes paralelos. Sem row lock, dois requests concorrentes liam o mesmo
      # `metadata`, cada um sobrescrevia chaves do outro, e a versao "perdedora"
      # sumia. `with_lock` faz `BEGIN; SELECT FOR UPDATE; ...; COMMIT;` no row
      # `sheets`, serializando os PATCHes que tocam o mesmo sheet. O bloco fica
      # curto (so o merge em memoria + save!), entao o lock e barato.
      sheet.with_lock do
        meta = (sheet.metadata || {}).deep_stringify_keys
        gen  = (meta['general'] || {}).deep_dup
        GENERAL_META_KEYS.each do |k|
          next unless data.key?(k)
          v = data[k]
          # `isNPC` e booleano canonico — coerce JSON `"true"/"false"` ou nil.
          v = ActiveModel::Type::Boolean.new.cast(v) if k == 'isNPC'
          gen[k] = v
        end
        meta['general'] = gen
        sheet.metadata = meta
        sheet.save!
      end
    end
  end
end
