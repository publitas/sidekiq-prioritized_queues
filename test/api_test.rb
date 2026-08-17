require 'minitest_helper'

module Sidekiq
  module PrioritizedQueues
    describe 'API Monkeypatch' do
      before do
        Sidekiq.redis { |c| c.flushdb }
        Sidekiq.default_configuration[:non_prioritized_queues] = %w[non_prio]
      end

      def push_prioritized(count)
        count.times { |i| Sidekiq::Client.new.push('class' => 'MockWorker', 'args' => [i + 1]) }
      end

      def push_non_prioritized(count)
        count.times { Sidekiq::Client.new.push('class' => MockWorkerNonPrioritizedQueue, 'args' => [nil]) }
      end

      describe Sidekiq::Queue do
        it 'sizes prioritized queues with zcard' do
          push_prioritized(3)
          assert_equal 3, Sidekiq::Queue.new('default').size
        end

        it 'sizes non prioritized queues with llen' do
          push_non_prioritized(2)
          assert_equal 2, Sidekiq::Queue.new('non_prio').size
        end

        it 'reports latency against the oldest job' do
          push_prioritized(1)
          assert_operator Sidekiq::Queue.new('default').latency, :>=, 0
        end

        it 'reports zero latency for an empty queue' do
          assert_equal 0, Sidekiq::Queue.new('default').latency
        end

        it 'iterates every job in a prioritized queue' do
          push_prioritized(3)
          assert_equal 3, Sidekiq::Queue.new('default').to_a.size
        end

        it 'clears a prioritized queue and deregisters it' do
          push_prioritized(2)
          Sidekiq::Queue.new('default').clear

          assert_equal 0, Sidekiq::Queue.new('default').size
          refute_includes Sidekiq.redis { |c| c.sscan('queues').to_a }, 'default'
        end

        it 'clears a non prioritized queue and deregisters it' do
          push_non_prioritized(2)
          Sidekiq::Queue.new('non_prio').clear

          assert_equal 0, Sidekiq::Queue.new('non_prio').size
          refute_includes Sidekiq.redis { |c| c.sscan('queues').to_a }, 'non_prio'
        end
      end

      describe Sidekiq::JobRecord do
        it 'deletes a job from a prioritized queue with zrem' do
          push_prioritized(2)
          job = Sidekiq::Queue.new('default').first

          assert job.delete
          assert_equal 1, Sidekiq::Queue.new('default').size
        end

        it 'deletes a job from a non prioritized queue with lrem' do
          push_non_prioritized(2)
          job = Sidekiq::Queue.new('non_prio').first

          assert job.delete
          assert_equal 1, Sidekiq::Queue.new('non_prio').size
        end
      end

      describe Sidekiq::Stats do
        it 'reports lengths for both queue types' do
          push_prioritized(2)
          push_non_prioritized(1)

          queues = Sidekiq::Stats.new.queues
          assert_equal 2, queues['default']
          assert_equal 1, queues['non_prio']
        end

        it 'builds fast stats without raising on a zset default queue' do
          push_prioritized(1)

          stats = Sidekiq::Stats.new
          assert_equal 0, stats.processed
          assert_operator stats.default_queue_latency, :>=, 0
        end

        it 'counts enqueued jobs across both queue types' do
          push_prioritized(2)
          push_non_prioritized(3)

          assert_equal 5, Sidekiq::Stats.new.enqueued
        end
      end
    end
  end
end
