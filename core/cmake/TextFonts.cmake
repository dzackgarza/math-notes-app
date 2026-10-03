# Shared font bytes for Skia Paragraph and the platform text input.
set(NOTO_REV ffebf8c1ee449e544955a7e813c54f9b73848eac)
set(NOTO_CACHE "${CMAKE_CURRENT_LIST_DIR}/../../.ci/fonts")
file(MAKE_DIRECTORY "${NOTO_CACHE}")
set(NOTO_FAMILIES NotoSansArabic NotoSansHebrew NotoSansDevanagari NotoSansSymbols2)
set(NOTO_HASHES
  ceea25b464a656dc3b26849bab9356740401af62aedf1bfa8b7f0d9b75925b1b
  a7fa16fffb27bedb060a0866267c29e9859aeb9c21cc33f5b3aaf6eb062eca85
  385e78e6359a9d88a0f243d53b1209d7548361ba2194e2b9ec779bcaa7e8949d
  630846d528dbe4c4981370a4d0a9475a1fd1491a129bb411f8e157cdb5de13c6)
foreach(FAMILY HASH IN ZIP_LISTS NOTO_FAMILIES NOTO_HASHES)
  set(FONT "${NOTO_CACHE}/${FAMILY}-Regular.ttf")
  if(EXISTS "${FONT}")
    file(SHA256 "${FONT}" ACTUAL)
    if(ACTUAL STREQUAL HASH)
      continue()
    endif()
  endif()
  file(DOWNLOAD "https://raw.githubusercontent.com/notofonts/noto-fonts/${NOTO_REV}/hinted/ttf/${FAMILY}/${FAMILY}-Regular.ttf"
    "${FONT}" EXPECTED_HASH "SHA256=${HASH}" TLS_VERIFY ON)
endforeach()
