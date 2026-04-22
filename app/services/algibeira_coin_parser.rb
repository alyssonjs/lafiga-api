# Detecta itens de inventario que na verdade descrevem moedas na algibeira
# (ex.: "Uma algibeira contendo 15 po") vindos do XLSX / PHB PT-BR.
module AlgibeiraCoinParser
  module_function

  ZERO_WALLET = { 'cp' => 0, 'sp' => 0, 'ep' => 0, 'gp' => 0, 'pp' => 0 }.freeze

  # True se o nome parece ser uma algibeira com valor monetario embutido.
  def pouch_coin_item?(name)
    return false if name.blank?

    n = ActiveSupport::Inflector.transliterate(name.to_s).downcase
    return false unless n.include?('algibeira')

    parse_pouch_wallet(name).values.any?(&:positive?)
  end

  # Extrai { "cp"=>..., "sp"=>... } ou hash vazio se nada reconhecido.
  def parse_pouch_wallet(str)
    out = ZERO_WALLET.dup
    s = ActiveSupport::Inflector.transliterate(str.to_s).downcase

    s.scan(/(\d+)\s*(?:pc|cobre)\b/) { out['cp'] += Regexp.last_match(1).to_i }
    s.scan(/(\d+)\s*(?:pp|prata)\b/) { out['sp'] += Regexp.last_match(1).to_i }
    s.scan(/(\d+)\s*(?:pe|electrum)\b/) { out['ep'] += Regexp.last_match(1).to_i }
    s.scan(/(\d+)\s*(?:po|ouro|gp)\b/) { out['gp'] += Regexp.last_match(1).to_i }
    s.scan(/(\d+)\s*(?:ppl|platina)\b/) { out['pp'] += Regexp.last_match(1).to_i }

    out
  end
end
