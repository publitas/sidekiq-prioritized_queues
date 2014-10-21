module Sidekiq
  class Client

  private

    def atomic_push(conn, payloads)
      if payloads.first['at']
        conn.zadd('schedule', payloads.map do |hash|
          at = hash.delete('at').to_s
          [at, Sidekiq.dump_json(hash)]
        end)
      else
        q = payloads.first['queue']

        conn.sadd('queues', q)

        payloads.each do |entry|
          to_push  = Sidekiq.dump_json(entry)
          priority = entry['priority'] || 0
          conn.zadd("queue:#{q}", priority, to_push)
        end
      end
    end
  end
end
