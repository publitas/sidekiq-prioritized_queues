module Sidekiq
  module PrioritizedQueues
    class Fetch
      # We want the fetch operation to timeout every few seconds so the thread
      # can check if the process is shutting down.
      TIMEOUT = 2

      UnitOfWork = Struct.new(:queue, :job, :prioritized) {
        def acknowledge
          # nothing to do
        end

        def queue_name
          queue.delete_prefix("queue:")
        end

        def requeue
          Sidekiq.redis do |conn|
            prioritized ? conn.zadd(queue, 0, job) : conn.rpush(queue, job)
          end
        end
      }

      def initialize(options)
        raise ArgumentError, "missing queue list" unless options[:queues]
        @strictly_ordered_queues = !!options[:strict]
        @queues = options[:queues].map { |q| "queue:#{q}" }

        # Non prioritized queues use list-based Redis push/pop
        @non_prioritized_queues =
          (options[:non_prioritized_queues] || Sidekiq[:non_prioritized_queues] || [])
            .map { |q| "queue:#{q}" }

        if @strictly_ordered_queues
          @queues.uniq!
          @queues << TIMEOUT
        end
      end

      def retrieve_work
        work = nil

        Sidekiq.redis do |conn|
          queues.each do |queue|
            if zset?(queue)
              response = conn.multi do |pipeline|
                pipeline.zrange(queue, 0, 0)
                pipeline.zremrangebyrank(queue, 0, 0)
              end.flatten(1)
              next if response.length == 1

              work = [queue, response.first, true]
              break
            else
              job = conn.rpop(queue)
              work = [queue, job, false] if job
              break if work
            end
          end
        end

        return UnitOfWork.new(*work) if work
        sleep TIMEOUT; nil
      end

      def queues
        @strictly_ordered_queues ? @queues.dup : @queues.shuffle.uniq
      end

      def bulk_requeue(inprogress, options)
        return if inprogress.empty?

        Sidekiq.logger.debug { "Re-queueing terminated jobs" }
        jobs_to_requeue = {}
        inprogress.each do |unit_of_work|
          jobs_to_requeue[unit_of_work.queue] ||= []
          jobs_to_requeue[unit_of_work.queue] << unit_of_work.job
        end

        Sidekiq.redis do |conn|
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
        Sidekiq.logger.warn("Failed to requeue #{inprogress.size} jobs: #{ex.message}")
      end

      private

      def zset?(queue)
        @memo ||= {}
        @memo.fetch(queue) { @memo[queue] = !@non_prioritized_queues.include?(queue) }
      end
    end
  end
end
