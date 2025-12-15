require 'minitest_helper'

module Sidekiq
  module PrioritizedQueues
    describe Fetch do
      before do
        Sidekiq.redis = REDIS
        Sidekiq.redis { |c| c.flushdb }
        Sidekiq[:non_prioritized_queues] = %w[non_prio]
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
        client.push('class' => MockWorkerNonPrioritizedQueue, 'args' => [nil])
        client.push('class' => MockWorker, 'args' => [20])

        fetcher = Sidekiq::PrioritizedQueues::Fetch.new(
          queues: %w[default non_prio],
          non_prioritized_queues: %w[non_prio],
        )

        works = []
        2.times { works << fetcher.retrieve_work }
        works.compact!

        assert_equal 2, works.length
      end

      describe 'UnitOfWork#requeue' do
        it 'requeues jobs from prioritized queues using zadd' do
          # Create a job in a prioritized queue
          job = Sidekiq.dump_json({ 'class' => 'MockWorker', 'args' => [10] })
          queue_name = 'queue:default'

          # Create a UnitOfWork for a prioritized queue
          unit_of_work = Sidekiq::PrioritizedQueues::Fetch::UnitOfWork.new(queue_name, job, true)

          # Requeue the job
          unit_of_work.requeue

          # Verify the job was added to the zset (prioritized queue)
          Sidekiq.redis do |conn|
            # Check that the job is in the zset
            zset_members = conn.zrange(queue_name, 0, -1)
            assert_includes zset_members, job
          end
        end

        it 'requeues jobs from ignored queues using rpush' do
          # Create a job in an ignored queue
          job = Sidekiq.dump_json({ 'class' => 'MockWorkerNonPrioritizedQueue', 'args' => [nil] })
          queue_name = 'queue:non_prio'

          # Create a UnitOfWork for an ignored (list-based) queue
          unit_of_work = Sidekiq::PrioritizedQueues::Fetch::UnitOfWork.new(queue_name, job, false)

          # Requeue the job
          unit_of_work.requeue

          # Verify the job was added to the list (ignored queue)
          Sidekiq.redis do |conn|
            # Check that the job is in the list
            list_members = conn.lrange(queue_name, 0, -1)
            assert_includes list_members, job
          end
        end
      end

      describe 'Fetch#bulk_requeue' do
        it 'requeues multiple jobs from prioritized queues using zadd' do
          job1 = Sidekiq.dump_json({ 'class' => 'MockWorker', 'args' => [10] })
          job2 = Sidekiq.dump_json({ 'class' => 'MockWorker', 'args' => [20] })
          queue_name = 'queue:default'

          fetcher = Sidekiq::PrioritizedQueues::Fetch.new(
            queues: ['default'],
            non_prioritized_queues: %w[non_prio],
          )

          # Create UnitOfWork objects for prioritized queues
          units = [
            Sidekiq::PrioritizedQueues::Fetch::UnitOfWork.new(queue_name, job1, true),
            Sidekiq::PrioritizedQueues::Fetch::UnitOfWork.new(queue_name, job2, true),
          ]

          # Bulk requeue the jobs
          fetcher.bulk_requeue(units, {})

          # Verify both jobs were added to the zset
          Sidekiq.redis do |conn|
            zset_members = conn.zrange(queue_name, 0, -1)
            assert_includes zset_members, job1
            assert_includes zset_members, job2
            assert_equal 2, zset_members.length
          end
        end

        it 'requeues multiple jobs from ignored queues using rpush' do
          job1 = Sidekiq.dump_json({ 'class' => 'MockWorkerNonPrioritizedQueue', 'args' => [nil] })
          job2 = Sidekiq.dump_json({ 'class' => 'MockWorkerNonPrioritizedQueue', 'args' => [nil] })
          queue_name = 'queue:non_prio'

          fetcher = Sidekiq::PrioritizedQueues::Fetch.new(
            queues: %w[default non_prio],
            non_prioritized_queues: %w[non_prio],
          )

          # Create UnitOfWork objects for ignored (list-based) queues
          units = [
            Sidekiq::PrioritizedQueues::Fetch::UnitOfWork.new(queue_name, job1, false),
            Sidekiq::PrioritizedQueues::Fetch::UnitOfWork.new(queue_name, job2, false),
          ]

          # Bulk requeue the jobs
          fetcher.bulk_requeue(units, {})

          # Verify both jobs were added to the list
          Sidekiq.redis do |conn|
            list_members = conn.lrange(queue_name, 0, -1)
            assert_includes list_members, job1
            assert_includes list_members, job2
            assert_equal 2, list_members.length
          end
        end

        it 'requeues jobs from mixed prioritized and ignored queues' do
          job_priority = Sidekiq.dump_json({ 'class' => 'MockWorker', 'args' => [10] })
          job_ignored = Sidekiq.dump_json({ 'class' => 'MockWorkerNonPrioritizedQueue', 'args' => [nil] })

          queue_priority = 'queue:default'
          queue_ignored = 'queue:non_prio'

          fetcher = Sidekiq::PrioritizedQueues::Fetch.new(
            queues: %w[default non_prio],
            non_prioritized_queues: %w[non_prio],
          )

          # Create UnitOfWork objects for both types of queues
          units = [
            Sidekiq::PrioritizedQueues::Fetch::UnitOfWork.new(queue_priority, job_priority, true),
            Sidekiq::PrioritizedQueues::Fetch::UnitOfWork.new(queue_ignored, job_ignored, false),
          ]

          # Bulk requeue the jobs
          fetcher.bulk_requeue(units, {})

          # Verify prioritized job was added to zset
          Sidekiq.redis do |conn|
            zset_members = conn.zrange(queue_priority, 0, -1)
            assert_includes zset_members, job_priority

            # Verify ignored job was added to list
            list_members = conn.lrange(queue_ignored, 0, -1)
            assert_includes list_members, job_ignored
          end
        end
      end
    end
  end
end
