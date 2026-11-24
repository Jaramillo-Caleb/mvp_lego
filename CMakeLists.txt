cmake_minimum_required(VERSION 3.20)
project(mvp_lego VERSION 0.1.0 LANGUAGES CXX)

enable_testing()

option(OPENSIM_BUILD_GDEXTENSION "Build Godot GDExtension adapter" ON)

add_subdirectory(brain)

if(OPENSIM_BUILD_GDEXTENSION)
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/gdextension/godot-cpp/CMakeLists.txt")
        add_subdirectory(gdextension)
    else()
        message(STATUS "godot-cpp not found in gdextension/godot-cpp; skipping GDExtension.")
    endif()
endif()