#include "platform.h"

#include "playlistmodel.h"

#include <QClipboard>
#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDesktopServices>
#include <QDir>
#include <QFileDialog>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJSEngine>
#include <QJsonArray>
#include <QJsonDocument>
#include <QKeyEvent>
#include <QLocale>
#include <QMouseEvent>
#include <QProcess>
#include <QQuickWindow>
#include <QStandardPaths>
#include <QUrl>
#include <QVersionNumber>

Platform *Platform::instance()
{
    static Platform *platform = new Platform;
    return platform;
}

Platform *Platform::create(QQmlEngine *, QJSEngine *)
{
    QJSEngine::setObjectOwnership(instance(), QJSEngine::CppOwnership);
    return instance();
}

Platform::Platform(QObject *parent)
    : QObject(parent)
{
}

void Platform::configure(const QStringList &files, bool fullscreen, const QString &selfTestDir)
{
    m_initialFiles = files;
    m_startFullscreen = fullscreen;
    m_selfTestDir = selfTestDir;
}

QString Platform::settingsFile() const
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/localtube");
    QDir().mkpath(dir);
    return QUrl::fromLocalFile(dir + QStringLiteral("/settings.conf")).toString();
}

bool Platform::hyprland() const
{
    return qEnvironmentVariableIsSet("HYPRLAND_INSTANCE_SIGNATURE");
}

QString Platform::version() const
{
    return QStringLiteral(LOCALTUBE_VERSION);
}

QStringList Platform::openFiles(const QString &startDir)
{
    const QString filter = tr("Videos") + QStringLiteral(" (") + MediaInfo::mediaFilters().join(QLatin1Char(' ')) + QStringLiteral(");;")
                           + tr("All files") + QStringLiteral(" (*)");
    return QFileDialog::getOpenFileNames(nullptr, tr("Open video"), startDir.isEmpty() ? QDir::homePath() : startDir, filter);
}

QString Platform::openFolder(const QString &startDir)
{
    return QFileDialog::getExistingDirectory(nullptr, tr("Open folder"), startDir.isEmpty() ? QDir::homePath() : startDir);
}

QString Platform::openSubtitle(const QString &startDir)
{
    return QFileDialog::getOpenFileName(nullptr, tr("Add subtitles"), startDir.isEmpty() ? QDir::homePath() : startDir,
                                        tr("Subtitles") + QStringLiteral(" (*.srt *.vtt *.ass *.ssa *.sub *.sup);;") + tr("All files") + QStringLiteral(" (*)"));
}

void Platform::copyText(const QString &text)
{
    QGuiApplication::clipboard()->setText(text);
}

void Platform::showInFolder(const QString &path)
{
    QDBusMessage msg = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.FileManager1"), QStringLiteral("/org/freedesktop/FileManager1"),
                                                      QStringLiteral("org.freedesktop.FileManager1"), QStringLiteral("ShowItems"));
    msg << QStringList {QUrl::fromLocalFile(path).toString()} << QString();
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [path](QDBusPendingCallWatcher *w) {
        if (w->isError())
            QDesktopServices::openUrl(QUrl::fromLocalFile(QFileInfo(path).absolutePath()));
        w->deleteLater();
    });
}

void Platform::inhibitIdle(bool inhibit)
{
    // Keeps hypridle (or any org.freedesktop.ScreenSaver provider) from
    // dimming or locking the screen while a video plays.
    m_inhibitWanted = inhibit;
    if (m_inhibitPending)
        return;
    if (inhibit && m_inhibitCookie == 0) {
        QDBusMessage msg = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.ScreenSaver"), QStringLiteral("/org/freedesktop/ScreenSaver"),
                                                          QStringLiteral("org.freedesktop.ScreenSaver"), QStringLiteral("Inhibit"));
        msg << QStringLiteral("localtube") << tr("Playing video");
        m_inhibitPending = true;
        auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(msg), this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
            QDBusPendingReply<uint> reply = *w;
            w->deleteLater();
            m_inhibitPending = false;
            if (reply.isError())
                return;
            m_inhibitCookie = reply.value();
            if (!m_inhibitWanted)
                inhibitIdle(false);
        });
    } else if (!inhibit && m_inhibitCookie != 0) {
        QDBusMessage msg = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.ScreenSaver"), QStringLiteral("/org/freedesktop/ScreenSaver"),
                                                          QStringLiteral("org.freedesktop.ScreenSaver"), QStringLiteral("UnInhibit"));
        msg << m_inhibitCookie;
        m_inhibitCookie = 0;
        QDBusConnection::sessionBus().asyncCall(msg);
    }
}

