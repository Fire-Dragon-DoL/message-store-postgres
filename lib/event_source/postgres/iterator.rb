module EventSource
  module Postgres
    class Iterator
      class Error < RuntimeError; end

      include Log::Dependency

      attr_accessor :batch
      attr_writer :batch_position
      attr_writer :stream_offset

      def batch_position
        @batch_position ||= 0
      end

      def stream_offset
        @stream_offset ||= (stream_position || 0)
      end

      dependency :get, Get
      dependency :cycle, Cycle

      ## TODO remove a() with default
      initializer :stream, a(:stream_position, 0), :batch_size, :precedence, :partition

      def self.build(stream, stream_position: nil, batch_size: nil, precedence: nil, partition: nil, cycle: nil, session: nil)
        new(stream, stream_position, batch_size, precedence, partition).tap do |instance|
          Get.configure instance, stream, batch_size: batch_size, precedence: precedence, partition: partition, session: session
          Cycle.configure instance, cycle: cycle
        end
      end

      def self.configure(receiver, stream, attr_name: nil, stream_position: nil, batch_size: nil, precedence: nil, partition: nil, cycle: nil, session: nil)
        attr_name ||= :iterator
        instance = build(stream, stream_position: stream_position, batch_size: batch_size, precedence: precedence, partition: partition, cycle: cycle, session: session)
        receiver.public_send "#{attr_name}=", instance
      end

      def next
        logger.trace "Getting next event data (Batch Length: #{batch.nil? ? '<none>' : batch.length}, Batch Position: #{batch_position}, Stream Offset: #{stream_offset})"

        resupply(batch)

        event_data = batch[batch_position]

        logger.debug "Finished getting next event data (Batch Length: #{batch.nil? ? '<none>' : batch.length}, Batch Position: #{batch_position}, Stream Offset: #{stream_offset})"
        logger.debug "Event Data: #{event_data.inspect}",  tags: [:data, :event_data]

        advance_positions

        event_data
      end

      def resupply(batch)
        logger.trace "Resupplying batch"

        if batch.nil?
          batch_log_text = "Batch: #{batch.inspect}"
        else
          batch_log_text = "Batch Length: #{batch.length}"
        end

        if batch.nil? || batch_position == batch.length
          logger.debug "Current batch is depleted (#{batch_log_text}, Batch Position: #{batch_position})"

          batch = get_batch
          reset(batch)
        else
          logger.debug "Current batch not depleted (#{batch_log_text}, Batch Position: #{batch_position})"
        end

        logger.debug "Finished resupplying batch"
      end

      def reset(batch)
        logger.trace "Resetting batch"

        self.batch = batch
        self.batch_position = 0

        logger.debug "Reset batch"
        logger.debug "Batch: #{batch.inspect}", tags: [:data, :batch]
        logger.debug "Batch Position: #{batch_position.inspect}", tags: [:data, :batch]
      end

      def get_batch
        logger.trace "Getting batch"

        batch = nil
        cycle.() do
          batch = get.(stream_position: stream_offset)
        end

        logger.debug "Finished getting batch (Count: #{batch.length})"

        batch
      end

      def advance_positions
        logger.trace "Advancing positions (Batch Position: #{batch_position}, Stream Offset: #{stream_offset})"
        self.batch_position += 1
        self.stream_offset += 1
        logger.debug "Advanced positions (Batch Position: #{batch_position}, Stream Offset: #{stream_offset})"
      end
    end
  end
end
