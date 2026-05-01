# frozen_string_literal: true

# Audit + provisão das subclasses canônicas que estavam faltando ou desalinhadas
# entre front e backend após a auditoria cross-class (Bárbaro Zelote, Bardo
# Glamour, ajustes de nomes em outras classes).
#
# Idempotente — pode rodar múltiplas vezes sem efeitos colaterais.
#
# Uso:
#   bundle exec rails dnd:audit_canonical_classes
#   bundle exec rails dnd:provision_missing_subklasses
#
# Após provisionar, rode `dnd:apply_subclass_overrides` para popular features
# das novas subclasses a partir do YAML.

namespace :dnd do
  # Subclasses que precisam existir após o fix cross-class.
  # Cada entrada: { klass_api_index, sub_api_index, sub_name }
  CROSS_CLASS_CANONICAL_TARGETS = [
    # Bárbaro: Caminho do Zelote (XGtE) — estava ausente
    { klass: 'barbarian', sub_api: 'zealot',             sub_name: 'Caminho do Zelote' },
    # Bardo: Colégio do Glamour (XGtE) — estava só no canonical_indexes, sem features
    { klass: 'bard',      sub_api: 'colegio-do-glamour', sub_name: 'Colégio do Glamour' }
  ].freeze

  desc 'Audita estado das subclasses canônicas cross-class (Zelote, Glamour, etc.)'
  task audit_canonical_classes: :environment do
    puts "Audit das subclasses canônicas cross-class:"
    CROSS_CLASS_CANONICAL_TARGETS.each do |target|
      klass = Klass.find_by(api_index: target[:klass])
      unless klass
        puts "  ❌ Klass '#{target[:klass]}' não encontrada"
        next
      end
      sub = klass.sub_klasses.find_by(api_index: target[:sub_api])
      if sub.nil?
        puts "  ⚠️  #{target[:klass]}/#{target[:sub_api]}: AUSENTE — precisa criar"
      elsif sub.name != target[:sub_name]
        puts "  ⚠️  #{target[:klass]}/#{target[:sub_api]}: nome '#{sub.name}' (esperado '#{target[:sub_name]}')"
      elsif sub.levels_json.blank? || sub.levels_json == '[]'
        puts "  ⚠️  #{target[:klass]}/#{target[:sub_api]}: sem levels_json (rode apply_subclass_overrides)"
      else
        puts "  ✅ #{target[:klass]}/#{target[:sub_api]}: '#{sub.name}' OK"
      end
    end
  end

  desc 'Cria SubKlasses ausentes (Zelote, Glamour) — idempotente'
  task provision_missing_subklasses: :environment do
    puts "Provisionando subklasses ausentes…"
    CROSS_CLASS_CANONICAL_TARGETS.each do |target|
      klass = Klass.find_by(api_index: target[:klass])
      unless klass
        puts "  ❌ Klass '#{target[:klass]}' não encontrada — skip"
        next
      end
      sub = SubKlass.find_or_initialize_by(api_index: target[:sub_api], klass_id: klass.id)
      changed = false
      if sub.new_record?
        sub.name = target[:sub_name]
        changed = true
        puts "  • criando #{target[:klass]}/#{target[:sub_api]} ('#{target[:sub_name]}')"
      elsif sub.name != target[:sub_name]
        sub.name = target[:sub_name]
        changed = true
        puts "  • atualizando nome #{target[:klass]}/#{target[:sub_api]} → '#{target[:sub_name]}'"
      else
        puts "  • #{target[:klass]}/#{target[:sub_api]} já existe (skip)"
      end
      sub.save! if changed && sub.changed?
    end
    puts "Concluído. Próximo passo: bundle exec rails dnd:apply_subclass_overrides"
  end
end