QJsonObject Platform::hyprClient() const
{
    QProcess p;
    p.start(QStringLiteral("hyprctl"), {QStringLiteral("clients"), QStringLiteral("-j")});
    if (!p.waitForFinished(1500))
        return {};
    const QJsonArray clients = QJsonDocument::fromJson(p.readAllStandardOutput()).array();
    const qint64 pid = QCoreApplication::applicationPid();
    for (const QJsonValue &v : clients) {
        if (v.toObject().value(QStringLiteral("pid")).toInteger() == pid)
            return v.toObject();
    }
    return {};
}

bool Platform::hyprlandLua() const
{
    // Hyprland 0.55 replaced the dispatcher syntax with a Lua API.
    static int lua = -1;
    if (lua < 0) {
        QProcess p;
        p.start(QStringLiteral("hyprctl"), {QStringLiteral("version"), QStringLiteral("-j")});
        p.waitForFinished(1500);
        QString tag = QJsonDocument::fromJson(p.readAllStandardOutput()).object().value(QStringLiteral("tag")).toString();
        if (tag.startsWith(QLatin1Char('v')))
            tag.remove(0, 1);
        lua = QVersionNumber::fromString(tag) >= QVersionNumber(0, 55) ? 1 : 0;
    }
    return lua == 1;
}

bool Platform::setMiniplayer(QWindow *, bool enabled)
{
    if (!hyprland())
        return false;
    const QJsonObject client = hyprClient();
    if (client.isEmpty())
        return false;
    const bool lua = hyprlandLua();
    const QString target = lua ? QStringLiteral("pid:%1").arg(QCoreApplication::applicationPid())
                               : QStringLiteral("address:") + client.value(QStringLiteral("address")).toString();
    const bool floating = client.value(QStringLiteral("floating")).toBool();
    const bool pinned = client.value(QStringLiteral("pinned")).toBool();

    // Each step: { lua call, classic dispatcher }.
    QList<QPair<QString, QString>> steps;
    const auto setFloating = [&](bool on) {
        steps.append({QStringLiteral("hl.dsp.window.float({ action = '%1', window = '%2' })").arg(on ? "set" : "unset", target),
                      QStringLiteral("dispatch togglefloating ") + target});
    };
    const auto setPinned = [&](bool on) {
        steps.append({QStringLiteral("hl.dsp.window.pin({ action = '%1', window = '%2' })").arg(on ? "set" : "unset", target),
                      QStringLiteral("dispatch pin ") + target});
    };
    const auto place = [&](int x, int y, int w, int h) {
        steps.append({QStringLiteral("hl.dsp.window.resize({ x = %1, y = %2, window = '%3' })").arg(w).arg(h).arg(target),
                      QStringLiteral("dispatch resizewindowpixel exact %1 %2,%3").arg(w).arg(h).arg(target)});
        steps.append({QStringLiteral("hl.dsp.window.move({ x = %1, y = %2, window = '%3' })").arg(x).arg(y).arg(target),
                      QStringLiteral("dispatch movewindowpixel exact %1 %2,%3").arg(x).arg(y).arg(target)});
    };

    if (enabled) {
        m_restoreState = client;
        QProcess p;
        p.start(QStringLiteral("hyprctl"), {QStringLiteral("monitors"), QStringLiteral("-j")});
        p.waitForFinished(1500);
        QJsonObject monitor;
        const QJsonArray monitors = QJsonDocument::fromJson(p.readAllStandardOutput()).array();
        for (const QJsonValue &v : monitors) {
            if (v.toObject().value(QStringLiteral("id")).toInt() == client.value(QStringLiteral("monitor")).toInt())
                monitor = v.toObject();
        }
        const double scale = monitor.value(QStringLiteral("scale")).toDouble(1.0);
        const int mx = monitor.value(QStringLiteral("x")).toInt();
        const int my = monitor.value(QStringLiteral("y")).toInt();
        const int mw = static_cast<int>(monitor.value(QStringLiteral("width")).toInt(1920) / scale);
        const int mh = static_cast<int>(monitor.value(QStringLiteral("height")).toInt(1080) / scale);
        const QJsonArray reserved = monitor.value(QStringLiteral("reserved")).toArray();
        const int w = qBound(320, mw / 3, 560);
        const int h = w * 9 / 16;
        if (!floating)
            setFloating(true);
        place(mx + mw - w - 20 - reserved.at(2).toInt(), my + mh - h - 20 - reserved.at(3).toInt(), w, h);
        if (!pinned)
            setPinned(true);
    } else {
        if (pinned && !m_restoreState.value(QStringLiteral("pinned")).toBool())
            setPinned(false);
        if (floating && !m_restoreState.value(QStringLiteral("floating")).toBool(true)) {
            setFloating(false);
        } else if (!m_restoreState.isEmpty()) {
            const QJsonArray size = m_restoreState.value(QStringLiteral("size")).toArray();
            const QJsonArray at = m_restoreState.value(QStringLiteral("at")).toArray();
            place(at.at(0).toInt(), at.at(1).toInt(), size.at(0).toInt(), size.at(1).toInt());
        }
        m_restoreState = {};
    }
    if (steps.isEmpty())
        return true;

    if (lua) {
        QString script;
        for (const auto &step : steps)
            script += QStringLiteral("hl.dispatch(") + step.first + QStringLiteral(") ");
        if (qEnvironmentVariableIsSet("LOCALTUBE_DEBUG"))
            fprintf(stderr, "[localtube] hyprctl eval %s\n", qPrintable(script));
        QProcess::startDetached(QStringLiteral("hyprctl"), {QStringLiteral("eval"), script});
    } else {
        QStringList cmds;
        for (const auto &step : steps)
            cmds << step.second;
        QProcess::startDetached(QStringLiteral("hyprctl"), {QStringLiteral("--batch"), cmds.join(QStringLiteral(" ; "))});
    }
    return true;
}

