require 'minitest_helper'

module Sidekiq
  module PrioritizedQueues
    describe Middleware do
      before do
        Sidekiq.redis = REDIS
        Sidekiq.redis { |c| c.flushdb }
      end

      it 'should add the priority field to jobs' do
        client = Sidekiq::Client.new
        client.push('class' => 'MockWorker', 'args' => [10])

        json = Sidekiq.redis { |c| c.zrange('queue:default', 0, 0) }.first
        job  = Sidekiq.load_json(json)

        assert_equal 100, job['priority']
      end

      it 'should pick the priority up from fixed values' do
        MockWorkerFixedPrio.perform_async(10)
        json = Sidekiq.redis { |c| c.zrange('queue:default', 0, 0) }.first
        job  = Sidekiq.load_json(json)

        assert_equal 2, job['priority']
      end
    end
  end
end
