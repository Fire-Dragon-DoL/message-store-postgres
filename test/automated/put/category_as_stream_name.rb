require_relative '../automated_init'

context "Put" do
  context "Category as Stream Name" do
    category = Controls::Category.example(category: 'testPutCategoryAsStreamName')
    write_event = Controls::EventData::Write.example

    Put.(write_event, category)

    read_event = Get.(category).first

    test "Writes the category name as the stream name" do
      assert(read_event.stream_name == category)
    end
  end
end