QString Platform::fileUrl(const QString &path)
{
    return QUrl::fromLocalFile(path).toString();
}

QString Platform::localPath(const QUrl &url)
{
    return url.isLocalFile() ? url.toLocalFile() : url.toString();
}

QString Platform::fileName(const QString &path)
{
    return QFileInfo(path).fileName();
}

QString Platform::dirName(const QString &path)
{
    return QFileInfo(path).absolutePath();
}

QString Platform::formatSize(qint64 bytes)
{
    return QLocale().formattedDataSize(bytes, 1, QLocale::DataSizeTraditionalFormat);
}

qint64 Platform::fileSize(const QString &path)
{
    return QFileInfo(path).size();
}

bool Platform::grab(QQuickWindow *window, const QString &file)
{
    return window && window->grabWindow().save(file);
}

void Platform::mouseMove(QQuickWindow *window, qreal x, qreal y)
{
    if (!window)
        return;
    QMouseEvent ev(QEvent::MouseMove, QPointF(x, y), window->mapToGlobal(QPointF(x, y)), Qt::NoButton, Qt::NoButton, Qt::NoModifier);
    QCoreApplication::sendEvent(window, &ev);
}

void Platform::mousePress(QQuickWindow *window, qreal x, qreal y)
{
    if (!window)
        return;
    QMouseEvent ev(QEvent::MouseButtonPress, QPointF(x, y), window->mapToGlobal(QPointF(x, y)), Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
    QCoreApplication::sendEvent(window, &ev);
}

void Platform::mouseRelease(QQuickWindow *window, qreal x, qreal y)
{
    if (!window)
        return;
    QMouseEvent ev(QEvent::MouseButtonRelease, QPointF(x, y), window->mapToGlobal(QPointF(x, y)), Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
    QCoreApplication::sendEvent(window, &ev);
}

void Platform::mouseClick(QQuickWindow *window, qreal x, qreal y, int button)
{
    if (!window)
        return;
    const auto b = static_cast<Qt::MouseButton>(button);
    QMouseEvent press(QEvent::MouseButtonPress, QPointF(x, y), window->mapToGlobal(QPointF(x, y)), b, b, Qt::NoModifier);
    QCoreApplication::sendEvent(window, &press);
    QMouseEvent release(QEvent::MouseButtonRelease, QPointF(x, y), window->mapToGlobal(QPointF(x, y)), b, Qt::NoButton, Qt::NoModifier);
    QCoreApplication::sendEvent(window, &release);
}

void Platform::key(QQuickWindow *window, int key, int modifiers, const QString &text)
{
    if (!window)
        return;
    QKeyEvent press(QEvent::KeyPress, key, Qt::KeyboardModifiers(modifiers), text);
    QCoreApplication::sendEvent(window, &press);
    QKeyEvent release(QEvent::KeyRelease, key, Qt::KeyboardModifiers(modifiers), text);
    QCoreApplication::sendEvent(window, &release);
}

void Platform::log(const QString &message)
{
    fprintf(stderr, "%s\n", qPrintable(message));
}

void Platform::quit(int code)
{
    QCoreApplication::exit(code);
}
