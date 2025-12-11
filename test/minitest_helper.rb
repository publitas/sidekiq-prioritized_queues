$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'sidekiq'
require 'sidekiq/prioritized_queues'

require 'minitest/autorun'

REDIS = Sidekiq::RedisConnection.create(
  url: 'redis://localhost/15',
)

class MockWorker
  include Sidekiq::Worker
  sidekiq_options priority: -> (arg) { arg * 10 }

  def perform(arg)
  end
end

class MockWorkerFixedPrio
  include Sidekiq::Worker
  sidekiq_options priority: 2

  def perform(arg)
  end
end

class MockWorkerIgnoredQueue
  include Sidekiq::Worker
  sidekiq_options queue: 'ignored_queue'

  def perform(arg)
  end
end

class MockWorkerProcQueue
  include Sidekiq::Worker
  sidekiq_options queue: -> (arg) { "queue_#{arg}" }

  def perform(arg)
  end
end

class MockWorkerNilQueue
  include Sidekiq::Worker
  sidekiq_options queue: nil

  def perform(arg)
  end
end

class MockWorkerEmptyQueue
  include Sidekiq::Worker
  sidekiq_options queue: ''

  def perform(arg)
  end
end

class MockWorkerSymbolQueue
  include Sidekiq::Worker
  sidekiq_options queue: :symbol_queue

  def perform(arg)
  end
end
