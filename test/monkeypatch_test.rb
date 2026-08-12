require 'minitest_helper'

module Sidekiq
  module PrioritizedQueues
    describe 'Client Monkeypatch' do
      before do
        Sidekiq.redis { |c| c.flushdb }
        Sidekiq.default_configuration[:non_prioritized_queues] = []
      end

      def score_of(queue, member)
        Sidekiq.redis { |c| c.zscore(queue, member) }.to_f
      end

      describe 'as an instance' do
        it 'pushes jobs with the right score' do
          Sidekiq::Client.new.push('class' => 'MockWorker', 'args' => [5])

          job = Sidekiq.redis { |c| c.zrange('queue:default', 0, 0) }.first
          assert_equal 50.0, score_of('queue:default', job)
        end
      end

      it 'pushes jobs with the right score' do
        Sidekiq::Client.push('class' => 'MockWorker', 'args' => [2])

        job = Sidekiq.redis { |c| c.zrange('queue:default', 0, 0) }.first
        assert_equal 20.0, score_of('queue:default', job)
      end

      it 'registers the queue in the queues set' do
        Sidekiq::Client.new.push('class' => 'MockWorker', 'args' => [1])

        assert_includes Sidekiq.redis { |c| c.sscan('queues').to_a }, 'default'
      end

      it 'pushes jobs to regular queue if in non prioritized queue' do
        Sidekiq.default_configuration[:non_prioritized_queues] = ['non_prio']
        Sidekiq::Client.new.push('class' => MockWorkerNonPrioritizedQueue, 'args' => [nil])

        assert_equal 1, Sidekiq.redis { |c| c.llen('queue:non_prio') }
        assert_equal 'list', Sidekiq.redis { |c| c.type('queue:non_prio') }
      end

      it 'pushes scheduled jobs onto the schedule zset' do
        at = Time.now.to_f + 60
        Sidekiq::Client.new.push('class' => 'MockWorker', 'args' => [5], 'at' => at)

        assert_equal 1, Sidekiq.redis { |c| c.zcard('schedule') }
        assert_equal 0, Sidekiq.redis { |c| c.zcard('queue:default') }

        job = Sidekiq.redis { |c| c.zrange('schedule', 0, 0) }.first
        refute_includes Sidekiq.load_json(job).keys, 'at'
      end
    end
  end
end
