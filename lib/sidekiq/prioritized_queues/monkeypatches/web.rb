# frozen_string_literal: true
require 'sidekiq/web'

module Sidekiq
  class WebApplication
    get '/queues/:name' do
      @name = route_params[:name]

      halt(404) unless @name

      @count = (params["count"] || 25).to_i
      @queue = Sidekiq::Queue.new(@name)
      (@current_page, @total_size, @messages) = page("queue:#{@name}", params["page"], @count, reverse: params["direction"] == "asc")
      @messages = @messages.map { |msg, _priority| Sidekiq::Job.new(msg, @name) }

      erb(:queue)
    end
  end
end
