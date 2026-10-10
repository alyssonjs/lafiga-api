# frozen_string_literal: true

# OUTRA SESSÃO do Postgres, fora do pool do Rails, para segurar uma trava (advisory lock) como outro processo faria
# (L0.4/L0.5: a trava por mundo e a trava global do relógio).
#
# ⚠️ Fora do pool de propósito: com a transação por exemplo, o Rails prende a conexão do teste à thread, e o
# `connection_pool.checkout` pode devolver ESSA mesma conexão. Na mesma sessão a trava é reentrante, e o "outro
# processo" não trava nada (a spec passava sozinha e falhava na suíte inteira).
module OutraSessaoPg
  def com_outra_sessao_pg
    cfg = ActiveRecord::Base.connection_config
    conexao = PG.connect(
      host: cfg[:host], port: cfg[:port] || 5432, user: cfg[:username], password: cfg[:password], dbname: cfg[:database],
    )
    yield conexao
  ensure
    conexao&.close
  end
end

RSpec.configure { |config| config.include OutraSessaoPg }
