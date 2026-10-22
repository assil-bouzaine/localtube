#include "mpvobject.h"

#include <QGuiApplication>
#include <QOpenGLContext>
#include <QOpenGLFramebufferObject>
#include <QPointer>
#include <QQuickWindow>
#include <QtGui/qguiapplication_platform.h>

#include <mpv/client.h>
#include <mpv/render_gl.h>

#include <atomic>
#include <cstring>
#include <deque>
#include <vector>

namespace {

QVariant nodeToVariant(const mpv_node *node)
{
    switch (node->format) {
    case MPV_FORMAT_STRING:
        return QString::fromUtf8(node->u.string);
    case MPV_FORMAT_FLAG:
        return node->u.flag != 0;
    case MPV_FORMAT_INT64:
        return static_cast<qlonglong>(node->u.int64);
    case MPV_FORMAT_DOUBLE:
        return node->u.double_;
    case MPV_FORMAT_NODE_ARRAY: {
        QVariantList list;
        list.reserve(node->u.list->num);
        for (int i = 0; i < node->u.list->num; ++i)
            list.append(nodeToVariant(&node->u.list->values[i]));
        return list;
    }
    case MPV_FORMAT_NODE_MAP: {
        QVariantMap map;
        for (int i = 0; i < node->u.list->num; ++i)
            map.insert(QString::fromUtf8(node->u.list->keys[i]), nodeToVariant(&node->u.list->values[i]));
        return map;
    }
    case MPV_FORMAT_BYTE_ARRAY:
        return QByteArray(static_cast<const char *>(node->u.ba->data), static_cast<qsizetype>(node->u.ba->size));
    default:
        return {};
    }
}

// Builds an mpv_node tree from a QVariant and owns all memory it points to.
class NodeBuilder
{
public:
    explicit NodeBuilder(const QVariant &value) { build(&m_root, value); }
    NodeBuilder(const NodeBuilder &) = delete;
    NodeBuilder &operator=(const NodeBuilder &) = delete;
    mpv_node *node() { return &m_root; }

private:
    void build(mpv_node *dst, const QVariant &v)
    {
        switch (v.typeId()) {
        case QMetaType::UnknownType:
            dst->format = MPV_FORMAT_NONE;
            break;
        case QMetaType::Bool:
            dst->format = MPV_FORMAT_FLAG;
            dst->u.flag = v.toBool() ? 1 : 0;
            break;
        case QMetaType::Int:
        case QMetaType::UInt:
        case QMetaType::Long:
        case QMetaType::LongLong:
        case QMetaType::ULongLong:
            dst->format = MPV_FORMAT_INT64;
            dst->u.int64 = v.toLongLong();
            break;
        case QMetaType::Float:
        case QMetaType::Double:
            dst->format = MPV_FORMAT_DOUBLE;
            dst->u.double_ = v.toDouble();
            break;
        case QMetaType::QVariantList:
        case QMetaType::QStringList: {
            const QVariantList list = v.toList();
            auto &values = m_values.emplace_back(list.size());
            for (qsizetype i = 0; i < list.size(); ++i)
                build(&values[i], list[i]);
            auto &l = m_lists.emplace_back();
            l.num = static_cast<int>(list.size());
            l.values = values.data();
            l.keys = nullptr;
            dst->format = MPV_FORMAT_NODE_ARRAY;
            dst->u.list = &l;
            break;
        }
        case QMetaType::QVariantMap: {
            const QVariantMap map = v.toMap();
            auto &values = m_values.emplace_back(map.size());
            auto &keys = m_keys.emplace_back(map.size());
            qsizetype i = 0;
            for (auto it = map.cbegin(); it != map.cend(); ++it, ++i) {
                keys[i] = m_strings.emplace_back(it.key().toUtf8()).data();
                build(&values[i], it.value());
            }
            auto &l = m_lists.emplace_back();
            l.num = static_cast<int>(map.size());
            l.values = values.data();
            l.keys = keys.data();
            dst->format = MPV_FORMAT_NODE_MAP;
            dst->u.list = &l;
            break;
        }
        default:
            dst->format = MPV_FORMAT_STRING;
            dst->u.string = m_strings.emplace_back(v.toString().toUtf8()).data();
            break;
        }
    }

