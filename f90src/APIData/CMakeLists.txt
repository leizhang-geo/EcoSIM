set(APIDATA_SOURCES
  PlantAPIData.F90
)

#include_directories(${CMAKE_BINARY_DIR}/f90src/Utils/)
#include_directories(${CMAKE_BINARY_DIR}/f90src/Modelconfig/)
#include_directories(${CMAKE_BINARY_DIR}/f90src/Modelpars/)
include(add_ecosim_library)
add_ecosim_library(APIData ${APIDATA_SOURCES})

target_include_directories(APIData PRIVATE 
  ${CMAKE_BINARY_DIR}/f90src/Utils/
  ${CMAKE_BINARY_DIR}/f90src/Modelconfig/
  ${CMAKE_BINARY_DIR}/f90src/Modelpars/
  ${CMAKE_BINARY_DIR})


set(ECOSIM_LIBRARIES ${ECOSIM_LIBRARIES};APIData PARENT_SCOPE)
set(ECOSIM_LIBRARIES ${ECOSIM_LIBRARIES};APIData)
install(TARGETS APIData DESTINATION ${CMAKE_BINARY_DIR}/lib)

if (NOT CMAKE_INSTALL_PREFIX STREQUAL "INSTALL_DISABLED")
  install(TARGETS APIData DESTINATION lib)
  file(GLOB HEADERS *.h)
  install(FILES ${HEADERS} DESTINATION include/)
endif()
