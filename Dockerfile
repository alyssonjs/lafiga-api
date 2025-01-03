# syntax=docker/dockerfile:1
FROM ruby:3.2.2

# Instala o cliente do PostgreSQL e outras dependências do sistema
RUN apt-get update -qq && apt-get install -y build-essential libpq-dev postgresql-client

# Cria e define o diretório de trabalho
RUN mkdir /lafiga-api
WORKDIR /lafiga-api

# Adiciona o Gemfile e Gemfile.lock
COPY Gemfile /lafiga-api/Gemfile
COPY Gemfile.lock /lafiga-api/Gemfile.lock

# Instala o Bundler e as gemas necessárias comentando
RUN gem install bundler:2.2.17
RUN bundle install

# Adiciona o restante do código da aplicação
COPY . /lafiga-api

# Configura o script de entrypoint
COPY entrypoint.sh /usr/bin/
RUN chmod +x /usr/bin/entrypoint.sh
ENTRYPOINT ["entrypoint.sh"]

# Exponha a porta 3000 para o servidor Rails
EXPOSE 3000

# Comando padrão para iniciar o servidor Rails
CMD ["rails", "server", "-b", "0.0.0.0"]
