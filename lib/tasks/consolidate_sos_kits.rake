# Consolida as variantes homebrew de "kit SOS" no Kit de Primeiros Socorros
# canonico, PRESERVANDO os usos que cada jogador contava no nome.
#
#   bundle exec rake dnd:consolidate_sos_kits            # DRY RUN (padrao)
#   APPLY=1 bundle exec rake dnd:consolidate_sos_kits    # aplica
#
# ## A leitura, e a evidencia dela
#
# Cada variante esta em UMA bolsa, com `quantity: 1`, de um jogador DIFERENTE.
# Isso descarta "xN = N kits" (seria quantidade) e confirma "xN = N usos
# restantes": cada jogador criou a propria entrada de catalogo e renomeava o
# item conforme gastava. Era a unica forma de contar antes de existir
# `uses_remaining`.
#
# ## O que faz, nesta ordem (a ordem importa)
#
#   1. reponta o `sheet_item` do jogador para o kit canonico;
#   2. grava os usos restantes em `props_json['uses_remaining']`;
#   3. so entao apaga a entrada homebrew do catalogo.
#
# Apagar antes deixaria item orfao na bolsa — o mesmo cuidado do
# `dnd:dedupe_tools`.
#
# ⚠️ A selecao e por `item_id`, NAO por `item_index`: a FK e no id, e ha linha
# com indice prefixado (`gi-kit-de-sos-x10`, prefixo que o mapper do front poe).
# Filtrar por indice perdia essa linha e o `destroy!` batia na FK — DEPOIS de ja
# ter repontado outra bolsa. Por isso tambem: tudo dentro de UMA transacao.
#
# ⚠️ NAO esta no hook de deploy: mexe na bolsa de seis jogadores.
namespace :dnd do
  CANONICAL_SOS = 'kit-de-primeiros-socorros'

  # api_index => usos restantes lidos do NOME. `nil` = sem numero no nome,
  # entao fica CHEIO (a ausencia da chave ja significa cheio).
  SOS_VARIANTS = {
    'kit-de-sos-x10' => 10,
    'kit-sos-x10'    => 10,
    'kit-sos-x9'     => 9,
    'kit-sos-x3'     => 3,
    'kit-sos-7pl'    => 7,
    'kit-sos'        => nil,
  }.freeze

  desc 'Consolida os "kit SOS" no kit canonico preservando usos (APPLY=1 aplica)'
  task consolidate_sos_kits: :environment do
    apply = ENV['APPLY'].present?
    canonico = Item.find_by(api_index: CANONICAL_SOS)
    if canonico.nil?
      abort "[dnd:consolidate_sos_kits] #{CANONICAL_SOS} nao existe — rode `dnd:seed_item_uses` antes."
    end
    teto = (canonico.props || {})['uses_max'].to_i
    puts "[dnd:consolidate_sos_kits]#{' DRY RUN —' unless apply} canonico tem #{teto} usos"

    movidos = 0
    apagados = 0

    ActiveRecord::Base.transaction do
    SOS_VARIANTS.each do |api_index, usos|
      item = Item.find_by(api_index: api_index)
      next puts "  [skip] #{api_index}: nao existe" if item.nil?

      afetados = SheetItem.where(item_id: item.id)
      afetados.each do |si|
        dono = si.sheet&.character&.name
        restante = usos.nil? ? teto : [usos, teto].min
        puts "  #{dono.inspect}: #{si.item_name.inspect} -> Kit de Primeiros Socorros com #{restante}/#{teto} usos"
        movidos += 1
        next unless apply

        props = (si.props_json || {}).deep_dup.stringify_keys
        # Cheio nao grava chave nenhuma — ausente JA significa cheio.
        if restante >= teto
          props.delete('uses_remaining')
        else
          props['uses_remaining'] = restante
        end
        si.update!(
          item_id: canonico.id,
          item_index: canonico.api_index,
          item_name: canonico.name,
          category: 'tools',
          props_json: props,
        )
      end

      apagados += 1
      item.destroy! if apply
    end
    end

    puts "  #{movidos} item(ns) de bolsa repontado(s), #{apagados} entrada(s) de catalogo a apagar"
    puts '  (nada foi gravado — repita com APPLY=1)' unless apply
  end
end
