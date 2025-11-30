require 'minitest_helper'

module Sidekiq
  module PrioritizedQueues
    describe Fetch do
      before do
        Sidekiq.redis = REDIS
        Sidekiq.redis { |c| c.flushdb }
        Sidekiq[:ignored_queues] = %w[ignored_queue]
      end

      it 'should fetch jobs in the right priority' do
        client = Sidekiq::Client.new
        client.push_bulk('class' => 'MockWorker', 'args' => [[20], [30], [10]])

        fetcher = Sidekiq::PrioritizedQueues::Fetch.new(queues: ['default'])

        [100, 200, 300].each do |priority|
          msg = Sidekiq.load_json(fetcher.retrieve_work.job)
          assert_equal priority, msg['priority']
        end
      end

      it 'fetch jobs from ignored queues with list-based Redis operations' do
        client = Sidekiq::Client.new
        client.push('class' => MockWorkerIgnoredQueue, 'args' => [nil])
        client.push('class' => MockWorker, 'args' => [20])

        fetcher = Sidekiq::PrioritizedQueues::Fetch.new(
          queues: %w[default ignored_queue],
          ignored_queues: %w[ignored_queue],
        )

        works = []
        2.times { works << fetcher.retrieve_work }
        works.compact!

        assert_equal 2, works.length
      end
    end
  end
end
