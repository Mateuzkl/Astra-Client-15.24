add_definitions(-DCLIENT)

# Protobuf (Phase 0 deliverable #6): generate appearances.pb.{h,cc} and
# staticdata.pb.{h,cc} from src/client/proto/*.proto. The pair is written to
# ${CMAKE_BINARY_DIR}/generated/proto/ (which the root CMakeLists.txt adds to
# include_directories), so consumers just #include "appearances.pb.h".
#
# find_package(Protobuf) is called by the root CMakeLists.txt before this
# fragment is include()'d, which is what makes protobuf_generate_cpp()
# available here. The PROTOC_OUT_DIR keyword is forwarded to the underlying
# protobuf_generate() helper; pre-creating the directory keeps protoc from
# failing on the very first configure when it does not exist yet.
file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/generated/proto)
protobuf_generate_cpp(PROTO_SRCS PROTO_HDRS
    PROTOC_OUT_DIR ${CMAKE_BINARY_DIR}/generated/proto
    ${CMAKE_CURRENT_LIST_DIR}/proto/appearances.proto
    ${CMAKE_CURRENT_LIST_DIR}/proto/staticdata.proto)

set(client_SOURCES ${client_SOURCES}
    ${PROTO_SRCS}

    # client
    ${CMAKE_CURRENT_LIST_DIR}/const.h
    ${CMAKE_CURRENT_LIST_DIR}/global.h
    ${CMAKE_CURRENT_LIST_DIR}/luafunctions_client.cpp
    ${CMAKE_CURRENT_LIST_DIR}/client.cpp
    ${CMAKE_CURRENT_LIST_DIR}/client.h

    # core
    ${CMAKE_CURRENT_LIST_DIR}/animatedtext.cpp
    ${CMAKE_CURRENT_LIST_DIR}/animatedtext.h
    ${CMAKE_CURRENT_LIST_DIR}/animator.h
    ${CMAKE_CURRENT_LIST_DIR}/animator.cpp
    ${CMAKE_CURRENT_LIST_DIR}/container.cpp
    ${CMAKE_CURRENT_LIST_DIR}/container.h
    ${CMAKE_CURRENT_LIST_DIR}/creature.cpp
    ${CMAKE_CURRENT_LIST_DIR}/creature.h
    ${CMAKE_CURRENT_LIST_DIR}/declarations.h
    ${CMAKE_CURRENT_LIST_DIR}/effect.cpp
    ${CMAKE_CURRENT_LIST_DIR}/effect.h
    ${CMAKE_CURRENT_LIST_DIR}/game.cpp
    ${CMAKE_CURRENT_LIST_DIR}/game.h
    ${CMAKE_CURRENT_LIST_DIR}/item.cpp
    ${CMAKE_CURRENT_LIST_DIR}/item.h
    ${CMAKE_CURRENT_LIST_DIR}/localplayer.cpp
    ${CMAKE_CURRENT_LIST_DIR}/localplayer.h
    ${CMAKE_CURRENT_LIST_DIR}/map.cpp
    ${CMAKE_CURRENT_LIST_DIR}/map.h
    ${CMAKE_CURRENT_LIST_DIR}/mapio.cpp
    ${CMAKE_CURRENT_LIST_DIR}/mapview.cpp
    ${CMAKE_CURRENT_LIST_DIR}/mapview.h
    ${CMAKE_CURRENT_LIST_DIR}/minimap.cpp
    ${CMAKE_CURRENT_LIST_DIR}/minimap.h
    ${CMAKE_CURRENT_LIST_DIR}/lightview.cpp
    ${CMAKE_CURRENT_LIST_DIR}/lightview.h
    ${CMAKE_CURRENT_LIST_DIR}/missile.cpp
    ${CMAKE_CURRENT_LIST_DIR}/missile.h
    ${CMAKE_CURRENT_LIST_DIR}/outfit.cpp
    ${CMAKE_CURRENT_LIST_DIR}/outfit.h
    ${CMAKE_CURRENT_LIST_DIR}/player.cpp
    ${CMAKE_CURRENT_LIST_DIR}/player.h
    ${CMAKE_CURRENT_LIST_DIR}/spritemanager.cpp
    ${CMAKE_CURRENT_LIST_DIR}/spritemanager.h
    ${CMAKE_CURRENT_LIST_DIR}/staticdata.h
    ${CMAKE_CURRENT_LIST_DIR}/statictext.cpp
    ${CMAKE_CURRENT_LIST_DIR}/statictext.h
    ${CMAKE_CURRENT_LIST_DIR}/thing.cpp
    ${CMAKE_CURRENT_LIST_DIR}/thing.h
    ${CMAKE_CURRENT_LIST_DIR}/thingtypemanager.cpp
    ${CMAKE_CURRENT_LIST_DIR}/thingtypemanager.h
    ${CMAKE_CURRENT_LIST_DIR}/thingtype.cpp
    ${CMAKE_CURRENT_LIST_DIR}/thingtype.h
    ${CMAKE_CURRENT_LIST_DIR}/appearancesloader.cpp
    ${CMAKE_CURRENT_LIST_DIR}/appearancesloader.h
    ${CMAKE_CURRENT_LIST_DIR}/spritesheetloader.cpp
    ${CMAKE_CURRENT_LIST_DIR}/spritesheetloader.h
    ${CMAKE_CURRENT_LIST_DIR}/itemtype.cpp
    ${CMAKE_CURRENT_LIST_DIR}/itemtype.h
    ${CMAKE_CURRENT_LIST_DIR}/tile.cpp
    ${CMAKE_CURRENT_LIST_DIR}/tile.h
    ${CMAKE_CURRENT_LIST_DIR}/healthbars.cpp
    ${CMAKE_CURRENT_LIST_DIR}/healthbars.h
    ${CMAKE_CURRENT_LIST_DIR}/houses.cpp
    ${CMAKE_CURRENT_LIST_DIR}/houses.h
    ${CMAKE_CURRENT_LIST_DIR}/towns.cpp
    ${CMAKE_CURRENT_LIST_DIR}/towns.h
    ${CMAKE_CURRENT_LIST_DIR}/creatures.cpp
    ${CMAKE_CURRENT_LIST_DIR}/creatures.h

    # lua
    ${CMAKE_CURRENT_LIST_DIR}/luavaluecasts_client.cpp
    ${CMAKE_CURRENT_LIST_DIR}/luavaluecasts_client.h

    # net
    ${CMAKE_CURRENT_LIST_DIR}/protocolcodes.cpp
    ${CMAKE_CURRENT_LIST_DIR}/protocolcodes.h
    ${CMAKE_CURRENT_LIST_DIR}/protocolgame.cpp
    ${CMAKE_CURRENT_LIST_DIR}/protocolgame.h
    ${CMAKE_CURRENT_LIST_DIR}/protocolgameparse.cpp
    ${CMAKE_CURRENT_LIST_DIR}/protocolgamesend.cpp

    # ui
    ${CMAKE_CURRENT_LIST_DIR}/uicreature.cpp
    ${CMAKE_CURRENT_LIST_DIR}/uicreature.h
    ${CMAKE_CURRENT_LIST_DIR}/uiitem.cpp
    ${CMAKE_CURRENT_LIST_DIR}/uiitem.h
    ${CMAKE_CURRENT_LIST_DIR}/uigraph.cpp
    ${CMAKE_CURRENT_LIST_DIR}/uigraph.h
    ${CMAKE_CURRENT_LIST_DIR}/uigrid.cpp
    ${CMAKE_CURRENT_LIST_DIR}/uigrid.h
    ${CMAKE_CURRENT_LIST_DIR}/uimap.cpp
    ${CMAKE_CURRENT_LIST_DIR}/uimap.h
    ${CMAKE_CURRENT_LIST_DIR}/uiminimap.cpp
    ${CMAKE_CURRENT_LIST_DIR}/uiminimap.h
    ${CMAKE_CURRENT_LIST_DIR}/uiprogressrect.cpp
    ${CMAKE_CURRENT_LIST_DIR}/uiprogressrect.h
    ${CMAKE_CURRENT_LIST_DIR}/uimapanchorlayout.cpp
    ${CMAKE_CURRENT_LIST_DIR}/uimapanchorlayout.h
    ${CMAKE_CURRENT_LIST_DIR}/uisprite.cpp
    ${CMAKE_CURRENT_LIST_DIR}/uisprite.h

    # util
    ${CMAKE_CURRENT_LIST_DIR}/position.h
)

# Wire Protobuf headers + generated-source dir + lib into the (single) executable target.
# This file is included from the root CMakeLists.txt _before_ add_executable, so we can only
# extend the *_INCLUDE_DIRS / *_LIBRARIES lists that the root then consumes.
include_directories(${Protobuf_INCLUDE_DIRS} ${CMAKE_BINARY_DIR}/generated/proto)
set(framework_LIBRARIES ${framework_LIBRARIES} ${Protobuf_LIBRARIES})
