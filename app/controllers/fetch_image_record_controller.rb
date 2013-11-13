require 'red/stdlib/util/image'

class FetchImageRecordController < FetchFileFileController

  async

  protected

  def send_data_opts
    {:disposition => "attachment"}
  end

  def get_file
    find_item(RedLib::Util::ImageRecord).file
  end

end
