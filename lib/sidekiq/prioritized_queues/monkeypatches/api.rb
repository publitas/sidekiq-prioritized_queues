# frozen_string_literal: true

# Sidekiq 7 loads sidekiq/api lazily; without this the patches below are
# defined first and then silently overwritten by the stock definitions.
require 'sidekiq/api'

module Sidekiq
  class Stats
    def queues
      Sidekiq.redis do |conn|
        queues = conn.sscan('queues').to_a

        lengths = conn.pipelined { |pipeline|
          queues.each do |queue|
            if Sidekiq::PrioritizedQueues.prioritized_queue?(queue)
              pipeline.zcard("queue:#{queue}")
            else
              pipeline.llen("queue:#{queue}")
            end
          end
        }

        array_of_arrays = queues.zip(lengths).sort_by { |_, size| -size }
        array_of_arrays.to_h
      end
    end

    def fetch_stats_fast!
      default_prioritized = Sidekiq::PrioritizedQueues.prioritized_queue?('default')

      pipe1_res = Sidekiq.redis do |conn|
        conn.pipelined do |pipeline|
          pipeline.get('stat:processed')
          pipeline.get('stat:failed')
          pipeline.zcard('schedule')
          pipeline.zcard('retry')
          pipeline.zcard('dead')
          pipeline.scard('processes')
          if default_prioritized
            pipeline.zrange('queue:default', 0, 0)
          else
            pipeline.lindex('queue:default', -1)
          end
        end
      end

      oldest = pipe1_res[6]
      oldest = oldest.first if oldest.is_a?(Array)

      default_queue_latency = if oldest
        job = begin
          Sidekiq.load_json(oldest)
        rescue
          {}
        end
        now = Time.now.to_f
        thence = job['enqueued_at'] || now
        now - thence
      else
        0
      end

      @stats = {
        processed: pipe1_res[0].to_i,
        failed: pipe1_res[1].to_i,
        scheduled_size: pipe1_res[2],
        retry_size: pipe1_res[3],
        dead_size: pipe1_res[4],
        processes_size: pipe1_res[5],

        default_queue_latency: default_queue_latency,
      }
    end

    def fetch_stats_slow!
      processes = Sidekiq.redis do |conn|
        conn.sscan('processes').to_a
      end

      queues = Sidekiq.redis do |conn|
        conn.sscan('queues').to_a
      end

      pipe2_res = Sidekiq.redis do |conn|
        conn.pipelined do |pipeline|
          processes.each { |key| pipeline.hget(key, 'busy') }
          queues.each do |queue|
            if Sidekiq::PrioritizedQueues.prioritized_queue?(queue)
              pipeline.zcard("queue:#{queue}")
            else
              pipeline.llen("queue:#{queue}")
            end
          end
        end
      end

      s = processes.size
      workers_size = pipe2_res[0...s].sum(&:to_i)
      enqueued = pipe2_res[s..].sum(&:to_i)

      @stats[:workers_size] = workers_size
      @stats[:enqueued] = enqueued
      @stats
    end
  end

  class Queue
    def size
      Sidekiq.redis do |conn|
        prioritized? ? conn.zcard(@rname) : conn.llen(@rname)
      end
    end

    def latency
      entry = Sidekiq.redis do |conn|
        if prioritized?
          conn.zrange(@rname, 0, 0)
        else
          conn.lrange(@rname, -1, -1)
        end
      end.first
      return 0 unless entry

      job = Sidekiq.load_json(entry)
      now = Time.now.to_f
      thence = job['enqueued_at'] || now
      now - thence
    end

    def each
      initial_size = size
      deleted_size = 0
      page = 0
      page_size = 50

      loop do
        range_start = page * page_size - deleted_size
        range_end = range_start + page_size - 1
        entries = Sidekiq.redis do |conn|
          if prioritized?
            conn.zrange(@rname, range_start, range_end, 'REV')
          else
            conn.lrange(@rname, range_start, range_end)
          end
        end
        break if entries.empty?

        page += 1
        entries.each do |entry|
          yield JobRecord.new(entry, @name)
        end
        deleted_size = initial_size - size
      end
    end

    def clear
      Sidekiq.redis do |conn|
        conn.multi do |transaction|
          transaction.unlink(@rname)
          transaction.srem('queues', [name])
        end
      end
    end

    private

    def prioritized?
      return @prioritized unless @prioritized.nil?

      @prioritized = Sidekiq::PrioritizedQueues.prioritized_queue?(name)
    end
  end

  class JobRecord
    def delete
      count = Sidekiq.redis do |conn|
        if prioritized?
          conn.zrem("queue:#{@queue}", @value)
        else
          conn.lrem("queue:#{@queue}", 1, @value)
        end
      end
      count != 0
    end

    private

    def prioritized?
      return @prioritized unless @prioritized.nil?

      @prioritized = Sidekiq::PrioritizedQueues.prioritized_queue?(@queue)
    end
  end
end