    mpv_node m_root {};
    std::deque<QByteArray> m_strings;
    std::deque<std::vector<mpv_node>> m_values;
    std::deque<std::vector<char *>> m_keys;
    std::deque<mpv_node_list> m_lists;
};

enum PropertyId : uint64_t {
    PropPause = 1,
    PropTimePos,
    PropDuration,
    PropVolume,
    PropMute,
    PropSpeed,
    PropLoopFile,
    PropSeeking,
    PropPausedForCache,
    PropEofReached,
    PropIdleActive,
    PropPath,
    PropMediaTitle,
    PropChapterList,
    PropChapter,
    PropTrackList,
    PropVideoParams,
    PropMetadata,
    PropCacheTime,
    PropHwdec,
    PropFps,
};

struct ObservedProperty {
    PropertyId id;
    const char *name;
    mpv_format format;
};

constexpr ObservedProperty kObserved[] = {
    {PropPause, "pause", MPV_FORMAT_FLAG},
    {PropTimePos, "time-pos", MPV_FORMAT_DOUBLE},
    {PropDuration, "duration", MPV_FORMAT_DOUBLE},
    {PropVolume, "volume", MPV_FORMAT_DOUBLE},
    {PropMute, "mute", MPV_FORMAT_FLAG},
    {PropSpeed, "speed", MPV_FORMAT_DOUBLE},
    {PropLoopFile, "loop-file", MPV_FORMAT_STRING},
    {PropSeeking, "seeking", MPV_FORMAT_FLAG},
    {PropPausedForCache, "paused-for-cache", MPV_FORMAT_FLAG},
    {PropEofReached, "eof-reached", MPV_FORMAT_FLAG},
    {PropIdleActive, "idle-active", MPV_FORMAT_FLAG},
    {PropPath, "path", MPV_FORMAT_STRING},
    {PropMediaTitle, "media-title", MPV_FORMAT_STRING},
    {PropChapterList, "chapter-list", MPV_FORMAT_NODE},
    {PropChapter, "chapter", MPV_FORMAT_INT64},
    {PropTrackList, "track-list", MPV_FORMAT_NODE},
    {PropVideoParams, "video-params", MPV_FORMAT_NODE},
    {PropMetadata, "metadata", MPV_FORMAT_NODE},
    {PropCacheTime, "demuxer-cache-time", MPV_FORMAT_DOUBLE},
    {PropHwdec, "hwdec-current", MPV_FORMAT_STRING},
    {PropFps, "container-fps", MPV_FORMAT_DOUBLE},
};

void *getProcAddress(void *, const char *name)
{
    if (QOpenGLContext *ctx = QOpenGLContext::currentContext())
        return reinterpret_cast<void *>(ctx->getProcAddress(QByteArray(name)));
    return nullptr;
}

QVariantMap &defaultOptions()
{
    static QVariantMap options;
    return options;
}

} // namespace

// State shared between the QML item (GUI thread) and its renderer (render
// thread). Whichever side lets go last destroys the mpv core, after the render
// context has been freed on the render thread.
struct MpvCore {
    // Lives on the GUI thread. Callbacks from mpv threads are queued to it, so
    // they are dropped safely if the item is already gone.
    struct Notifier : QObject {
        QPointer<MpvObject> item;
    };

    mpv_handle *mpv = nullptr;
    Notifier *notifier = nullptr;
    std::atomic<mpv_render_context *> gl {nullptr};

    ~MpvCore()
    {
        if (mpv)
            mpv_terminate_destroy(mpv);
        if (notifier)
            notifier->deleteLater();
    }

