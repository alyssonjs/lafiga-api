# frozen_string_literal: true

module Klasses
  # FASE 5 do editor de classes — o que o mestre muda chega às fichas que JÁ
  # existem. Molde literal de `Races::ResyncSummaries`.
  #
  # ⚠️ A mecânica propaga sozinha (o produtor lê `ClassRules` a cada summary),
  # mas a VITRINE é um snapshot materializado no provisionamento: proficiências,
  # perícias e ferramentas ficam presas no `class_summary`. O resultado é o pior
  # dos dois mundos — o personagem passa a ter a proficiência nova em combate e a
  # ficha não lista nada que explique porquê.
  #
  # ⚠️ E o conserto óbvio — recompor o snapshot pela regra — APAGA A ESCOLHA DO
  # JOGADOR. `ClassRules.apply` clampa `first(choose)` em DOIS sítios
  # (`class_rules.rb` ≈581 e ≈1795): se o mestre reduzir `choose` de 2 para 1, a
  # perícia que o jogador escolheu simplesmente some do snapshot, sem erro e sem
  # aviso. Por isso a união preservadora abaixo, e por isso o que a regra deixou
  # de oferecer sai RELATADO em vez de sair calado.
  class ResyncSummaries
    Relatorio = Struct.new(:vistas, :mudadas, :detalhes, keyword_init: true)

    # Campos do snapshot que guardam ESCOLHA do jogador. `armor`/`weapons` não
    # entram: são concedidos pela regra, sem escolha por baixo.
    CAMPOS_DE_ESCOLHA = %w[skills tools].freeze

    def self.call(klass_id: nil, sub_klass_id: nil, dry_run: false)
      new(klass_id: klass_id, sub_klass_id: sub_klass_id, dry_run: dry_run).call
    end

    def initialize(klass_id: nil, sub_klass_id: nil, dry_run: false)
      @klass_id = klass_id
      @sub_klass_id = sub_klass_id
      @dry_run = dry_run
      @detalhes = []
    end

    def call
      vistas = 0
      mudadas = 0

      escopo.find_each do |sheet|
        vistas += 1
        antes = snapshot_atual(sheet)
        depois = recompoe(sheet, antes)
        next if depois.nil? || depois == antes

        mudadas += 1
        @detalhes << { sheet_id: sheet.id, mudou: (antes.keys | depois.keys).select { |k| antes[k] != depois[k] } }
        next if @dry_run

        # A dupla escrita (coluna + `metadata['class_summary']`, que VENCE na
        # leitura) vive no rebuilder: um gravador só para os dois caminhos.
        ClassSummaryRebuilder.new(sheet).persist!(depois)
      end

      Relatorio.new(vistas: vistas, mudadas: mudadas, detalhes: @detalhes)
    end

    private

    def escopo
      base = Sheet.joins(:sheet_klasses).distinct
      base = base.where(sheet_klasses: { klass_id: @klass_id }) if @klass_id.present?
      base = base.where(sheet_klasses: { sub_klass_id: @sub_klass_id }) if @sub_klass_id.present?
      base
    end

    # ⚠️ Compara contra o que o LEITOR vê: o override em
    # `metadata['class_summary']` vence a coluna (`sheets_controller.rb:219`).
    # Comparar com a coluna diria "mudou" em ficha que não mudou, e vice-versa.
    def snapshot_atual(sheet)
      do_meta = (sheet.metadata || {})['class_summary']
      return do_meta.deep_stringify_keys if do_meta.is_a?(Hash) && do_meta.present?

      col = sheet.read_attribute(:class_summary)
      col.is_a?(Hash) ? col.deep_stringify_keys : {}
    end

    def recompoe(sheet, antes)
      novo = ClassSummaryRebuilder.new(sheet).compute
      return nil unless novo.is_a?(Hash)

      preserva_escolhas(sheet, antes, novo)
    end

    # União preservadora: a lista final é a da REGRA unida ao que o jogador já
    # tinha E que a regra AINDA oferece. O que saiu do catálogo da regra é
    # removido, mas entra em `detalhes` — o mestre tem de poder saber que a
    # edição dele custou uma escolha a alguém.
    def preserva_escolhas(sheet, antes, novo)
      regra = ClassRules.find(api_da_classe(sheet)) || {}

      CAMPOS_DE_ESCOLHA.each do |campo|
        antigos = Array(antes[campo]).map(&:to_s)
        next if antigos.empty?

        atuais = Array(novo[campo]).map(&:to_s)
        opcoes = opcoes_da_regra(regra, campo)

        # ⚠️ NUNCA apaga. MEDIDO: `ClassRules.apply` clampa `first(choose)` mas
        # NÃO filtra pelo catálogo — perícia que saiu das `options` continua a
        # sair de lá. Ou seja, "sumir" da ficha só poderia vir DESTE serviço; e
        # tirar a escolha de um jogador porque o mestre mexeu no catálogo é
        # exatamente o estrago que ele existe para não fazer. Relata e mantém:
        # quem decide o que fazer com a divergência é o mestre, não o resync.
        fora_do_catalogo = opcoes.nil? ? [] : (antigos - opcoes)
        if fora_do_catalogo.any?
          @detalhes << { sheet_id: sheet.id, campo: campo, removidos: fora_do_catalogo,
                         motivo: 'a regra deixou de oferecer estas opções (mantidas na ficha)' }
        end

        novo[campo] = (atuais | antigos)
      end

      novo
    end

    # `nil` = "não sei quais são as opções" (diferente de "não há nenhuma").
    def opcoes_da_regra(regra, campo)
      return nil unless campo == 'skills'

      bloco = regra[:skill_proficiencies]
      return nil unless bloco.is_a?(Hash)

      opcoes = bloco[:options]
      return nil if opcoes == :any || opcoes.blank?

      Array(opcoes).map(&:to_s)
    end

    def api_da_classe(sheet)
      sheet.sheet_klasses.order(level: :desc, id: :asc).first&.klass&.api_index
    end
  end
end
