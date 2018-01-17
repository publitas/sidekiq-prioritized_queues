# frozen_string_literal: true

module Sidekiq
  class Client
  private

    def atomic_push(conn, payloads)
      if payloads.first['at'.freeze]
        conn.zadd('schedule'.freeze, payloads.map do |hash|
          at = hash.delete('at'.freeze).to_s
          [at, Sidekiq.dump_json(hash)]
        end)
      else
        q = payloads.first['queue'.freeze]
        now = Time.now.to_f
        conn.sadd('queues'.freeze, q)
        payloads.each do |entry|
          to_push  = Sidekiq.dump_json(entry)
          priority = entry['priority'] || 0
          conn.zadd("queue:#{q}", priority, to_push)
        end
      end
    end
  end
end
