require_relative '../../automated_init'

Controls = EventSource::Postgres::Controls

context "Put" do
  context "No Stream" do
    context "For a stream that doesn't exist" do
      stream_name = Controls::StreamName.example
      write_event = Controls::EventData::Write.example

      stream_position = Put.(stream_name, write_event)

      test "Ensures that the event written is the first event in the stream" do
        assert(stream_position == 0)
      end
    end
  end
end