    static void onWakeup(void *ctx)
    {
        auto *n = static_cast<Notifier *>(ctx);
        QMetaObject::invokeMethod(n, [n] { if (n->item) n->item->onMpvEvents(); }, Qt::QueuedConnection);
    }

    static void onRenderUpdate(void *ctx)
    {
        auto *n = static_cast<Notifier *>(ctx);
        QMetaObject::invokeMethod(n, [n] { if (n->item) n->item->update(); }, Qt::QueuedConnection);
    }

    void notifyRenderContextReady()
    {
        auto *n = notifier;
        QMetaObject::invokeMethod(n, [n] { if (n->item) n->item->onRenderContextReady(); }, Qt::QueuedConnection);
    }
};

class MpvRenderer : public QQuickFramebufferObject::Renderer
{
public:
    explicit MpvRenderer(std::shared_ptr<MpvCore> core)
        : m_core(std::move(core))
    {
    }

    ~MpvRenderer() override
    {
        QObject::disconnect(m_swapConnection);
        if (mpv_render_context *gl = m_core->gl.exchange(nullptr))
            mpv_render_context_free(gl);
    }

    QOpenGLFramebufferObject *createFramebufferObject(const QSize &size) override
    {
        if (!m_core->gl.load())
            initialize();
        QOpenGLFramebufferObjectFormat format;
        format.setAttachment(QOpenGLFramebufferObject::NoAttachment);
        return new QOpenGLFramebufferObject(size, format);
    }

    void synchronize(QQuickFramebufferObject *item) override
    {
        // Reporting buffer swaps lets mpv wait for real presentation before it
        // queues the next frame, which keeps frame pacing even.
        if (!m_swapConnection && item->window() && qEnvironmentVariable("LOCALTUBE_REPORT_SWAP", "1") != "0") {
            std::weak_ptr<MpvCore> weak = m_core;
            m_swapConnection = QObject::connect(item->window(), &QQuickWindow::frameSwapped, item->window(), [weak] {
                if (auto core = weak.lock()) {
                    if (mpv_render_context *gl = core->gl.load())
                        mpv_render_context_report_swap(gl);
                }
            }, Qt::DirectConnection);
        }
    }

    void render() override
    {
        mpv_render_context *gl = m_core->gl.load();
        QOpenGLFramebufferObject *fbo = framebufferObject();
        if (!gl || !fbo)
            return;
        mpv_opengl_fbo target {static_cast<int>(fbo->handle()), fbo->width(), fbo->height(), 0};
        mpv_render_param params[] = {
            {MPV_RENDER_PARAM_OPENGL_FBO, &target},
            {MPV_RENDER_PARAM_INVALID, nullptr},
        };
        mpv_render_context_render(gl, params);
    }

private:
    void initialize()
    {
        if (m_initializationAttempted || !m_core->mpv)
            return;
        m_initializationAttempted = true;
        mpv_opengl_init_params glInit {getProcAddress, nullptr};
        std::vector<mpv_render_param> params {
            {MPV_RENDER_PARAM_API_TYPE, const_cast<char *>(MPV_RENDER_API_TYPE_OPENGL)},
            {MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &glInit},
        };
        // The native display lets mpv set up zero-copy VA-API interop.
        const QString platform = QGuiApplication::platformName();
        if (platform.startsWith(QLatin1String("wayland"))) {
            if (auto *wl = qGuiApp->nativeInterface<QNativeInterface::QWaylandApplication>())
                params.push_back({MPV_RENDER_PARAM_WL_DISPLAY, wl->display()});
        } else if (platform == QLatin1String("xcb")) {
            if (auto *x11 = qGuiApp->nativeInterface<QNativeInterface::QX11Application>())
                params.push_back({MPV_RENDER_PARAM_X11_DISPLAY, x11->display()});
        }
        params.push_back({MPV_RENDER_PARAM_INVALID, nullptr});

        mpv_render_context *gl = nullptr;
        const int error = mpv_render_context_create(&gl, m_core->mpv, params.data());
        if (error < 0) {
            auto *n = m_core->notifier;
            const QString message = QStringLiteral("Could not initialize video rendering: %1. Check your graphics driver and restart LocalTube.").arg(QString::fromUtf8(mpv_error_string(error)));
            QMetaObject::invokeMethod(n, [n, message] {
                if (n->item) n->item->onRenderContextFailed(message);
            }, Qt::QueuedConnection);
            return;
        }
        m_core->gl.store(gl);
        mpv_render_context_set_update_callback(gl, MpvCore::onRenderUpdate, m_core->notifier);
        m_core->notifyRenderContextReady();
    }

