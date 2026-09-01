cmake_minimum_required(VERSION 3.21)

project(NotepadReplacerLauncher VERSION 0.0.0.2 LANGUAGES CXX RC)

option(NOTEPADREPLACER_STATIC_CRT "Link the MSVC runtime statically (/MT)" ON)
option(NOTEPADREPLACER_BUILD_CONTEXT_MENU "Build the Win11 context-menu DLL" ON)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_library(launcher_core STATIC
    src/launcher_core.cpp
    src/launcher_core.h
)
target_compile_features(launcher_core PUBLIC cxx_std_17)
target_compile_definitions(launcher_core PUBLIC UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
target_link_libraries(launcher_core PUBLIC advapi32)

add_executable(NotepadReplacerLauncher WIN32
    src/launcher_main.cpp
    src/version.rc
)
target_link_libraries(NotepadReplacerLauncher PRIVATE launcher_core shell32)
target_compile_definitions(NotepadReplacerLauncher PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
set_target_properties(NotepadReplacerLauncher PROPERTIES OUTPUT_NAME "NotepadReplacerLauncher")

if(MSVC)
    if(NOTEPADREPLACER_STATIC_CRT)
        set(_runtime "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    else()
        set(_runtime "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL")
    endif()
    set_property(TARGET launcher_core NotepadReplacerLauncher PROPERTY MSVC_RUNTIME_LIBRARY "${_runtime}")
    target_compile_options(launcher_core PRIVATE $<$<CONFIG:Release>:/O1> $<$<CONFIG:Release>:/GL>)
    target_compile_options(NotepadReplacerLauncher PRIVATE $<$<CONFIG:Release>:/O1> $<$<CONFIG:Release>:/GL>)
    target_link_options(NotepadReplacerLauncher PRIVATE
        $<$<CONFIG:Release>:/LTCG>
        $<$<CONFIG:Release>:/OPT:REF>
        $<$<CONFIG:Release>:/OPT:ICF>
        $<$<CONFIG:Release>:/INCREMENTAL:NO>
    )
endif()

if(NOTEPADREPLACER_BUILD_CONTEXT_MENU)
    add_library(NotepadReplacerContextMenu SHARED
        src/context_menu.cpp
        src/context_menu.rc
        src/context_menu.def
    )
    target_link_libraries(NotepadReplacerContextMenu PRIVATE launcher_core shell32 ole32 advapi32)
    target_compile_definitions(NotepadReplacerContextMenu PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX _WIN32_WINNT=0x0A00)
    set_target_properties(NotepadReplacerContextMenu PROPERTIES OUTPUT_NAME "NotepadReplacerContextMenu")
    if(MSVC)
        set_property(TARGET NotepadReplacerContextMenu PROPERTY MSVC_RUNTIME_LIBRARY "${_runtime}")
        target_compile_options(NotepadReplacerContextMenu PRIVATE /utf-8 $<$<CONFIG:Release>:/O1> $<$<CONFIG:Release>:/GL>)
        target_link_options(NotepadReplacerContextMenu PRIVATE $<$<CONFIG:Release>:/LTCG> $<$<CONFIG:Release>:/OPT:REF> $<$<CONFIG:Release>:/OPT:ICF> $<$<CONFIG:Release>:/INCREMENTAL:NO>)
    endif()
endif()

include(CTest)
if(BUILD_TESTING)
    add_executable(launcher_core_tests tests/launcher_core_tests.cpp)
    target_link_libraries(launcher_core_tests PRIVATE launcher_core)
    target_compile_definitions(launcher_core_tests PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
    if(MSVC)
        set_property(TARGET launcher_core_tests PROPERTY MSVC_RUNTIME_LIBRARY "${_runtime}")
        target_compile_options(launcher_core_tests PRIVATE $<$<CONFIG:Release>:/O1> $<$<CONFIG:Release>:/GL>)
        target_link_options(launcher_core_tests PRIVATE
            $<$<CONFIG:Release>:/LTCG>
            $<$<CONFIG:Release>:/OPT:REF>
            $<$<CONFIG:Release>:/OPT:ICF>
            $<$<CONFIG:Release>:/INCREMENTAL:NO>
        )
    endif()
    add_test(NAME launcher_core_tests COMMAND launcher_core_tests)
endif()
