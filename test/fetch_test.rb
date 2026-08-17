require 'minitest_helper'

module Sidekiq
  module PrioritizedQueues
    describe Fetch do
      before do
        Sidekiq.redis { |c| c.flushdb }
        Sidekiq.default_configuration[:non_prioritized_queues] = %w[non_prio]
      end

      it 'should fetch jobs in the right priority' do
        client = Sidekiq::Client.new
        client.push_bulk('class' => 'MockWorker', 'args' => [[20], [30], [10]])

        fetcher = Sidekiq::PrioritizedQueues::Fetch.new(build_capsule)

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
          build_capsule(queues: %w[default non_prio], non_prioritized: %w[non_prio]),
        )

        works = []
        2.times { works << fetcher.retrieve_work }
        works.compact!

        assert_equal 2, works.length
      end

      it 'carries the capsule so the unit of work can reach Redis' do
        client = Sidekiq::Client.new
        client.push('class' => 'MockWorker', 'args' => [10])

        capsule = build_capsule
        work = Sidekiq::PrioritizedQueues::Fetch.new(capsule).retrieve_work

        assert_equal capsule, work.config
        assert_equal 'default', work.queue_name
      end

      describe 'UnitOfWork#requeue' do
        it 'requeues jobs from prioritized queues using zadd' do
          job = Sidekiq.dump_json({ 'class' => 'MockWorker', 'args' => [10] })
          queue_name = 'queue:default'

          unit_of_work = Sidekiq::PrioritizedQueues::Fetch::UnitOfWork.new(
            queue_name, job, build_capsule, true
          )

          unit_of_work.requeue

          Sidekiq.redis do |conn|
            zset_members = conn.zrange(queue_name, 0, -1)
            assert_includes zset_members, job
          end
        end

        it 'requeues jobs from ignored queues using rpush' do
          job = Sidekiq.dump_json({ 'class' => 'MockWorkerNonPrioritizedQueue', 'args' => [nil] })
          queue_name = 'queue:non_prio'

          unit_of_work = Sidekiq::PrioritizedQueues::Fetch::UnitOfWork.new(
            queue_name, job, build_capsule, false
          )

          unit_of_work.requeue

          Sidekiq.redis do |conn|
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

          capsule = build_capsule(non_prioritized: %w[non_prio])
          fetcher = Sidekiq::PrioritizedQueues::Fetch.new(capsule)

          units = [
            Sidekiq::PrioritizedQueues::Fetch::UnitOfWork.new(queue_name, job1, capsule, true),
            Sidekiq::PrioritizedQueues::Fetch::UnitOfWork.new(queue_name, job2, capsule, true),
          ]

          fetcher.bulk_requeue(units)

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

          capsule = build_capsule(queues: %w[default non_prio], non_prioritized: %w[non_prio])
          fetcher = Sidekiq::PrioritizedQueues::Fetch.new(capsule)

          units = [
            Sidekiq::PrioritizedQueues::Fetch::UnitOfWork.new(queue_name, job1, capsule, false),
            Sidekiq::PrioritizedQueues::Fetch::UnitOfWork.new(queue_name, job2, capsule, false),
          ]

          fetcher.bulk_requeue(units)

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

          capsule = build_capsule(queues: %w[default non_prio], non_prioritized: %w[non_prio])
          fetcher = Sidekiq::PrioritizedQueues::Fetch.new(capsule)

          units = [
            Sidekiq::PrioritizedQueues::Fetch::UnitOfWork.new(queue_priority, job_priority, capsule, true),
            Sidekiq::PrioritizedQueues::Fetch::UnitOfWork.new(queue_ignored, job_ignored, capsule, false),
          ]

          fetcher.bulk_requeue(units)

          Sidekiq.redis do |conn|
            zset_members = conn.zrange(queue_priority, 0, -1)
            assert_includes zset_members, job_priority

            list_members = conn.lrange(queue_ignored, 0, -1)
            assert_includes list_members, job_ignored
          end
        end
      end

      it 'is instantiated by the capsule when registered as the fetch class' do
        config = Sidekiq::Config.new
        config[:fetch_class] = Sidekiq::PrioritizedQueues::Fetch

        capsule = Sidekiq::Capsule.new('test', config)
        capsule.queues = %w[default]

        assert_instance_of Sidekiq::PrioritizedQueues::Fetch, capsule.fetcher
      end

      describe 'queue modes' do
        it 'infers strict ordering from zero weights' do
          capsule = build_capsule(queues: %w[default non_prio])
          assert_equal :strict, capsule.mode
        end

        it 'infers weighted ordering when a queue carries a weight' do
          capsule = build_capsule(queues: [['default', 2], ['non_prio', 1]])
          assert_equal :weighted, capsule.mode
        end
      end
    end
  end
end
