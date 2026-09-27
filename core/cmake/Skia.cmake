# Skia as the imported target Skia::skia.
#   wasm32: the pinned JetBrains/skia prebuilt (built with emsdk 4.0.7).
#   iOS:    built from source at the same commit by scripts/build-skia-ios.sh;
#           pass -DSKIA_SOURCE_DIR=<skia checkout>. The prebuilt iOS archives
#           target iOS 12.0/14.0, not 18.0.
# Compile defines follow JetBrains Skiko
# buildSrc/src/main/kotlin/tasks/configuration/CommonTasksConfiguration.kt
# skiaPreprocessorFlags (lines 68-128), plus SK_SUPPORT_PDF.
if(EMSCRIPTEN)
  include(FetchContent)
  set(SKIA_RELEASE m154-ab5932137b)
  FetchContent_Declare(skia
    URL https://github.com/JetBrains/skia/releases/download/${SKIA_RELEASE}/Skia-${SKIA_RELEASE}-wasm-Release-wasm.zip
    URL_HASH SHA256=a95e7a2aa89073e815ced111b9e811ecf9868d236bb0736c2d877b1ef57eb1f5
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
  FetchContent_MakeAvailable(skia)
  set(SKIA_ROOT "${skia_SOURCE_DIR}")
  file(GLOB SKIA_ARCHIVES "${SKIA_ROOT}/out/*/*.a")
elseif(CMAKE_SYSTEM_NAME STREQUAL "iOS")
  set(SKIA_SOURCE_DIR "" CACHE PATH "Skia checkout built by scripts/build-skia-ios.sh")
  if(CMAKE_OSX_SYSROOT MATCHES "[Ss]imulator")
    set(SKIA_OUT simulator)
  else()
    set(SKIA_OUT device)
  endif()
  set(SKIA_ROOT "${SKIA_SOURCE_DIR}")
  # Paragraph, Unicode, and HarfBuzz are separate archives in the source build.
  file(GLOB SKIA_ARCHIVES "${SKIA_ROOT}/out/${SKIA_OUT}/*.a")
else()
  message(FATAL_ERROR "No Skia build for ${CMAKE_SYSTEM_NAME}; targets are wasm32 and iOS arm64")
endif()

if(NOT SKIA_ARCHIVES)
  message(FATAL_ERROR "No Skia archives found under ${SKIA_ROOT}/out")
endif()
set(SKIA_ARCHIVES "${SKIA_ARCHIVES}" CACHE INTERNAL "Skia static archives")

add_library(Skia::skia INTERFACE IMPORTED GLOBAL)
target_include_directories(Skia::skia INTERFACE "${SKIA_ROOT}")
target_link_libraries(Skia::skia INTERFACE ${SKIA_ARCHIVES})
target_compile_definitions(Skia::skia INTERFACE
  SK_ALLOW_STATIC_GLOBAL_INITIALIZERS=1
  SK_FORCE_DISTANCE_FIELD_TEXT=0
  SK_GAMMA_APPLY_TO_A8
  SK_GAMMA_SRGB
  SK_SCALAR_TO_FLOAT_EXCLUDED
  SK_SUPPORT_GPU=1
  SK_GANESH
  SK_SUPPORT_OPENCL=0
  SK_SUPPORT_PDF
  NDEBUG)
if(EMSCRIPTEN)
  target_compile_definitions(Skia::skia INTERFACE SK_GL)
else()
  target_compile_definitions(Skia::skia INTERFACE SK_BUILD_FOR_IOS SK_METAL)
  target_link_libraries(Skia::skia INTERFACE
    "-framework Metal" "-framework Foundation" "-framework CoreGraphics"
    "-framework CoreText" "-framework CoreFoundation" "-framework QuartzCore")
endif()
