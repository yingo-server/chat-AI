cmake_minimum_required(VERSION 3.18.1)
project(vault CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

add_compile_options(
    -fvisibility=hidden
    -fvisibility-inlines-hidden
    -ffunction-sections
    -fdata-sections
    -O3
)
add_link_options(
    -Wl,--gc-sections
    -Wl,--exclude-libs,ALL
    -Wl,-z,now
    -Wl,-z,relro
    -Wl,--strip-all
)

add_library(vault SHARED
    vault.cpp
)

find_library(log-lib log)
target_link_libraries(vault ${log-lib})

target_compile_definitions(vault PRIVATE VAULT_BUILD=1)