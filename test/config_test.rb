require 'minitest_helper'

module Sidekiq
  module PrioritizedQueues
    describe Config do
      it 'should load non prioritized queues from config file' do
        config = { require: File.join(__dir__, 'fixtures') }
        gem_config = Sidekiq::PrioritizedQueues::Config.new(config)
        assert_equal %w[non_prio], gem_config.non_prioritized_queues
      end

      it 'should return empty array if no ignored queues are set' do
        config = { require: File.join(__dir__, 'nonexistent') }
        gem_config = Sidekiq::PrioritizedQueues::Config.new(config)
        assert_equal [], gem_config.non_prioritized_queues
      end
    end
  end
end
