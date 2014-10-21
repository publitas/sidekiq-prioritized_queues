require 'sidekiq/api'

module Sidekiq
  class Stats
    def queues
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
