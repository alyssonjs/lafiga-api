# frozen_string_literal: true

# Os DADOS DO SERVIDOR (09/10; L0.6, plano B2). A vila e a IA rolam aqui, não no navegador.
#
# - `Dados::Expressao`: a gramática dos dados (`2d20kh1+3`);
# - `Dados::Fonte::Segura` (as ações do jogador) e `Dados::Fonte::Hmac` (o mundo: a chave do evento decide os dados);
# - `Dados::Rola`: rola e grava a `Dados::Rolagem` selada, sem repetir a mesma chave;
# - `Dados::Teste`: o teste de d20 (atributo, proficiência, especialização, vantagem, CD);
# - `Dados::Verifica` (`bin/rails "dados:verificar[ID]"`): reconfere uma rolagem gravada.
module Dados
  # O segredo das fontes e do selo, derivado do `secret_key_base`: o mesmo em todo processo do ambiente, outro em cada
  # ambiente. Trocar o `secret_key_base` invalida os selos antigos.
  def self.segredo
    @segredo ||= Rails.application.key_generator.generate_key('lafiga/dados/v1', 32)
  end
end
