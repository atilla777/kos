source "https://rubygems.org"

gem "rails", "8.1.3.1"
gem "sqlite3", "~> 2.9"
gem "puma", "~> 8.0"
gem "json_schemer", require: false

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

gem "bootsnap", require: false

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "rspec-rails", "~> 8.0"
  gem "rubocop-rails-omakase", "~> 1.1", require: false
  gem "rubocop-rspec", require: false
  gem "rubocop-rspec_rails", require: false
end

group :development do
  gem "brakeman", require: false
  gem "bundler-audit", require: false
end