    std::shared_ptr<MpvCore> m_core;
    QMetaObject::Connection m_swapConnection;
    bool m_initializationAttempted = false;
};

void MpvObject::setDefaultOptions(const QVariantMap &options)
{
    defaultOptions() = options;
}

MpvObject::MpvObject(QQuickItem *parent)
    : QQuickFramebufferObject(parent)
    , m_core(std::make_shared<MpvCore>())
{
    setMirrorVertically(false);

    m_core->notifier = new MpvCore::Notifier;
    m_core->notifier->item = this;

    mpv_handle *mpv = mpv_create();
    if (!mpv) {
        m_initializationError = tr("Could not create the playback engine. Restart LocalTube.");
        return;
    }
    m_core->mpv = mpv;

    const QVariantMap options = defaultOptions();
    for (auto it = options.cbegin(); it != options.cend(); ++it) {
        const int err = mpv_set_option_string(mpv, it.key().toUtf8().constData(), it.value().toString().toUtf8().constData());
        if (err < 0)
            qWarning("localtube: mpv option %s=%s: %s", qPrintable(it.key()), qPrintable(it.value().toString()), mpv_error_string(err));
    }

    const int initError = mpv_initialize(mpv);
    if (initError < 0) {
        m_initializationError = tr("Could not initialize playback: %1. Check your mpv configuration and restart LocalTube.")
                                    .arg(QString::fromUtf8(mpv_error_string(initError)));
        mpv_terminate_destroy(mpv);
        m_core->mpv = nullptr;
        return;
    }

    mpv_request_log_messages(mpv, qEnvironmentVariableIsSet("LOCALTUBE_DEBUG") ? "v" : "warn");
    for (const auto &p : kObserved)
        mpv_observe_property(mpv, p.id, p.name, p.format);
    mpv_set_wakeup_callback(mpv, MpvCore::onWakeup, m_core->notifier);
}

MpvObject::~MpvObject()
{
    // Silence playback right away; the core itself may outlive this item until
    // the render thread has released the render context.
    if (m_core->mpv) {
        const char *cmd[] = {"stop", nullptr};
        mpv_command_async(m_core->mpv, 0, cmd);
    }
}

QQuickFramebufferObject::Renderer *MpvObject::createRenderer() const
{
    return new MpvRenderer(m_core);
}

void MpvObject::onRenderContextReady()
{
    if (m_ready)
        return;
    m_ready = true;
    emit readyChanged();
}

void MpvObject::onRenderContextFailed(const QString &error)
{
    m_initializationError = error;
    emit initializationErrorChanged();
}

