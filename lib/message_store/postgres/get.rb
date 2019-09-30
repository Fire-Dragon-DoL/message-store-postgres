## Needs abstract method for getting last position from batch
## Put it on the specialized get classes (as a class method)
## Pass in the batch, get the last position back

module MessageStore
  module Postgres
    ## Make into module
    class Get
      include MessageStore::Get

      dependency :session, Session

      initializer :stream_name, na(:batch_size), :condition

      def batch_size
        @batch_size ||= Defaults.batch_size
      end

      def self.build(stream_name, batch_size: nil, session: nil, condition: nil)
        cls = specialization(stream_name)

        cls.new(stream_name, batch_size, condition).tap do |instance|
          instance.configure(session: session)
        end
      end

      def self.specialization(stream_name)
        if category_stream?(stream_name)
          Category
        else
          Stream
        end
      end

      def self.configure(receiver, stream_name, attr_name: nil, batch_size: nil, condition: nil, session: nil)
        attr_name ||= :get
        instance = build(stream_name, batch_size: batch_size, condition: condition, session: session)
        receiver.public_send "#{attr_name}=", instance
      end

      def configure(session: nil)
        Session.configure self, session: session
      end

      def self.call(stream_name, position: nil, batch_size: nil, condition: nil,  session: nil)
        instance = build(stream_name, batch_size: batch_size, condition: condition, session: session)
        instance.(position)
      end

      def call(position)
        logger.trace(tag: :get) { "Getting message data (Stream Name: #{stream_name}, Position: #{position.inspect}, Batch Size: #{batch_size.inspect})" }

        position ||= Defaults.position

        result = get_result(stream_name, position)

        message_data = convert(result)

        logger.info(tag: :get) { "Finished getting message data (Count: #{message_data.length}, Stream Name: #{stream_name}, Position: #{position.inspect}, Batch Size: #{batch_size.inspect})" }
        logger.info(tags: [:data, :message_data]) { message_data.pretty_inspect }

        message_data
      end

      def get_result(stream_name, position)
        logger.trace(tag: :get) { "Getting result (Stream Name: #{stream_name}, Position: #{position.inspect}, Batch Size: #{batch_size.inspect}, Condition: #{condition || '(none)'})" }

        sql_command = self.class.sql_command(stream_name, position, batch_size, condition)

        cond = self.class.constrain_condition(condition)

        params = [
          stream_name,
          position,
          batch_size,
          cond
        ]

        result = session.execute(sql_command, params)

        logger.debug(tag: :get) { "Finished getting result (Count: #{result.ntuples}, Stream Name: #{stream_name}, Position: #{position.inspect}, Batch Size: #{batch_size.inspect}, Condition: #{condition || '(none)'})" }

        result
      end

      def self.constrain_condition(condition)
        return nil if condition.nil?

        "(#{condition})"
      end

      def self.sql_command(stream_name, position, batch_size, condition)
        parameters = '$1::varchar, $2::bigint, $3::bigint, $4::varchar'

        if category_stream?(stream_name)
          return "SELECT * FROM get_category_messages(#{parameters});"
        else
          return "SELECT * FROM get_stream_messages(#{parameters});"
        end
      end

      def convert(result)
        logger.trace(tag: :get) { "Converting result to message data (Result Count: #{result.ntuples})" }

        message_data = result.map do |record|
          record['data'] = Deserialize.data(record['data'])
          record['metadata'] = Deserialize.metadata(record['metadata'])
          record['time'] = Time.utc_coerced(record['time'])

          MessageData::Read.build record
        end

        logger.debug(tag: :get) { "Converted result to message data (Message Data Count: #{message_data.length})" }

        message_data
      end

      def last_position(batch)
        if self.class.category_stream?(stream_name)
          batch.last.global_position
        else
          batch.last.position
        end
      end

## Can be generalized to base module
      def self.category_stream?(stream_name)
        StreamName.category?(stream_name)
      end

      module Deserialize
        def self.data(serialized_data)
          return nil if serialized_data.nil?
          Transform::Read.(serialized_data, :json, MessageData::Hash)
        end

        def self.metadata(serialized_metadata)
          return nil if serialized_metadata.nil?
          Transform::Read.(serialized_metadata, :json, MessageData::Hash)
        end
      end

      module Time
        def self.utc_coerced(local_time)
          Clock::UTC.coerce(local_time)
        end
      end

      module Defaults
        def self.position
          0
        end

        def self.batch_size
          1000
        end
      end
    end
  end
end
