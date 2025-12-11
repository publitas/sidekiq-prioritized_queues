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

      it 'should resolve queue names when the queue option is a Proc' do
        MockWorkerProcQueue.perform_async('high')
        json = Sidekiq.redis { |c| c.zrange('queue:queue_high', 0, 0) }.first
        job  = Sidekiq.load_json(json)

        assert_equal 'queue_high', job['queue']
      end

      it 'should default queue to "default" when queue option is nil' do
        middleware = Middleware.new
        msg = { 'args' => [10], 'queue' => 'temporary' }

        middleware.call(MockWorkerNilQueue, msg, 'temporary', nil) do
          # no-op
        end

        assert_equal 'default', msg['queue']
      end

      it 'should default queue to "default" when queue option is an empty string' do
        middleware = Middleware.new
        msg = { 'args' => [10], 'queue' => 'temporary' }

        middleware.call(MockWorkerEmptyQueue, msg, 'temporary', nil) do
          # no-op
        end

        assert_equal 'default', msg['queue']
      end

      it 'should convert queue names to strings' do
        MockWorkerSymbolQueue.perform_async(10)
        json = Sidekiq.redis { |c| c.zrange('queue:symbol_queue', 0, 0) }.first
        job  = Sidekiq.load_json(json)

        assert_equal 'symbol_queue', job['queue']
        assert_kind_of String, job['queue']
      end
    end
  end
end
