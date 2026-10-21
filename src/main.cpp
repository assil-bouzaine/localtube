#include "mpvobject.h"
#include "platform.h"
#include "thumbnailer.h"

#include <QApplication>
#include <QCommandLineParser>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFontDatabase>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QStandardPaths>
#include <QSurfaceFormat>
#include <QThread>
#include <QUrl>

#include <clocale>
#include <memory>

namespace {

// libass (subtitles) cannot read Qt resources, so the bundled fonts are copied
// to a real directory that mpv's sub-fonts-dir can point at.
QString exportFonts()
{
    const QString dir = Thumbnailer::cacheRoot() + QStringLiteral("/fonts");
    QDir().mkpath(dir);
    for (const char *name : {"Roboto-Regular.ttf", "Roboto-Medium.ttf"}) {
        const QString src = QStringLiteral(":/qt/qml/LocalTube/assets/fonts/") + QLatin1String(name);
        const QString dst = dir + QLatin1Char('/') + QLatin1String(name);
        if (!QFile::exists(dst) || QFileInfo(dst).size() != QFileInfo(src).size()) {
            QFile::remove(dst);
            QFile::copy(src, dst);
        }
    }
    return dir;
}

QVariantMap mpvDefaults(const QString &fontsDir)
{
    const QString pictures = QStandardPaths::writableLocation(QStandardPaths::PicturesLocation);
    QVariantMap o {
        {QStringLiteral("vo"), QStringLiteral("libmpv")},
        // VA-API first (Intel/AMD, and NVIDIA via nvidia-vaapi-driver), then
        // mpv's safe list (e.g. NVDEC).
        {QStringLiteral("hwdec"), qEnvironmentVariable("LOCALTUBE_HWDEC", QStringLiteral("vaapi,auto-safe"))},
        {QStringLiteral("keep-open"), QStringLiteral("yes")},
        {QStringLiteral("idle"), QStringLiteral("yes")},
        {QStringLiteral("osd-level"), QStringLiteral("0")},
        {QStringLiteral("input-default-bindings"), QStringLiteral("no")},
        {QStringLiteral("input-vo-keyboard"), QStringLiteral("no")},
        {QStringLiteral("load-scripts"), QStringLiteral("no")},
        {QStringLiteral("ytdl"), QStringLiteral("no")},
        {QStringLiteral("audio-client-name"), QStringLiteral("localtube")},
        // Never block Qt's render thread waiting for a frame's display time;
        // the frame is presented on the next vsync instead, keeping the UI at
        // full frame rate during playback.
        {QStringLiteral("video-timing-offset"), QStringLiteral("0")},
        // YouTube-like buffer (also makes short backward seeks instant).
        {QStringLiteral("cache"), QStringLiteral("yes")},
        {QStringLiteral("cache-secs"), QStringLiteral("60")},
        {QStringLiteral("demuxer-max-bytes"), QStringLiteral("256MiB")},
        {QStringLiteral("demuxer-max-back-bytes"), QStringLiteral("64MiB")},
        // Cheap but good scaling for integrated GPUs: avoids a full-resolution
        // linear-light pass when 4K is downscaled to the screen.
        {QStringLiteral("linear-downscaling"), QStringLiteral("no")},
        {QStringLiteral("hr-seek-framedrop"), QStringLiteral("yes")},
        // Subtitles styled like YouTube captions.
        {QStringLiteral("sub-auto"), QStringLiteral("fuzzy")},
        {QStringLiteral("sub-file-paths"), QStringLiteral("subs:Subs:subtitles:Subtitles")},
        {QStringLiteral("sub-fonts-dir"), fontsDir},
        {QStringLiteral("sub-font"), QStringLiteral("Roboto")},
        {QStringLiteral("sub-font-size"), QStringLiteral("34")},
        {QStringLiteral("sub-color"), QStringLiteral("#FFFFFFFF")},
        {QStringLiteral("sub-border-style"), QStringLiteral("background-box")},
        {QStringLiteral("sub-back-color"), QStringLiteral("#BF080808")},
        {QStringLiteral("sub-outline-size"), QStringLiteral("4")},
        {QStringLiteral("sub-shadow-offset"), QStringLiteral("0")},
        {QStringLiteral("sub-margin-y"), QStringLiteral("30")},
        {QStringLiteral("screenshot-directory"), pictures},
        {QStringLiteral("screenshot-template"), QStringLiteral("localtube-%F-%wH.%wM.%wS")},
    };

    // Power users can tune mpv with ~/.config/localtube/mpv.conf.
    const QString configDir = QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/localtube");
    if (QFile::exists(configDir + QStringLiteral("/mpv.conf"))) {
        o.insert(QStringLiteral("config-dir"), configDir);
        o.insert(QStringLiteral("config"), QStringLiteral("yes"));
    }
    return o;
}

} // namespace

