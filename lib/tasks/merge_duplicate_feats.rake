# frozen_string_literal: true

namespace :feats do
  # Talentos que existiam DUAS VEZES no catálogo, com nomes diferentes para a mesma
  # regra. Quando `Talentos.docx` virou a fonte de verdade, renomear o keeper para o
  # nome do documento passou a colidir com a linha solta — daí esta fusão.
  #
  # ⚠️ Direção: o KEEPER é quem tem a REGRA (special_rules) e está no
  # `feats_improved.yml`; o perdedor é a linha que entrou por fora do import.
  # Fichas que apontem para o perdedor são repontadas antes de apagar.
  #
  # Idempotente: sem o perdedor, não faz nada. `DRY_RUN=1` relata sem gravar.
  FUSOES = {
    # perdedor            => keeper
    'atirador_agucado'    => 'atirador_eximio',
  }.freeze

  desc 'Funde talentos duplicados (perdedor -> keeper), repontando as fichas'
  task merge_duplicates: :environment do
    seco = ENV['DRY_RUN'] == '1'
    puts "=== Fusão de talentos duplicados#{seco ? ' (DRY RUN)' : ''} ==="

    FUSOES.each do |perdedor_key, keeper_key|
      perdedor = Feat.find_by(api_index: perdedor_key)
      keeper   = Feat.find_by(api_index: keeper_key)

      next puts("  #{perdedor_key}: já não existe — nada a fazer") if perdedor.nil?
      next puts("  ⚠️ #{keeper_key}: KEEPER não encontrado, abortando este par") if keeper.nil?

      usos = SheetFeat.where(feat_id: perdedor.id)
      puts "  #{perdedor.name.inspect} (##{perdedor.id}) -> #{keeper.name.inspect} (##{keeper.id}) · fichas: #{usos.count}"
      next if seco

      ActiveRecord::Base.transaction do
        usos.find_each do |sf|
          # Índice/uso duplo: se a ficha JÁ tem o keeper, o vínculo do perdedor
          # simplesmente some — somar duas vezes o mesmo talento seria pior.
          if SheetFeat.exists?(sheet_id: sf.sheet_id, feat_id: keeper.id)
            sf.destroy!
          else
            sf.update!(feat_id: keeper.id)
          end
        end
        perdedor.destroy!
      end
      puts '     fundido.'
    end

    puts "Total de talentos: #{Feat.count}"
  end
end
