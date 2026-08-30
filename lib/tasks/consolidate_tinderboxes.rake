# Consolida as variantes homebrew de "caixa de fogo" na canonica,
# PRESERVANDO os usos que cada jogador contava no nome.
#
#   bundle exec rake dnd:consolidate_tinderboxes            # DRY RUN (padrao)
#   APPLY=1 bundle exec rake dnd:consolidate_tinderboxes    # aplica
#
# ## A leitura, e a evidencia dela
#
# Mesma assinatura do `dnd:consolidate_sos_kits`, e verificada nos dados antes
# de escrever esta linha: cada variante esta com `quantity: 1`, e a mais comum
# ("caixa de fogo x10") aparece em SEIS fichas de personagens DIFERENTES. Isso
# descarta "xN = N caixas" (seria quantidade, e num inventario so) e confirma
# "xN = N usos restantes": cada jogador criou a propria entrada de catalogo e
# renomeava conforme gastava, porque nao havia onde contar.
#
# As seis clones nao tem categoria, peso nem preco — nasceram do `ItemResolver`,
# que CRIA registro novo quando o nome digitado nao casa com o catalogo. So a
# `caixa-de-fogo` tem os dados do PHB (5 pp, 0,5 kg).
#
# ## O que faz, nesta ordem (a ordem importa)
#
#   1. reponta o `sheet_item` do jogador para a caixa canonica;
#   2. grava os usos restantes em `props_json['uses_remaining']`;
#   3. so entao apaga a entrada homebrew do catalogo.
#
# Apagar antes deixaria item orfao na bolsa — o mesmo cuidado do
# `dnd:consolidate_sos_kits`.
#
# ⚠️ A selecao e por `item_id`, NAO por `item_index`: a FK e no id, e o
# `destroy!` bate na FK se sobrar linha apontada. Por isso tambem: tudo dentro
# de UMA transacao.
#
# ⚠️ NAO esta no hook de deploy: mexe na bolsa de doze jogadores.
namespace :dnd do
  CANONICAL_TINDERBOX = 'caixa-de-fogo'

  # api_index => usos restantes lidos do NOME. `nil` = sem numero no nome,
  # entao fica CHEIA (a ausencia da chave ja significa cheio).
  TINDERBOX_VARIANTS = {
    'caixa-de-fogo-x10' => 10,
    'caixa-de-fogo-10x' => 10,
    'caixa-de-fogo-10'  => 10,
    'caixa-de-fogo-x9'  => 9,
    'caixa-de-fogo-6'   => 6,
    'caixa-de-fogo-4'   => 4,
  }.freeze

  desc 'Consolida as "caixa de fogo" na canonica preservando usos (APPLY=1 aplica)'
  task consolidate_tinderboxes: :environment do
    apply = ENV['APPLY'].present?
    canonica = Item.find_by(api_index: CANONICAL_TINDERBOX)
    if canonica.nil?
      abort "[dnd:consolidate_tinderboxes] #{CANONICAL_TINDERBOX} nao existe — rode `dnd:seed_item_uses` antes."
    end

    teto = (canonica.props || {})['uses_max'].to_i
    if teto <= 0
      abort '[dnd:consolidate_tinderboxes] a caixa canonica nao declara `uses_max` — rode `dnd:seed_item_uses` antes.'
    end
    puts "[dnd:consolidate_tinderboxes]#{' DRY RUN —' unless apply} canonica tem #{teto} usos"

    movidos = 0
    apagados = 0

    ActiveRecord::Base.transaction do
      TINDERBOX_VARIANTS.each do |api_index, usos|
        item = Item.find_by(api_index: api_index)
        next puts "  [skip] #{api_index}: nao existe" if item.nil?

        SheetItem.where(item_id: item.id).each do |si|
          dono = si.sheet&.character&.name
          restante = usos.nil? ? teto : [usos, teto].min
          puts "  #{dono.inspect}: #{si.item_name.inspect} -> Caixa de fogo com #{restante}/#{teto} usos"
          movidos += 1
          next unless apply

          props = (si.props_json || {}).deep_dup.stringify_keys
          # Cheia nao grava chave nenhuma — ausente JA significa cheia.
          if restante >= teto
            props.delete('uses_remaining')
          else
            props['uses_remaining'] = restante
          end
          si.update!(
            item_id: canonica.id,
            item_index: canonica.api_index,
            item_name: canonica.name,
            category: canonica.category,
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