int main(int argc, char *argv[])
{
    // EGL is required for zero-copy VA-API frames, also under X11.
    if (qEnvironmentVariableIsEmpty("QT_XCB_GL_INTEGRATION"))
        qputenv("QT_XCB_GL_INTEGRATION", "xcb_egl");
    QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);
    QSurfaceFormat format = QSurfaceFormat::defaultFormat();
    format.setSwapInterval(1);
    QSurfaceFormat::setDefaultFormat(format);

    QApplication app(argc, argv);
    QApplication::setApplicationName(QStringLiteral("localtube"));
    QApplication::setApplicationDisplayName(QStringLiteral("LocalTube"));
    QApplication::setApplicationVersion(QStringLiteral(LOCALTUBE_VERSION));
    QApplication::setDesktopFileName(QStringLiteral("localtube"));
    QApplication::setWindowIcon(QIcon::fromTheme(QStringLiteral("localtube"), QIcon(QStringLiteral(":/qt/qml/LocalTube/data/localtube.svg"))));

    // libmpv requires the C locale for number parsing.
    std::setlocale(LC_NUMERIC, "C");

    QCommandLineParser parser;
    parser.setApplicationDescription(QStringLiteral("A YouTube-style video player for local files."));
    parser.addHelpOption();
    parser.addVersionOption();
    parser.addPositionalArgument(QStringLiteral("files"), QStringLiteral("Videos or folders to open."), QStringLiteral("[files...]"));
    QCommandLineOption fullscreenOpt({QStringLiteral("f"), QStringLiteral("fullscreen")}, QStringLiteral("Start in full screen."));
    QCommandLineOption mpvOpt(QStringLiteral("mpv-opt"), QStringLiteral("Pass an option to mpv, e.g. --mpv-opt hwdec=no."), QStringLiteral("key=value"));
    QCommandLineOption selfTestOpt(QStringLiteral("self-test"), QStringLiteral("Run the UI self-test and save screenshots to <dir>."), QStringLiteral("dir"));
    selfTestOpt.setFlags(QCommandLineOption::HiddenFromHelp);
    parser.addOptions({fullscreenOpt, mpvOpt, selfTestOpt});
    parser.process(app);

    QStringList files;
    for (const QString &arg : parser.positionalArguments()) {
        const QUrl url(arg);
        files << (url.isLocalFile() ? url.toLocalFile() : QFileInfo(arg).absoluteFilePath());
    }

    QFontDatabase::addApplicationFont(QStringLiteral(":/qt/qml/LocalTube/assets/fonts/Roboto-Regular.ttf"));
    QFontDatabase::addApplicationFont(QStringLiteral(":/qt/qml/LocalTube/assets/fonts/Roboto-Medium.ttf"));

    QVariantMap options = mpvDefaults(exportFonts());
    for (const QString &opt : parser.values(mpvOpt)) {
        const qsizetype eq = opt.indexOf(QLatin1Char('='));
        if (eq > 0)
            options.insert(opt.left(eq), opt.mid(eq + 1));
        else
            options.insert(opt, QStringLiteral("yes"));
    }
    MpvObject::setDefaultOptions(options);

    Platform::instance()->configure(files, parser.isSet(fullscreenOpt), parser.value(selfTestOpt));

    std::unique_ptr<QThread> cleanup(QThread::create([] { Thumbnailer::cleanupCache(45); }));
    cleanup->start(QThread::IdlePriority);

    QQmlApplicationEngine engine;
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app, [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("LocalTube", "Main");
    const int code = app.exec();
    cleanup->wait();
    return code;
}
