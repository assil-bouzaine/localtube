cmake_minimum_required(VERSION 3.21)
project(localtube VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

find_package(Qt6 6.8 REQUIRED COMPONENTS Core Gui Qml Quick OpenGL Widgets DBus ShaderTools Concurrent)
find_package(PkgConfig REQUIRED)
pkg_check_modules(MPV REQUIRED IMPORTED_TARGET mpv)
pkg_check_modules(LIBAV REQUIRED IMPORTED_TARGET libavformat libavcodec libavutil libswscale)

qt_standard_project_setup(REQUIRES 6.8)

qt_add_executable(localtube
    src/main.cpp
    src/mpvobject.cpp src/mpvobject.h
    src/thumbnailer.cpp src/thumbnailer.h
    src/framegrabber.cpp src/framegrabber.h
    src/playlistmodel.cpp src/playlistmodel.h
    src/history.cpp src/history.h
    src/platform.cpp src/platform.h
    src/mpris.cpp src/mpris.h
)

set_source_files_properties(qml/Theme.qml qml/Icons.qml
    PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(localtube
    URI LocalTube
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/Theme.qml
        qml/Icons.qml
        qml/Icon.qml
        qml/Frosted.qml
        qml/RoundedImage.qml
        qml/PlayerView.qml
        qml/AdaptiveQuality.qml
        qml/ControlBar.qml
        qml/ProgressBar.qml
        qml/PillButton.qml
        qml/PlayButton.qml
        qml/VolumeControl.qml
        qml/AutoplayToggle.qml
        qml/Tooltip.qml
        qml/SettingsMenu.qml
        qml/MenuRow.qml
        qml/ContextMenu.qml
        qml/ChapterMenu.qml
        qml/Bezel.qml
        qml/SeekIndicator.qml
        qml/Spinner.qml
        qml/StatsPanel.qml
        qml/ShortcutsDialog.qml
        qml/UpNext.qml
        qml/PlaylistPanel.qml
        qml/HomeScreen.qml
        qml/Toggle.qml
        qml/SelfTest.qml
    RESOURCES
        assets/fonts/Roboto-Regular.ttf
        assets/fonts/Roboto-Medium.ttf
        data/localtube.svg
)

qt_add_shaders(localtube "localtube_shaders"
    PREFIX "/"
    GLSL "300es,330"
    FILES
        shaders/frosted.frag
        shaders/rounded.frag
)

target_include_directories(localtube PRIVATE src)
target_compile_definitions(localtube PRIVATE LOCALTUBE_VERSION="${PROJECT_VERSION}")
target_link_libraries(localtube PRIVATE
    Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::OpenGL Qt6::Widgets Qt6::DBus Qt6::Concurrent
    PkgConfig::MPV PkgConfig::LIBAV)

include(GNUInstallDirs)
configure_file(data/localtube.desktop.in localtube.desktop @ONLY)
install(TARGETS localtube RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/localtube.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
install(FILES data/localtube.svg DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps)
install(FILES assets/fonts/OFL.txt DESTINATION ${CMAKE_INSTALL_DATADIR}/licenses/localtube RENAME Roboto-OFL.txt)

include(CTest)
if(BUILD_TESTING)
    find_package(Qt6 REQUIRED COMPONENTS Test)
    qt_add_executable(localtube_core_tests
        tests/core_test.cpp
        src/history.cpp src/history.h
        src/playlistmodel.cpp src/playlistmodel.h
        src/thumbnailer.cpp src/thumbnailer.h
        src/framegrabber.cpp src/framegrabber.h
        src/mpvobject.cpp src/mpvobject.h
    )
    target_include_directories(localtube_core_tests PRIVATE src)
    target_compile_definitions(localtube_core_tests PRIVATE LOCALTUBE_EXECUTABLE="$<TARGET_FILE:localtube>")
    add_dependencies(localtube_core_tests localtube)
    target_link_libraries(localtube_core_tests PRIVATE Qt6::Test Qt6::Gui Qt6::Qml Qt6::Quick Qt6::OpenGL Qt6::Concurrent PkgConfig::LIBAV PkgConfig::MPV)
    add_test(NAME core COMMAND localtube_core_tests)
    set_tests_properties(core PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software")
endif()
