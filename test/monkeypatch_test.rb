require 'minitest_helper'

module Sidekiq
  module PrioritizedQueues
    describe 'Client Monkeypatch' do
      before do
        @redis = Minitest::Mock.new
        def @redis.sadd(*); true; end
        def @redis.with; yield self; end
        def @redis.multi; [yield] * 2 if block_given?; end
        Sidekiq.instance_variable_set(:@redis, @redis)
        Sidekiq::Client.instance_variable_set(:@default, nil)
      end

      after do
        Sidekiq.redis = REDIS
        Sidekiq::Client.instance_variable_set(:@default, nil)
      end

      describe 'as an instance' do
        it 'pushes jobs with the right score' do
          @redis.expect :zadd, 1, ['queue:default', 50, String]
          client = Sidekiq::Client.new
          client.push('class' => 'MockWorker', 'args' => [5])
          @redis.verify
        end
      end

      it 'pushes jobs with the right score' do
        @redis.expect :zadd, 1, ['queue:default', 20, String]
        Sidekiq::Client.push('class' => 'MockWorker', 'args' => [2])
        @redis.verify
      end
    end
  end
end
