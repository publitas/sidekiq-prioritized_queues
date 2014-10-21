module Sidekiq
  module PrioritizedQueues
    class Fetch
      def initialize(options)
        @strictly_ordered_queues = !!options[:strict]
        @queues = options[:queues].map { |q| "queue:#{q}" }
        @unique_queues = @queues.uniq
      end

      def retrieve_work
        work = nil

        Sidekiq.redis do |conn|
          queues.find do |queue|
            response = conn.multi do
              conn.zrange(queue, 0, 0)
              conn.zremrangebyrank(queue, 0, 0)
            end.flatten(1)

            next if response.length == 1
            work = [queue, response.first]
            break
          end
        end

        return UnitOfWork.new(*work) if work
        sleep 1; nil
      end

      # By leaving this as a class method, it can be pluggable and used by the Manager actor. Making it
      # an instance method will make it async to the Fetcher actor
      def self.bulk_requeue(inprogress, options)
        return if inprogress.empty?

        Sidekiq.logger.debug { "Re-queueing terminated jobs" }
        jobs_to_requeue = {}
        inprogress.each do |unit_of_work|
          jobs_to_requeue[unit_of_work.queue_name] ||= []
          jobs_to_requeue[unit_of_work.queue_name] << unit_of_work.message
        end

        Sidekiq.redis do |conn|
          conn.pipelined do
            jobs_to_requeue.each do |queue, jobs|
              jobs.each { |job| conn.zadd("queue:#{queue}", 0, job) }
            end
          end
        end
        Sidekiq.logger.info("Pushed #{inprogress.size} messages back to Redis")
      rescue => ex
        Sidekiq.logger.warn("Failed to requeue #{inprogress.size} jobs: #{ex.message}")
      end

      UnitOfWork = Struct.new(:queue, :message) do
        def acknowledge
          # nothing to do
        end

        def queue_name
          queue.gsub(/.*queue:/, '')
        end

        def requeue
          Sidekiq.redis { |conn| conn.zadd("queue:#{queue_name}", 0, message) }
        end
      end

      def queues
        @strictly_ordered_queues ? @unique_queues.dup : @queues.shuffle.uniq
      end
    end
  end
end
