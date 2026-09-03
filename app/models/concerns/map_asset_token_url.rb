# frozen_string_literal: true

# Onde mora a URL do token da biblioteca de objetos.
#
# ⚠️ Era a MESMA linha copiada em `Monster` e `BasicNpc`, e o `CombatNpc` seria
# a terceira cópia. O endpoint do `map_assets` serve o blob com cache imutável
# e SEM gate de DM — o token é da mesa inteira.
#
# Path RELATIVO (sem host) de propósito: o front prefixa com a baseURL da API.
# Gravar o host absoluto no banco faria o token do dev apontar para `localhost`
# depois do deploy.
module MapAssetTokenUrl
  module_function

  def for(asset_id)
    return nil if asset_id.blank?

    "/api/v1/admin/map_assets/#{asset_id}/image?v=#{asset_id}"
  end
end
