# frozen_string_literal: true

module Sidekiq
  class Client
  private

    def atomic_push(conn, payloads)
      if payloads.first.key?('at')
        conn.zadd('schedule', payloads.flat_map do |hash|
          at = hash['at'].to_s
          hash.delete('enqueued_at')
          hash = hash.dup
          hash.delete('at')
          [at, Sidekiq.dump_json(hash)]
        end)
      else
        queue = payloads.first['queue']
        now = Time.now.to_f
        conn.sadd('queues', [queue])

        if Sidekiq::PrioritizedQueues.prioritized_queue?(queue)
          payloads.each do |entry|
            entry['enqueued_at'] = now
            to_push  = Sidekiq.dump_json(entry)
            priority = entry['priority'] || 0
            conn.zadd("queue:#{queue}", priority, to_push)
          end
        else
          to_push = payloads.map { |entry|
            entry['enqueued_at'] = now
            Sidekiq.dump_json(entry)
          }
          conn.lpush("queue:#{queue}", to_push)
        end
      end
    end
  end
end
