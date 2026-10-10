# frozen_string_literal: true

# Os DADOS DO SERVIDOR (09/10; L0.6, plano B2). A regra está em Dados::Verifica.
#
#   bin/rails "dados:verificar[ID]"   # reconfere o selo e, na fonte hmac, os próprios dados; sai com 1 se não conferir
namespace :dados do
  desc 'Reconfere uma rolagem do servidor: o selo e, na fonte hmac, os próprios dados. bin/rails "dados:verificar[ID]"'
  task :verificar, [:id] => :environment do |_, args|
    rolagem = Dados::Rolagem.find_by(id: args[:id])
    abort "rolagem #{args[:id].inspect} não existe" unless rolagem

    resultado = Dados::Verifica.call(rolagem)
    puts resultado.linhas
    abort 'NÃO CONFERE' unless resultado.ok
  end
end
