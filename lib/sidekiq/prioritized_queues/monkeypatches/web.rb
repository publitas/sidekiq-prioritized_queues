# frozen_string_literal: true
require 'sidekiq/web'

module Sidekiq
  class WebApplication
    custom_block = Proc.new do
      @name = route_params[:name]

      halt(404) if !@name || @name !~ QUEUE_NAME

      @count = (params["count"] || 25).to_i
      @queue = Sidekiq::Queue.new(@name)
      (@current_page, @total_size, @jobs) = page("queue:#{@name}", params["page"], @count, reverse: params["direction"] == "asc")
      @jobs = @jobs.map { |msg, _priority| Sidekiq::JobRecord.new(msg, @name) }

      erb(:queue)
    end

    @routes[WebRouter::GET].unshift WebRoute.new(WebRouter::GET, '/queues/:name', custom_block)
  end
end
