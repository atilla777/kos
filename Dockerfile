FROM public.ecr.aws/docker/library/ruby:3.4.10-slim

RUN apt-get update && apt-get install -y --no-install-recommends build-essential libsqlite3-dev pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .
RUN mkdir -p log tmp storage && chmod -R a+rwX log tmp storage

ENV RAILS_ENV=development
ENV HOME=/tmp
CMD ["bin/rails", "server", "-b", "0.0.0.0", "-p", "3137"]
