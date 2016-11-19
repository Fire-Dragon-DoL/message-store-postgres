require_relative '../../automated_init'

context "Write" do
  context "Message" do
    stream_name = Controls::StreamName.example(category: 'testWriteMessagePartition')
    write_event = Controls::EventData::Write.example

    written_position = Write.(write_event, stream_name)

    read_event = Get.(stream_name, position: written_position).first

    test "Got the event that was written" do
      assert(read_event.position == written_position)
    end
  end
end
