require 'sidekiq/api'

module Sidekiq
  class Stats

    def fetch_stats!
      pipe1_res = Sidekiq.redis do |conn|
        conn.pipelined do
          conn.get('stat:processed'.freeze)
          conn.get('stat:failed'.freeze)
          conn.zcard('schedule'.freeze)
          conn.zcard('retry'.freeze)
          conn.zcard('dead'.freeze)
          conn.scard('processes'.freeze)
          conn.zrange('queue:default'.freeze, -1, -1)
          conn.smembers('processes'.freeze)
          conn.smembers('queues'.freeze)
        end
      end
      pipe2_res = Sidekiq.redis do |conn|
        conn.pipelined do
          pipe1_res[7].each {|key| conn.hget(key, 'busy'.freeze) }
          pipe1_res[8].each {|queue| conn.zcard("queue:#{queue}") }
        end
      end
      s = pipe1_res[7].size
      workers_size = pipe2_res[0...s].map(&:to_i).inject(0, &:+)
      enqueued     = pipe2_res[s..-1].map(&:to_i).inject(0, &:+)
      default_queue_latency = if (entry = pipe1_res[6].first)
                                Time.now.to_f - Sidekiq.load_json(entry)['enqueued_at'.freeze]
                              else
                                0
                              end
      @stats = {
        processed:             pipe1_res[0].to_i,
        failed:                pipe1_res[1].to_i,
        scheduled_size:        pipe1_res[2],
        retry_size:            pipe1_res[3],
        dead_size:             pipe1_res[4],
        processes_size:        pipe1_res[5],
        default_queue_latency: default_queue_latency,
        workers_size:          workers_size,
        enqueued:              enqueued
      }
    end

    class Queues

      def lengths
        Sidekiq.redis do |conn|
          queues = conn.smembers('queues')
          lengths = conn.pipelined do
            queues.each do |queue|
              conn.zcard("queue:#{queue}")
            end
          end
          i = 0
          array_of_arrays = queues.inject({}) do |memo, queue|
            memo[queue] = lengths[i]
            i += 1
            memo
          end.sort_by { |_, size| size }
          Hash[array_of_arrays.reverse]
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
      Time.now.to_f - Sidekiq.load_json(entry)['enqueued_at']
    end

    def each(&block)
      initial_size = size
      deleted_size = 0
      page = 0
      page_size = 50

      loop do
        range_start = page * page_size - deleted_size
        range_end   = page * page_size - deleted_size + (page_size - 1)
        entries = Sidekiq.redis do |conn|
          conn.zrevrange @rname, range_start, range_end
        end
        break if entries.empty?
        page += 1
        entries.each do |entry|
          block.call Job.new(entry, @name)
        end
        deleted_size = initial_size - size
      end
    end
  end

  class Job
    def delete
      count = Sidekiq.redis do |conn|
        conn.zrem("queue:#{@queue}", @value)
      end
      count != 0
    end
  end
end
