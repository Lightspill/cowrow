include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(cowrow_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(cowrow_setup_options)
  option(cowrow_ENABLE_HARDENING "Enable hardening" ON)
  option(cowrow_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    cowrow_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    cowrow_ENABLE_HARDENING
    OFF)

  cowrow_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR cowrow_PACKAGING_MAINTAINER_MODE)
    option(cowrow_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(cowrow_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(cowrow_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(cowrow_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(cowrow_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(cowrow_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(cowrow_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(cowrow_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(cowrow_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(cowrow_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(cowrow_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(cowrow_ENABLE_PCH "Enable precompiled headers" OFF)
    option(cowrow_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(cowrow_ENABLE_IPO "Enable IPO/LTO" ON)
    option(cowrow_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(cowrow_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(cowrow_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(cowrow_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(cowrow_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(cowrow_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(cowrow_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(cowrow_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(cowrow_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(cowrow_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(cowrow_ENABLE_PCH "Enable precompiled headers" OFF)
    option(cowrow_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      cowrow_ENABLE_IPO
      cowrow_WARNINGS_AS_ERRORS
      cowrow_ENABLE_USER_LINKER
      cowrow_ENABLE_SANITIZER_ADDRESS
      cowrow_ENABLE_SANITIZER_LEAK
      cowrow_ENABLE_SANITIZER_UNDEFINED
      cowrow_ENABLE_SANITIZER_THREAD
      cowrow_ENABLE_SANITIZER_MEMORY
      cowrow_ENABLE_UNITY_BUILD
      cowrow_ENABLE_CLANG_TIDY
      cowrow_ENABLE_CPPCHECK
      cowrow_ENABLE_COVERAGE
      cowrow_ENABLE_PCH
      cowrow_ENABLE_CACHE)
  endif()

  cowrow_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (cowrow_ENABLE_SANITIZER_ADDRESS OR cowrow_ENABLE_SANITIZER_THREAD OR cowrow_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(cowrow_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(cowrow_global_options)
  if(cowrow_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    cowrow_enable_ipo()
  endif()

  cowrow_supports_sanitizers()

  if(cowrow_ENABLE_HARDENING AND cowrow_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR cowrow_ENABLE_SANITIZER_UNDEFINED
       OR cowrow_ENABLE_SANITIZER_ADDRESS
       OR cowrow_ENABLE_SANITIZER_THREAD
       OR cowrow_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${cowrow_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${cowrow_ENABLE_SANITIZER_UNDEFINED}")
    cowrow_enable_hardening(cowrow_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(cowrow_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(cowrow_warnings INTERFACE)
  add_library(cowrow_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  cowrow_set_project_warnings(
    cowrow_warnings
    ${cowrow_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(cowrow_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    cowrow_configure_linker(cowrow_options)
  endif()

  include(cmake/Sanitizers.cmake)
  cowrow_enable_sanitizers(
    cowrow_options
    ${cowrow_ENABLE_SANITIZER_ADDRESS}
    ${cowrow_ENABLE_SANITIZER_LEAK}
    ${cowrow_ENABLE_SANITIZER_UNDEFINED}
    ${cowrow_ENABLE_SANITIZER_THREAD}
    ${cowrow_ENABLE_SANITIZER_MEMORY})

  set_target_properties(cowrow_options PROPERTIES UNITY_BUILD ${cowrow_ENABLE_UNITY_BUILD})

  if(cowrow_ENABLE_PCH)
    target_precompile_headers(
      cowrow_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(cowrow_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    cowrow_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(cowrow_ENABLE_CLANG_TIDY)
    cowrow_enable_clang_tidy(cowrow_options ${cowrow_WARNINGS_AS_ERRORS})
  endif()

  if(cowrow_ENABLE_CPPCHECK)
    cowrow_enable_cppcheck(${cowrow_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(cowrow_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    cowrow_enable_coverage(cowrow_options)
  endif()

  if(cowrow_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(cowrow_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(cowrow_ENABLE_HARDENING AND NOT cowrow_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR cowrow_ENABLE_SANITIZER_UNDEFINED
       OR cowrow_ENABLE_SANITIZER_ADDRESS
       OR cowrow_ENABLE_SANITIZER_THREAD
       OR cowrow_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    cowrow_enable_hardening(cowrow_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
