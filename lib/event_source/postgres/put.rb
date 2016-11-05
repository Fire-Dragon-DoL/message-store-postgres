module EventSource
  module Postgres
    class Put
      include Log::Dependency

      dependency :session, Session

      def partition
        @partition ||= Defaults.partition
      end
      attr_writer :partition

      def self.build(partition: nil, session: nil)
        new.tap do |instance|
          instance.partition = partition
          instance.configure(session: session)
        end
      end

      def configure(session: nil)
        Session.configure(self, session: session)
      end

      def self.configure(receiver, partition: nil, session: nil, attr_name: nil)
        attr_name ||= :put
        instance = build(partition: partition, session: session)
        receiver.public_send "#{attr_name}=", instance
      end

      def self.call(write_event, stream_name, expected_version: nil, partition: nil, session: nil)
        instance = build(partition: partition, session: session)
        instance.(write_event, stream_name, expected_version: expected_version)
      end

      def call(write_event, stream_name, expected_version: nil)
        logger.trace { "Putting event data (Stream Name: #{stream_name}, Type: #{write_event.type}, Expected Version: #{expected_version.inspect})" }
        logger.trace(tags: [:data, :event_data]) { write_event.pretty_inspect }

        type, data, metadata = destructure_event(write_event)
        expected_version = ExpectedVersion.canonize(expected_version)

        insert_event(stream_name, type, data, metadata, expected_version).tap do |position|
          logger.info { "Put event data (Position: #{position}, Stream Name: #{stream_name}, Type: #{write_event.type}, Expected Version: #{expected_version.inspect})" }
          logger.info(tags: [:data, :event_data]) { write_event.pretty_inspect }
        end
      end

      def destructure_event(write_event)
        type = write_event.type
        data = write_event.data
        metadata = write_event.metadata

        logger.debug(tags: [:data, :event_data]) { "Data: #{data.pretty_inspect}" }
        logger.debug(tags: [:data, :event_data]) { "Metadata: #{metadata.pretty_inspect}" }

        return type, data, metadata
      end

      def insert_event(stream_name, type, data, metadata, expected_version)
        serialized_data = serialized_data(data)
        serialized_metadata = serialized_metadata(metadata)
        records = execute_query(stream_name, type, serialized_data, serialized_metadata, expected_version)
        position(records)
      end

      def execute_query(stream_name, type, serialized_data, serialized_metadata, expected_version)
        logger.trace { "Executing insert (Stream Name: #{stream_name}, Type: #{type}, Expected Version: #{expected_version.inspect})" }

        params = [
          stream_name,
          type,
          serialized_data,
          partition,
          serialized_metadata,
          expected_version
        ]

        begin
          records = session.execute(self.class.statement, params)
        rescue PG::RaiseException => e
          raise_error e
        end

        logger.debug { "Executed insert (Stream Name: #{stream_name}, Type: #{type}, Expected Version: #{expected_version.inspect})" }

        records
      end

      def self.statement
        @statement ||= "SELECT write_event($1::varchar, $2::varchar, $3::jsonb, $4::varchar, $5::jsonb, $6::int);"
      end

      def serialized_data(data)
        serializable_data = EventData::Hash[data]
        serialized_data = Transform::Write.(serializable_data, :json)
        logger.debug(tags: [:data, :serialize]) { "Serialized Data: #{serialized_data.inspect}" }
        serialized_data
      end

      def serialized_metadata(metadata)
        serializable_metadata = EventData::Hash[metadata]
        serialized_metadata = nil
        unless metadata.nil?
          serialized_metadata = Transform::Write.(serializable_metadata, :json)
        end
        logger.debug(tags: [:data, :serialize]) { "Serialized Metadata: #{serialized_metadata.inspect}" }
        serialized_metadata
      end

      def position(records)
        position = nil
        unless records[0].nil?
          position = records[0].values[0]
        end
        position
      end

      def raise_error(pg_error)
        error_message = pg_error.message
        if error_message.include? 'Wrong expected version'
          error_message.gsub!('ERROR:', '').strip!
          raise ExpectedVersion::Error, error_message
        end
        raise pg_error
      end

      module Defaults
        def self.partition
          Partition::Defaults.name
        end
      end
    end
  end
end
