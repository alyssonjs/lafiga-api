# frozen_string_literal: true

# Onde mora a URL do token da biblioteca de objetos.
#
# ⚠️ Era a MESMA linha copiada em `Monster` e `BasicNpc`, e o `CombatNpc` seria
# a terceira cópia. O endpoint do `map_assets` serve o blob com cache imutável
# e SEM gate de DM — o token é da mesa inteira.
#
# ⚠️ O `?v=` é o id do BLOB da imagem, não o do asset: é ele que muda quando o
# Mestre troca a arte, e o cache imutável só larga a imagem velha se a URL
# mudar. Com o id do asset no `v=`, o navegador que já tinha visto o token o
# mostraria velho para sempre. É também a mesma URL que a biblioteca serve
# (`MapAssetSerializer.image_url_for`), então o navegador baixa a arte uma vez.
#
# Path RELATIVO (sem host) de propósito: o front prefixa com a baseURL da API.
# Gravar o host absoluto no banco faria o token do dev apontar para `localhost`
# depois do deploy.
module MapAssetTokenUrl
  module_function

  # Pelo id — quem só tem o id à mão (a escrita do `combat_npc`). Uma consulta.
  def for(asset_id)
    return nil if asset_id.blank?

    montar(asset_id, blob_id_da_imagem(asset_id))
  end

  # Pelo registro já carregado. Nas listagens, pré-carregar
  # `token_map_asset: :image_attachment` deixa isto sem consulta nenhuma: o id
  # do blob está na linha do anexo, sem precisar do blob.
  def for_asset(asset_id, asset)
    return nil if asset_id.blank?

    montar(asset_id, asset&.image_attachment&.blob_id)
  end

  # Sem anexo (asset apagado): recua para o id do asset — a URL de sempre, que
  # o endpoint responde com 404.
  def montar(asset_id, blob_id)
    "/api/v1/admin/map_assets/#{asset_id}/image?v=#{blob_id || asset_id}"
  end

  def blob_id_da_imagem(asset_id)
    ActiveStorage::Attachment.where(record_type: 'MapAsset', record_id: asset_id, name: 'image').pick(:blob_id)
  end

  private_class_method :montar, :blob_id_da_imagem
end
