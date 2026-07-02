# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

group :development do
  gem 'reek'
  gem 'rake'
  # RuboCop is pinned exactly: when CI's bundler cannot reuse the lockfile it
  # resolves the Gemfile fresh, and an unpinned rubocop floats to a newer
  # release whose cops disagree with the locally vendored one. Upgrades are
  # deliberate: bump the pin, run `bundle update rubocop`, fix new offenses.
  gem 'rubocop', '1.88.1', require: false
  gem 'rubocop-performance', '1.26.1', require: false
  gem 'rubocop-rails', require: false
  gem 'rubocop-rspec', require: false
end

group :test do
  gem 'fakefs', require: 'fakefs/spec_helpers'
  gem 'rspec'
  gem 'simplecov', require: false
  gem 'webmock', require: false
end
