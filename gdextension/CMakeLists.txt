set(GODOTCPP_API_VERSION "4.7" CACHE STRING "Target Godot API version" FORCE)
set(GODOTCPP_TARGET "template_debug" CACHE STRING "Target godot-cpp build" FORCE)
set(GODOTCPP_USE_HOT_RELOAD ON CACHE BOOL "Enable hot reload support" FORCE)

add_subdirectory(godot-cpp SYSTEM)

add_library(opensim_gdext SHARED
    src/OpenSimNode.cpp
    src/register_types.cpp
)

target_link_libraries(opensim_gdext
    PRIVATE
        opensim_brain
        godot::cpp
)

target_compile_features(opensim_gdext PRIVATE cxx_std_20)

set(OPENSIM_EXT_OUTPUT_DIR "${CMAKE_SOURCE_DIR}/app/bin")

set_target_properties(opensim_gdext PROPERTIES
    CXX_STANDARD_REQUIRED ON
    CXX_EXTENSIONS OFF
    RUNTIME_OUTPUT_DIRECTORY "${OPENSIM_EXT_OUTPUT_DIR}"
    LIBRARY_OUTPUT_DIRECTORY "${OPENSIM_EXT_OUTPUT_DIR}"
    RUNTIME_OUTPUT_DIRECTORY_DEBUG "${OPENSIM_EXT_OUTPUT_DIR}"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE "${OPENSIM_EXT_OUTPUT_DIR}"
    LIBRARY_OUTPUT_DIRECTORY_DEBUG "${OPENSIM_EXT_OUTPUT_DIR}"
    LIBRARY_OUTPUT_DIRECTORY_RELEASE "${OPENSIM_EXT_OUTPUT_DIR}"
)

if(WIN32)
    set_target_properties(opensim_gdext PROPERTIES PREFIX "")
endif()

target_compile_options(opensim_gdext PRIVATE
    $<$<CXX_COMPILER_ID:MSVC>:/W4>
    $<$<NOT:$<CXX_COMPILER_ID:MSVC>>:-Wall -Wextra -Wpedantic>
)

if(WIN32 AND CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    target_link_options(opensim_gdext PRIVATE
        -static-libgcc
        -static-libstdc++
    )
endif()