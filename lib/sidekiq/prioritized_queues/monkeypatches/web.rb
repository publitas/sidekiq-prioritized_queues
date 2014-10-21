require 'sinatra'

module Sidekiq
  class Web < Sinatra::Base
    get "/queues/:name" do
      halt 404 unless params[:name]
      @count = (params[:count] || 25).to_i
      @name = params[:name]
      @queue = Sidekiq::Queue.new(@name)
      (@current_page, @total_size, @messages) = page("queue:#{@name}", params[:page], @count)
      @messages = @messages.map {|msg, priority| Sidekiq::Job.new(msg, @name) }
      erb :queue
    end
  end
end
