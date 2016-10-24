require_relative '../automated_init'

context "Expected Version" do
  context "Expected version does not match the stream version" do
    stream_name = Controls::StreamName.example
    write_event = Controls::EventData::Write.example

    position = Put.(stream_name, write_event)

    incorrect_stream_version = position  + 1

    test "Is an error" do
      assert proc { Put.(stream_name, write_event, expected_version: incorrect_stream_version ) } do
        raises_error? EventSource::ExpectedVersionError
      end
    end
  end
end
