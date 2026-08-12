require 'sidekiq/component'

module Sidekiq
  module PrioritizedQueues
    class Fetch
      include Sidekiq::Component

      # We want the fetch operation to timeout every few seconds so the thread
      # can check if the process is shutting down.
      TIMEOUT = 2

      UnitOfWork = Struct.new(:queue, :job, :config, :prioritized) {
        def acknowledge
          # nothing to do
        end

        def queue_name
          queue.delete_prefix("queue:")
        end

        def requeue
          config.redis do |conn|
            prioritized ? conn.zadd(queue, 0, job) : conn.rpush(queue, job)
          end
        end
      }

      def initialize(capsule)
        raise ArgumentError, "missing queue list" unless capsule.queues

        @config = capsule
        @strictly_ordered_queues = capsule.mode == :strict
        @queues = capsule.queues.map { |q| "queue:#{q}" }

        # Non prioritized queues use list-based Redis push/pop
        @non_prioritized_queues =
          (capsule[:non_prioritized_queues] || []).map { |q| "queue:#{q}" }

        @queues.uniq! if @strictly_ordered_queues
      end

      def retrieve_work
        work = nil

        redis do |conn|
          queues_cmd.each do |queue|
            if zset?(queue)
              response = conn.multi { |transaction|
                transaction.zrange(queue, 0, 0)
                transaction.zremrangebyrank(queue, 0, 0)
              }.flatten(1)
              next if response.length == 1

              work = [queue, response.first, config, true]
              break
            else
              job = conn.rpop(queue)
              work = [queue, job, config, false] if job
              break if work
            end
          end
        end

        return UnitOfWork.new(*work) if work

        sleep TIMEOUT
        nil
      end

      def queues_cmd
        @strictly_ordered_queues ? @queues.dup : @queues.shuffle.uniq
      end

      def bulk_requeue(inprogress)
        return if inprogress.empty?

        logger.debug { "Re-queueing terminated jobs" }
        jobs_to_requeue = {}
        inprogress.each do |unit_of_work|
          jobs_to_requeue[unit_of_work.queue] ||= []
          jobs_to_requeue[unit_of_work.queue] << unit_of_work.job
        end

        redis do |conn|
          conn.pipelined do |pipeline|
            jobs_to_requeue.each do |queue, jobs|
              jobs.each do |job|
                if zset?(queue)
                  pipeline.zadd(queue, 0, job)
                else
                  pipeline.rpush(queue, job)
                end
              end
            end
          end
        end
      rescue => ex
        logger.warn("Failed to requeue #{inprogress.size} jobs: #{ex.message}")
      end

      private

      def zset?(queue)
        @memo ||= {}
        @memo.fetch(queue) { @memo[queue] = !@non_prioritized_queues.include?(queue) }
      end
    end
  end
end
