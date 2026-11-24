add_library(opensim_brain STATIC
    src/ConnectionGraph.cpp
    src/KinematicSolver.cpp
    src/Simulation.cpp
)

target_include_directories(opensim_brain
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_compile_features(opensim_brain PUBLIC cxx_std_20)
set_target_properties(opensim_brain PROPERTIES
    CXX_STANDARD_REQUIRED ON
    CXX_EXTENSIONS OFF
    POSITION_INDEPENDENT_CODE ON
)

target_compile_options(opensim_brain PRIVATE
    $<$<CXX_COMPILER_ID:MSVC>:/W4>
    $<$<NOT:$<CXX_COMPILER_ID:MSVC>>:-Wall -Wextra -Wpedantic>
)

add_executable(opensim_brain_tests
    tests/test_kinematics.cpp
)

target_link_libraries(opensim_brain_tests PRIVATE opensim_brain)
target_compile_options(opensim_brain_tests PRIVATE
    $<$<CXX_COMPILER_ID:MSVC>:/W4>
    $<$<NOT:$<CXX_COMPILER_ID:MSVC>>:-Wall -Wextra -Wpedantic>
)

add_test(NAME opensim_brain_kinematics COMMAND opensim_brain_tests)