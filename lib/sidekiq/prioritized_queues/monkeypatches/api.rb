# frozen_string_literal: true

module Sidekiq
  class Stats

    def fetch_stats_fast!
      pipe1_res = Sidekiq.redis do |conn|
        conn.pipelined do
          conn.get('stat:processed')
          conn.get('stat:failed')
          conn.zcard('schedule')
          conn.zcard('retry')
          conn.zcard('dead')
          conn.scard('processes')
          conn.zrange('queue:default', -1, -1)
        end
      end

      default_queue_latency = if (entry = pipe1_res[6].first)
        job = begin
          Sidekiq.load_json(entry)
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
        conn.sscan_each('processes').to_a
      end

      queues = Sidekiq.redis do |conn|
        conn.sscan_each('queues').to_a
      end

      pipe2_res = Sidekiq.redis do |conn|
        conn.pipelined do
          processes.each { |key| conn.hget(key, 'busy') }
          queues.each { |queue| conn.zcard("queue:#{queue}") }
        end
      end

      s = processes.size
      workers_size = pipe2_res[0...s].sum(&:to_i)
      enqueued = pipe2_res[s..-1].sum(&:to_i)

      @stats[:workers_size] = workers_size
      @stats[:enqueued] = enqueued
    end

    class Queues
      def lengths
        Sidekiq.redis do |conn|
          queues = conn.sscan_each('queues').to_a

          lengths = conn.pipelined {
            queues.each do |queue|
              conn.zcard("queue:#{queue}")
            end
          }

          array_of_arrays = queues.zip(lengths).sort_by { |_, size| -size }
          array_of_arrays.to_h
        end
      end
    end
  end

  class Queue
    def size
      Sidekiq.redis { |conn| conn.zcard(@rname) }
    end

    def latency
      entry = Sidekiq.redis do |conn|
        conn.zrange(@rname, -1, -1)
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
          conn.zrevrange @rname, range_start, range_end
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
        conn.multi do
          conn.unlink(@rname)
          conn.zrem("queues", name)
        end
      end
    end
  end

  class JobRecord
    def delete
      count = Sidekiq.redis do |conn|
        conn.zrem("queue:#{@queue}", @value)
      end
      count != 0
    end
  end
end
