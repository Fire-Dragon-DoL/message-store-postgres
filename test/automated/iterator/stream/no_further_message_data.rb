require_relative '../../automated_init'

context "Iterator" do
  context "Stream" do
    context "No Further Message Data" do
      stream_name, _ = Controls::Put.(instances: 2)

## build parm not needed. get will have it
##      iterator = Read::Iterator.build(stream_name)
      iterator = Read::Iterator.build
      Get.configure(iterator, batch_size: 1)

      2.times { iterator.next }

      last = iterator.next

      test "Results in nil" do
        assert(last.nil?)
      end
    end
  end
end