void MpvObject::onMpvEvents()
{
    mpv_handle *mpv = m_core->mpv;
    while (true) {
        mpv_event *event = mpv_wait_event(mpv, 0);
        if (event->event_id == MPV_EVENT_NONE)
            break;
        switch (event->event_id) {
        case MPV_EVENT_PROPERTY_CHANGE: {
            auto *prop = static_cast<mpv_event_property *>(event->data);
            handlePropertyChange(event->reply_userdata, prop->data, prop->format);
            break;
        }
        case MPV_EVENT_START_FILE:
            m_scrubs.cancel();
            emit fileStarted();
            break;
        case MPV_EVENT_FILE_LOADED:
            if (!m_fileLoaded) {
                m_fileLoaded = true;
                emit fileLoadedChanged();
            }
            emit fileReady();
            break;
        case MPV_EVENT_END_FILE: {
            auto *ef = static_cast<mpv_event_end_file *>(event->data);
            QString reason;
            switch (ef->reason) {
            case MPV_END_FILE_REASON_EOF: reason = QStringLiteral("eof"); break;
            case MPV_END_FILE_REASON_STOP: reason = QStringLiteral("stop"); break;
            case MPV_END_FILE_REASON_QUIT: reason = QStringLiteral("quit"); break;
            case MPV_END_FILE_REASON_ERROR: reason = QStringLiteral("error"); break;
            case MPV_END_FILE_REASON_REDIRECT: reason = QStringLiteral("redirect"); break;
            }
            const QString error = ef->reason == MPV_END_FILE_REASON_ERROR ? QString::fromUtf8(mpv_error_string(ef->error)) : QString();
            if (m_fileLoaded) {
                m_fileLoaded = false;
                emit fileLoadedChanged();
            }
            emit fileEnded(reason, error);
            break;
        }
        case MPV_EVENT_PLAYBACK_RESTART:
            if (const auto target = m_scrubs.completed())
                issueScrub(*target);
            emit playbackRestarted();
            break;
        case MPV_EVENT_SET_PROPERTY_REPLY:
            if (event->error < 0)
                fprintf(stderr, "[localtube] mpv request failed: %s\n", mpv_error_string(event->error));
            break;
        case MPV_EVENT_COMMAND_REPLY: {
            const QString operation = m_requests.take(event->reply_userdata);
            if (!operation.isEmpty()) {
                if (event->error < 0)
                    emit commandFailed(operation, QString::fromUtf8(mpv_error_string(event->error)));
                else
                    emit commandSucceeded(operation);
            }
            break;
        }
        case MPV_EVENT_LOG_MESSAGE: {
            auto *msg = static_cast<mpv_event_log_message *>(event->data);
            QByteArray text(msg->text);
            if (text.endsWith('\n'))
                text.chop(1);
            fprintf(stderr, "[mpv/%s] %s\n", msg->prefix, text.constData());
            break;
        }
        default:
            break;
        }
    }
}

template<typename T>
static bool assign(T &member, const T &value)
{
    if (member == value)
        return false;
    member = value;
    return true;
}

void MpvObject::handlePropertyChange(uint64_t id, void *data, int format)
{
    const auto flag = [&](bool fallback) { return format == MPV_FORMAT_FLAG ? *static_cast<int *>(data) != 0 : fallback; };
    const auto number = [&](double fallback) { return format == MPV_FORMAT_DOUBLE ? *static_cast<double *>(data) : fallback; };
    const auto string = [&] { return format == MPV_FORMAT_STRING ? QString::fromUtf8(*static_cast<char **>(data)) : QString(); };
    const auto node = [&] { return format == MPV_FORMAT_NODE ? nodeToVariant(static_cast<mpv_node *>(data)) : QVariant(); };

    switch (static_cast<PropertyId>(id)) {
    case PropPause:
        if (assign(m_paused, flag(false))) emit pausedChanged();
        break;
    case PropTimePos:
        if (assign(m_position, number(0))) emit positionChanged();
        break;
    case PropDuration:
        if (assign(m_duration, number(0))) emit durationChanged();
        break;
    case PropVolume:
        if (assign(m_volume, number(m_volume))) emit volumeChanged();
        break;
    case PropMute:
        if (assign(m_muted, flag(false))) emit mutedChanged();
        break;
    case PropSpeed:
        if (assign(m_speed, number(1))) emit speedChanged();
        break;
    case PropLoopFile: {
        const QString v = string();
        if (assign(m_loop, !v.isEmpty() && v != QLatin1String("no"))) emit loopChanged();
        break;
    }
    case PropSeeking:
        if (assign(m_seeking, flag(false))) emit seekingChanged();
        break;
    case PropPausedForCache:
        if (assign(m_buffering, flag(false))) emit bufferingChanged();
        break;
    case PropEofReached:
        if (assign(m_eofReached, flag(false))) emit eofReachedChanged();
        break;
    case PropIdleActive:
        if (assign(m_idle, flag(true))) emit idleChanged();
        break;
    case PropPath:
        if (assign(m_path, string())) emit pathChanged();
        break;
    case PropMediaTitle:
        if (assign(m_mediaTitle, string())) emit mediaTitleChanged();
        break;
    case PropChapterList:
        if (assign(m_chapters, node().toList())) emit chaptersChanged();
        break;
    case PropChapter:
        if (assign(m_chapter, format == MPV_FORMAT_INT64 ? static_cast<int>(*static_cast<int64_t *>(data)) : -1)) emit chapterChanged();
        break;
    case PropTrackList:
        if (assign(m_tracks, node().toList())) emit tracksChanged();
        break;
    case PropVideoParams:
        if (assign(m_videoParams, node().toMap())) emit videoParamsChanged();
        break;
    case PropMetadata:
        if (assign(m_metadata, node().toMap())) emit metadataChanged();
        break;
    case PropCacheTime:
        if (assign(m_cacheTime, number(0))) emit cacheTimeChanged();
        break;
    case PropHwdec:
        if (assign(m_hwdec, string())) emit hwdecChanged();
        break;
    case PropFps:
        if (assign(m_fps, number(0))) emit fpsChanged();
        break;
    }
}

