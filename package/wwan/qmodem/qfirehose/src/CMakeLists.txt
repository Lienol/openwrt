cmake_minimum_required(VERSION 2.4) 

project(QFirehose) 
add_definitions(-Wall -Wextra -Werror -O1)

set( QFirehose_SRCS
     firehose_protocol.c  qfirehose.c  sahara.c usb_linux.c stream_download_protocol.c md5.c usb2tcp.c
     )

add_executable(QFirehose ${QFirehose_SRCS})
target_link_libraries(QFirehose PUBLIC pthread) 
install (TARGETS QFirehose DESTINATION bin)
