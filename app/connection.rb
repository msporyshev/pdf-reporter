require "socket"

include Socket::Constants

socket = Socket.new( AF_INET, SOCK_STREAM, 0 )
sockaddr = Socket.pack_sockaddr_in( 30000, 'localhost' )
# data = IO.read("untitled")
data =<<EOF
asdasd

EOF
socket.connect( sockaddr )
  socket.write(data)
results = socket.read
puts results
# while not socket.eof?
# end