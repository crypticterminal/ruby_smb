
require 'smb2/packet/query/standard_information'

# An open file on the remote filesystem.
class Smb2::File

  # The tree that {Tree#create created} this File
  #
  # @return [Smb2::Tree]
  attr_accessor :tree

  # The server's response from when we {Tree#create created} this File
  #
  # @return [Smb2::Packet::CreateResponse]
  attr_accessor :create_response

  # The last response we got from {#read}. Useful for figuring out what went
  # wrong.
  #
  # @return [Smb2::Packet::ReadResponse]
  attr_accessor :last_read_response

  # @param tree [Smb2::Tree] the Tree where this File was opened. See {#tree}
  # @param create_response [Smb2::Packet::CreateResponse] the server's
  #   response from when we {Tree#create created} this File. See
  #   {#create_response}
  def initialize(tree:, create_response:)
    self.tree = tree
    self.create_response = create_response
  end


  # Close this File handle on the server
  #
  # @return [Smb2::Packet::CloseResponse]
  def close
    packet = Smb2::Packet::CloseRequest.new do |request|
      request.file_id = self.create_response.file_id
    end

    response = tree.send_recv(packet)

    Smb2::Packet::CloseResponse.new(response)
  end

  # @return [String]
  def inspect
    "#<Smb2::File file-id=#{create_response.file_id.unpack("H*").first} >"
  end

  # Call {#read_chunk} repeatedly until we get everything
  #
  # @note Beware of ballooning memory usage
  # @note Calling this on a pipe without a `length` is probably a really bad
  #   idea
  #
  # @param offset [Fixnum] offset from the beginning of the file (*default*: 0)
  # @param length [Fixnum,nil] number of bytes to read. If this is nil, read
  #   the whole file, i.e. {#size} bytes.
  # @return [String] full contents of the remote file
  def read(offset: 0, length: nil)
    data = ''
    max = tree.client.max_read_size
    length ||= size
    (offset...(offset+length)).step(max) do |step|
      data << read_chunk(offset: step, length: max)
    end

    data
  end

  # Send a {Smb2::Packet::ReadRequest ReadRequest} and return the data.
  #
  # @note Does not handle files being too large for a single request. See
  #   {#read} if `length` is greater than {Smb2::Client#max_read_size
  #   tree.client.max_read_size}
  #
  # @param offset [Fixnum] offset from the beginning of the file (*default*: 0)
  # @param length [Fixnum] number of bytes to read, starting from `offset`. If
  #   this is greater than the server's maximum read size, the server will
  #   respond with STATUS_INVALID_PARAMETER
  # @return [String]
  def read_chunk(offset: 0, length: self.tree.client.max_read_size)
    packet = Smb2::Packet::ReadRequest.new do |request|
      request.read_offset = offset
      request.read_length = length
      request.file_id = self.create_response.file_id
      request.minimum_count = 0
    end

    response = tree.send_recv(packet)

    response_packet = Smb2::Packet::ReadResponse.new(response)
    @last_read_response = response_packet

    response_packet.data
  end

  # The size of the file in bytes
  #
  # @return [Fixnum]
  def size
    packet = Smb2::Packet::QueryInfoRequest.new do |request|
      request.info_type = Smb2::Packet::QUERY_INFO_TYPES[:FILE]
      request.file_info_class = Smb2::Packet::FILE_INFORMATION_CLASSES[:FileStandardInformation]
      request.output_buffer_length = 40
      request.input_buffer_length = 0
      request.file_id = self.create_response.file_id
    end
    response = tree.send_recv(packet)
    query_response = Smb2::Packet::QueryInfoResponse.new(response)
    info = Smb2::Packet::Query::StandardInformation.new(query_response.output_buffer)

    info.end_of_file
  end

end
