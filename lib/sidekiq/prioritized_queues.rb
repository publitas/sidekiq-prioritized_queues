require 'sidekiq/prioritized_queues/version'
require 'sidekiq/prioritized_queues/middleware'
require 'sidekiq/prioritized_queues/fetch'
require 'sidekiq/prioritized_queues/monkeypatches'
require 'sidekiq/prioritized_queues/config'

# Add the Client middleware that takes care of setting up the priority property
# on the messages being queued.
Sidekiq.configure_server do |config|
  gem_config = Sidekiq::PrioritizedQueues::Config.new(config)
  config.merge!(gem_config.config)

  config.client_middleware do |chain|
    chain.add Sidekiq::PrioritizedQueues::Middleware, ignored_queues: gem_config.ignored_queues
  end
  # Set up the fetcher as the priority based one too.
  config[:fetch] = Sidekiq::PrioritizedQueues::Fetch.new(config)
end

Sidekiq.configure_client do |config|
  gem_config = Sidekiq::PrioritizedQueues::Config.new(config)
  config.merge!(gem_config.config)

  config.client_middleware do |chain|
    chain.add Sidekiq::PrioritizedQueues::Middleware, ignored_queues: gem_config.ignored_queues
  end
end
