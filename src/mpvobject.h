#pragma once

#include <QElapsedTimer>
#include <QQuickFramebufferObject>
#include <QVariant>
#include <QtQml/qqmlregistration.h>

#include <memory>

struct MpvCore;

// A Qt Quick item that renders libmpv video through the OpenGL render API and
// exposes the player state to QML as ordinary properties.
class MpvObject : public QQuickFramebufferObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool ready READ ready NOTIFY readyChanged)
    Q_PROPERTY(bool paused READ paused WRITE setPaused NOTIFY pausedChanged)
    Q_PROPERTY(double position READ position NOTIFY positionChanged)
    Q_PROPERTY(double duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(double volume READ volume WRITE setVolume NOTIFY volumeChanged)
    Q_PROPERTY(bool muted READ muted WRITE setMuted NOTIFY mutedChanged)
    Q_PROPERTY(double speed READ speed WRITE setSpeed NOTIFY speedChanged)
    Q_PROPERTY(bool loop READ loop WRITE setLoop NOTIFY loopChanged)
    Q_PROPERTY(bool seeking READ seeking NOTIFY seekingChanged)
    Q_PROPERTY(bool buffering READ buffering NOTIFY bufferingChanged)
    Q_PROPERTY(bool eofReached READ eofReached NOTIFY eofReachedChanged)
    Q_PROPERTY(bool idle READ idle NOTIFY idleChanged)
    Q_PROPERTY(bool fileLoaded READ fileLoaded NOTIFY fileLoadedChanged)
    Q_PROPERTY(QString path READ path NOTIFY pathChanged)
    Q_PROPERTY(QString mediaTitle READ mediaTitle NOTIFY mediaTitleChanged)
    Q_PROPERTY(QVariantList chapters READ chapters NOTIFY chaptersChanged)
    Q_PROPERTY(int chapter READ chapter NOTIFY chapterChanged)
    Q_PROPERTY(QVariantList tracks READ tracks NOTIFY tracksChanged)
    Q_PROPERTY(QVariantMap videoParams READ videoParams NOTIFY videoParamsChanged)
    Q_PROPERTY(QVariantMap metadata READ metadata NOTIFY metadataChanged)
    Q_PROPERTY(double cacheTime READ cacheTime NOTIFY cacheTimeChanged)
    Q_PROPERTY(QString hwdec READ hwdec NOTIFY hwdecChanged)
    Q_PROPERTY(double fps READ fps NOTIFY fpsChanged)
    Q_PROPERTY(QString audioFilter READ audioFilter WRITE setAudioFilter NOTIFY audioFilterChanged)

public:
    explicit MpvObject(QQuickItem *parent = nullptr);
    ~MpvObject() override;

    Renderer *createRenderer() const override;

    // Options applied to every new mpv instance before initialization.
    static void setDefaultOptions(const QVariantMap &options);

    bool ready() const { return m_ready; }
    bool paused() const { return m_paused; }
    double position() const { return m_position; }
    double duration() const { return m_duration; }
    double volume() const { return m_volume; }
    bool muted() const { return m_muted; }
    double speed() const { return m_speed; }
    bool loop() const { return m_loop; }
    bool seeking() const { return m_seeking; }
    bool buffering() const { return m_buffering; }
    bool eofReached() const { return m_eofReached; }
    bool idle() const { return m_idle; }
    bool fileLoaded() const { return m_fileLoaded; }
    QString path() const { return m_path; }
    QString mediaTitle() const { return m_mediaTitle; }
    QVariantList chapters() const { return m_chapters; }
    int chapter() const { return m_chapter; }
    QVariantList tracks() const { return m_tracks; }
    QVariantMap videoParams() const { return m_videoParams; }
    QVariantMap metadata() const { return m_metadata; }
    double cacheTime() const { return m_cacheTime; }
    QString hwdec() const { return m_hwdec; }
    double fps() const { return m_fps; }
    QString audioFilter() const { return m_audioFilter; }

    void setPaused(bool paused);
    void setVolume(double volume);
    void setMuted(bool muted);
    void setSpeed(double speed);
    void setLoop(bool loop);
    void setAudioFilter(const QString &filter);

    // Starts playback of a file. `start` is in seconds (<= 0 means beginning).
    Q_INVOKABLE void loadFile(const QString &path, double start = 0, bool paused = false);
    Q_INVOKABLE void stop();
    // Runs an mpv command asynchronously, e.g. ["seek", 10, "relative"].
    Q_INVOKABLE void command(const QVariantList &args);
    Q_INVOKABLE QVariant commandSync(const QVariantList &args);
    Q_INVOKABLE QVariant getProperty(const QString &name) const;
    Q_INVOKABLE void setOption(const QString &name, const QVariant &value);
    Q_INVOKABLE void seekTo(double seconds, bool exact = true);
    Q_INVOKABLE void seekBy(double seconds, bool exact = true);
    // Fast keyframe seeking for progress-bar dragging. Requests are coalesced so
    // that at most one seek is in flight; the newest target always wins.
    Q_INVOKABLE void scrub(double seconds);
    Q_INVOKABLE void frameStep(bool backwards);
    Q_INVOKABLE void selectTrack(const QString &type, const QVariant &id);
    Q_INVOKABLE void addSubtitle(const QString &path);
    Q_INVOKABLE void screenshot();

signals:
    void readyChanged();
    void pausedChanged();
    void positionChanged();
    void durationChanged();
    void volumeChanged();
    void mutedChanged();
    void speedChanged();
    void loopChanged();
    void seekingChanged();
    void bufferingChanged();
    void eofReachedChanged();
    void idleChanged();
    void fileLoadedChanged();
    void pathChanged();
    void mediaTitleChanged();
    void chaptersChanged();
    void chapterChanged();
    void tracksChanged();
    void videoParamsChanged();
    void metadataChanged();
    void cacheTimeChanged();
    void hwdecChanged();
    void fpsChanged();
    void audioFilterChanged();

    void fileStarted();
    void fileReady();
    void fileEnded(const QString &reason, const QString &error);
    void playbackRestarted();

private slots:
    void onMpvEvents();
    void onRenderContextReady();

private:
    friend struct MpvCore;
    friend class MpvRenderer;
    void handlePropertyChange(uint64_t id, void *data, int format);
    void issueScrub();

    std::shared_ptr<MpvCore> m_core;

    bool m_ready = false;
    bool m_paused = false;
    double m_position = 0;
    double m_duration = 0;
    double m_volume = 100;
    bool m_muted = false;
    double m_speed = 1;
    bool m_loop = false;
    bool m_seeking = false;
    bool m_buffering = false;
    bool m_eofReached = false;
    bool m_idle = true;
    bool m_fileLoaded = false;
    QString m_path;
    QString m_mediaTitle;
    QVariantList m_chapters;
    int m_chapter = -1;
    QVariantList m_tracks;
    QVariantMap m_videoParams;
    QVariantMap m_metadata;
    double m_cacheTime = 0;
    QString m_hwdec;
    double m_fps = 0;
    QString m_audioFilter;

    bool m_scrubInFlight = false;
    bool m_scrubPending = false;
    double m_scrubTarget = 0;
    QElapsedTimer m_scrubTimer;
};
