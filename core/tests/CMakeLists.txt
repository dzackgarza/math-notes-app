set(INK_DOCUMENTS_DIR "${PROJECT_SOURCE_DIR}/../tests/documents")

find_package(Catch2 3 CONFIG REQUIRED)
include(Catch)

add_executable(ink_tests test_version.cpp test_pdf.cpp test_ink.cpp test_document.cpp test_editor.cpp
  test_render.cpp test_abi.cpp test_pages.cpp test_history.cpp test_erase.cpp test_selection.cpp test_space.cpp test_pens.cpp
  support/trace.cpp support/notebook_dir.cpp support/write_fixture.cpp)
target_include_directories(ink_tests PRIVATE . ../src)
target_compile_definitions(ink_tests PRIVATE
  INK_FIXTURE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/fixtures"
  INK_DOCUMENTS_DIR="${INK_DOCUMENTS_DIR}")
target_link_libraries(ink_tests PRIVATE ink Catch2::Catch2WithMain)
target_compile_definitions(ink_tests PRIVATE INK_TEST_VERSION="${PROJECT_VERSION}")
if(EMSCRIPTEN)
  # adobe/lagrange cmake/lagrange/lagrange_add_executable.cmake:53-69
  target_link_options(ink_tests PRIVATE
    -sENVIRONMENT=node -sNODERAWFS=1 -sEXIT_RUNTIME=1 -sALLOW_MEMORY_GROWTH=1)
endif()
# adobe/lagrange cmake/lagrange/lagrange_add_test.cmake:60-69
catch_discover_tests(ink_tests DISCOVERY_MODE PRE_TEST)

if(EMSCRIPTEN)
  add_subdirectory(webgl)
endif()

# Writes core/tests/fixtures/documents from tests/documents (just document-fixtures).
add_executable(write_documents write_documents.cpp support/notebook_dir.cpp)
target_include_directories(write_documents PRIVATE . ../src)
target_link_libraries(write_documents PRIVATE ink)
if(EMSCRIPTEN)
  target_link_options(write_documents PRIVATE
    -sENVIRONMENT=node -sNODERAWFS=1 -sEXIT_RUNTIME=1 -sALLOW_MEMORY_GROWTH=1)
endif()

# Writes core/tests/fixtures/templates (just template-fixtures).
add_executable(write_templates write_templates.cpp support/notebook_dir.cpp)
target_include_directories(write_templates PRIVATE . ../src)
target_link_libraries(write_templates PRIVATE ink)
if(EMSCRIPTEN)
  target_link_options(write_templates PRIVATE
    -sENVIRONMENT=node -sNODERAWFS=1 -sEXIT_RUNTIME=1 -sALLOW_MEMORY_GROWTH=1)
endif()
