$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'sidekiq'
require 'sidekiq/capsule'
require 'sidekiq/prioritized_queues'

require 'minitest/autorun'

Sidekiq.default_configuration.redis = { url: 'redis://localhost/15' }

# Sidekiq 7 hands each capsule to the fetcher rather than an options hash.
def build_capsule(queues: %w[default], non_prioritized: [])
  config = Sidekiq.default_configuration
  config[:non_prioritized_queues] = non_prioritized

  capsule = Sidekiq::Capsule.new('test', config)
  capsule.queues = queues
  capsule
end

class MockWorker
  include Sidekiq::Worker
  sidekiq_options priority: ->(arg) { arg * 10 }

  def perform(arg)
  end
end

class MockWorkerFixedPrio
  include Sidekiq::Worker
  sidekiq_options priority: 2

  def perform(arg)
  end
end

class MockWorkerNonPrioritizedQueue
  include Sidekiq::Worker
  sidekiq_options queue: 'non_prio'

  def perform(arg)
  end
end