void MpvObject::setPaused(bool paused)
{
    if (!m_core->mpv) return;
    int flag = paused ? 1 : 0;
    mpv_set_property_async(m_core->mpv, 0, "pause", MPV_FORMAT_FLAG, &flag);
}

void MpvObject::setVolume(double volume)
{
    if (!m_core->mpv) return;
    volume = qBound(0.0, volume, 100.0);
    mpv_set_property_async(m_core->mpv, 0, "volume", MPV_FORMAT_DOUBLE, &volume);
}

void MpvObject::setMuted(bool muted)
{
    if (!m_core->mpv) return;
    int flag = muted ? 1 : 0;
    mpv_set_property_async(m_core->mpv, 0, "mute", MPV_FORMAT_FLAG, &flag);
}

void MpvObject::setSpeed(double speed)
{
    if (!m_core->mpv) return;
    speed = qBound(0.07, speed, 16.0);
    mpv_set_property_async(m_core->mpv, 0, "speed", MPV_FORMAT_DOUBLE, &speed);
}

void MpvObject::setLoop(bool loop)
{
    if (!m_core->mpv) return;
    const char *value = loop ? "inf" : "no";
    mpv_set_property_async(m_core->mpv, 0, "loop-file", MPV_FORMAT_STRING, &value);
}

void MpvObject::setAudioFilter(const QString &filter)
{
    if (!m_core->mpv) return;
    if (m_audioFilter == filter)
        return;
    m_audioFilter = filter;
    const QByteArray value = filter.toUtf8();
    setOption(QStringLiteral("af"), QString::fromUtf8(value));
    emit audioFilterChanged();
}

void MpvObject::loadFile(const QString &path, double start, bool paused)
{
    m_scrubs.cancel();
    setPaused(paused);
    QVariantMap cmd {
        {QStringLiteral("name"), QStringLiteral("loadfile")},
        {QStringLiteral("url"), path},
        {QStringLiteral("flags"), QStringLiteral("replace")},
    };
    if (start > 0)
        cmd.insert(QStringLiteral("options"), QVariantMap {{QStringLiteral("start"), QString::number(start, 'f', 3)}});
    dispatchCommand(cmd, QStringLiteral("loadfile"));
}

void MpvObject::stop()
{
    m_scrubs.cancel();
    command({QStringLiteral("stop")});
}

void MpvObject::command(const QVariantList &args)
{
    dispatchCommand(args, args.isEmpty() ? QStringLiteral("command") : args.first().toString());
}

