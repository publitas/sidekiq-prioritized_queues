source 'https://rubygems.org'

# Specify your gem's dependencies in sidekiq-prioritized_queues.gemspec
gemspec

# Lets CI pin a specific Sidekiq across the supported range.
gem 'sidekiq', ENV['SIDEKIQ_VERSION'] if ENV['SIDEKIQ_VERSION']
