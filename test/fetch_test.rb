require 'minitest_helper'

module Sidekiq
  module PrioritizedQueues
    describe Fetch do
      before do
        Sidekiq.redis = REDIS
        Sidekiq.redis { |c| c.flushdb }
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
    end
  end
end