void MpvObject::dispatchCommand(const QVariant &args, const QString &operation)
{
    if (!m_core->mpv) {
        emit commandFailed(operation, m_initializationError);
        return;
    }
    const quint64 request = ++m_nextRequest;
    m_requests.insert(request, operation);
    NodeBuilder builder(args);
    const int error = mpv_command_node_async(m_core->mpv, request, builder.node());
    if (error < 0) {
        m_requests.remove(request);
        emit commandFailed(operation, QString::fromUtf8(mpv_error_string(error)));
    }
}

QVariant MpvObject::commandSync(const QVariantList &args)
{
    if (!m_core->mpv) return {};
    NodeBuilder builder(args);
    mpv_node result {};
    if (mpv_command_node(m_core->mpv, builder.node(), &result) < 0)
        return {};
    QVariant v = nodeToVariant(&result);
    mpv_free_node_contents(&result);
    return v;
}

QVariant MpvObject::getProperty(const QString &name) const
{
    if (!m_core->mpv) return {};
    mpv_node node {};
    if (mpv_get_property(m_core->mpv, name.toUtf8().constData(), MPV_FORMAT_NODE, &node) < 0)
        return {};
    QVariant v = nodeToVariant(&node);
    mpv_free_node_contents(&node);
    return v;
}

void MpvObject::setOption(const QString &name, const QVariant &value)
{
    if (!m_core->mpv) return;
    // Scalars go through mpv's option parser as strings: a JS number arrives
    // as a double, which mpv rejects for integer options.
    const int type = value.typeId();
    if (type != QMetaType::QVariantList && type != QMetaType::QVariantMap && type != QMetaType::QStringList) {
        QByteArray text;
        if (type == QMetaType::Bool)
            text = value.toBool() ? "yes" : "no";
        else if (type == QMetaType::Double || type == QMetaType::Float)
            text = QByteArray::number(value.toDouble(), 'g', 10);
        else
            text = value.toString().toUtf8();
        dispatchCommand(QVariantList {QStringLiteral("set"), name, QString::fromUtf8(text)}, QStringLiteral("set ") + name);
        return;
    }
    NodeBuilder builder(value);
    mpv_set_property_async(m_core->mpv, 0, name.toUtf8().constData(), MPV_FORMAT_NODE, builder.node());
}

void MpvObject::seekTo(double seconds, bool exact)
{
    m_scrubs.cancel();
    command({QStringLiteral("seek"), qMax(0.0, seconds), exact ? QStringLiteral("absolute+exact") : QStringLiteral("absolute+keyframes")});
}

void MpvObject::seekBy(double seconds, bool exact)
{
    m_scrubs.cancel();
    command({QStringLiteral("seek"), seconds, exact ? QStringLiteral("relative+exact") : QStringLiteral("relative+keyframes")});
}

void MpvObject::scrub(double seconds)
{
    if (const auto target = m_scrubs.request(qMax(0.0, seconds)))
        issueScrub(*target);
}

void MpvObject::issueScrub(double target)
{
    command({QStringLiteral("seek"), target, QStringLiteral("absolute+keyframes")});
}

void MpvObject::frameStep(bool backwards)
{
    m_scrubs.cancel();
    command({backwards ? QStringLiteral("frame-back-step") : QStringLiteral("frame-step")});
}

void MpvObject::selectTrack(const QString &type, const QVariant &id)
{
    const QString prop = type == QLatin1String("audio") ? QStringLiteral("aid")
                         : type == QLatin1String("video") ? QStringLiteral("vid")
                                                           : QStringLiteral("sid");
    setOption(prop, id.isValid() && !id.isNull() ? id : QVariant(QStringLiteral("no")));
}

void MpvObject::addSubtitle(const QString &path)
{
    command({QStringLiteral("sub-add"), path, QStringLiteral("select")});
}

void MpvObject::screenshot()
{
    command({QStringLiteral("screenshot")});
}
