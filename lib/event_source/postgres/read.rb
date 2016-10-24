module EventSource
  module Postgres
    class Read
      class Error < RuntimeError; end

      include Log::Dependency

      initializer :stream, :stream_position, :batch_size, :precedence, :partition

      dependency :session, Session
      dependency :iterator, Iterator

      def self.build(stream_name, stream_position: nil, batch_size: nil, precedence: nil, partition: nil, delay_milliseconds: nil, timeout_milliseconds: nil, cycle: nil, session: nil)
        stream = Stream.new(stream_name)

        if cycle.nil?
          cycle = Cycle.build(delay_milliseconds: delay_milliseconds, timeout_milliseconds: timeout_milliseconds)
        end

        new(stream, stream_position, batch_size, precedence, partition).tap do |instance|
          Iterator.configure instance, stream, stream_position: stream_position, batch_size: batch_size, precedence: precedence, partition: partition, cycle: cycle, session: session
        end
      end

      def self.call(stream_name, stream_position: nil, batch_size: nil, precedence: nil, partition: nil, delay_milliseconds: nil, timeout_milliseconds: nil, cycle: nil, session: nil, &action)
        instance = build(stream_name, stream_position: stream_position, batch_size: batch_size, precedence: precedence, partition: partition, delay_milliseconds: delay_milliseconds, timeout_milliseconds: timeout_milliseconds, cycle: cycle, session: session)
        instance.(&action)
      end

      def self.configure(receiver, stream_name, attr_name: nil, stream_position: nil, batch_size: nil, precedence: nil, partition: partition, delay_milliseconds: nil, timeout_milliseconds: nil, cycle: nil, session: nil)
        attr_name ||= :reader
        instance = build(stream_name, stream_position: stream_position, batch_size: batch_size, precedence: precedence, partition: partition, delay_milliseconds: delay_milliseconds, timeout_milliseconds: timeout_milliseconds, cycle: cycle, session: session)
        receiver.public_send "#{attr_name}=", instance
      end

      def call(&action)
        if action.nil?
          error_message = "Reader must be actuated with a block"
          logger.error error_message
          raise Error, error_message
        end

        enumerate_event_data(&action)

        return AsyncInvocation::Incorrect
      end

      def enumerate_event_data(&action)
        logger.trace "Reading event data (Stream Name: #{stream.name}, Category: #{stream.category?}, Stream Position: #{stream_position.inspect}, Batch Size: #{batch_size.inspect}, Precedence: #{precedence.inspect}, Partition: #{partition.inspect})"

        event_data = nil

        loop do
          event_data = iterator.next

          break if event_data.nil?

          action.(event_data)
        end

        logger.debug "Finished reading event data (Stream Name: #{stream.name}, Category: #{stream.category?}, Stream Position: #{stream_position.inspect}, Batch Size: #{batch_size.inspect}, Precedence: #{precedence.inspect}, Partition: #{partition.inspect})"
      end
    end
  end
end
