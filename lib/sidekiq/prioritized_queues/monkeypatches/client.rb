# frozen_string_literal: true

module Sidekiq
  class Client
  private

    def atomic_push(conn, payloads)
      if payloads.first.key?('at')
        conn.zadd('schedule', payloads.map do |hash|
          at = hash.delete('at').to_s
          [at, Sidekiq.dump_json(hash)]
        end)
      else
        queue = payloads.first['queue']
        now = Time.now.to_f
        conn.sadd('queues', queue)
        payloads.each do |entry|
          entry['enqueued_at'] = now
          to_push  = Sidekiq.dump_json(entry)

          if entry['priority'].is_a?(FalseClass)
            conn.lpush("queue:#{queue}", to_push)
          else
            priority = entry['priority'] || 0
            conn.zadd("queue:#{queue}", priority, to_push)
          end
        end
      end
    end
  end
end
