# syntax=docker/dockerfile:1
FROM ruby:2.7.3
RUN apt-get update -qq && apt-get install -y postgresql-client
RUN mkdir /lafiga-api
WORKDIR /lafiga-api
COPY Gemfile /lafiga-api/Gemfile
COPY Gemfile.lock /lafiga-api/Gemfile.lock
RUN gem install bundler:2.2.17
RUN bundle update listen
RUN bundle install
COPY . /lafiga-api

# Add a script to be executed every time the container starts.
COPY entrypoint.sh /usr/bin/
RUN chmod +x /usr/bin/entrypoint.sh
ENTRYPOINT ["entrypoint.sh"]
EXPOSE 3000

# Configure the main process to run when running the image
CMD ["rails", "server", "-b", "0.0.0.0"]