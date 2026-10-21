#pragma once

#include <QDBusAbstractAdaptor>
#include <QDBusObjectPath>
#include <QObject>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

// MPRIS2 integration so media keys, playerctl and desktop widgets can control
// the player. QML binds the state properties and handles the request signals.
class Mpris : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool playing MEMBER m_playing WRITE setPlaying NOTIFY stateChanged)
    Q_PROPERTY(bool active MEMBER m_active WRITE setActive NOTIFY stateChanged)
    Q_PROPERTY(QString title MEMBER m_title WRITE setTitle NOTIFY metadataChanged)
    Q_PROPERTY(QString artist MEMBER m_artist WRITE setArtist NOTIFY metadataChanged)
    Q_PROPERTY(QString artUrl MEMBER m_artUrl WRITE setArtUrl NOTIFY metadataChanged)
    Q_PROPERTY(QString path MEMBER m_path WRITE setPath NOTIFY metadataChanged)
    Q_PROPERTY(double duration MEMBER m_duration WRITE setDuration NOTIFY metadataChanged)
    Q_PROPERTY(double position MEMBER m_position NOTIFY positionUpdated)
    Q_PROPERTY(double volume MEMBER m_volume WRITE setVolume NOTIFY stateChanged)
    Q_PROPERTY(bool canGoNext MEMBER m_canGoNext WRITE setCanGoNext NOTIFY stateChanged)
    Q_PROPERTY(bool canGoPrevious MEMBER m_canGoPrevious WRITE setCanGoPrevious NOTIFY stateChanged)

public:
    explicit Mpris(QObject *parent = nullptr);
    ~Mpris() override;

    void setPlaying(bool v);
    void setActive(bool v);
    void setTitle(const QString &v);
    void setArtist(const QString &v);
    void setArtUrl(const QString &v);
    void setPath(const QString &v);
    void setDuration(double v);
    void setVolume(double v);
    void setCanGoNext(bool v);
    void setCanGoPrevious(bool v);
    // Called by QML on every position change; tells clients about jumps.
    Q_INVOKABLE void updatePosition(double seconds, bool seeked);

    // Used by the D-Bus adaptors.
    QString playbackStatus() const;
    QVariantMap metadataMap() const;
    qlonglong positionUs() const { return static_cast<qlonglong>(m_position * 1e6); }
    double volumeValue() const { return m_volume; }
    bool canGoNext() const { return m_canGoNext; }
    bool canGoPrevious() const { return m_canGoPrevious; }
    bool active() const { return m_active; }

signals:
    void stateChanged();
    void metadataChanged();
    void positionUpdated();
    void seeked(qlonglong positionUs);

    void raiseRequested();
    void quitRequested();
    void playPauseRequested();
    void playRequested();
    void pauseRequested();
    void stopRequested();
    void nextRequested();
    void previousRequested();
    void seekRequested(double offsetSeconds);
    void setPositionRequested(double seconds);
    void volumeRequested(double volume);

private:
    void propertiesChanged(const QVariantMap &changed);

    bool m_registered = false;
    bool m_playing = false;
    bool m_active = false;
    QString m_title;
    QString m_artist;
    QString m_artUrl;
    QString m_path;
    double m_duration = 0;
    double m_position = 0;
    double m_volume = 1;
    bool m_canGoNext = false;
    bool m_canGoPrevious = false;
};

class MprisRootAdaptor : public QDBusAbstractAdaptor
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.mpris.MediaPlayer2")
    Q_PROPERTY(bool CanQuit READ canQuit CONSTANT)
    Q_PROPERTY(bool CanRaise READ canRaise CONSTANT)
    Q_PROPERTY(bool HasTrackList READ hasTrackList CONSTANT)
    Q_PROPERTY(QString Identity READ identity CONSTANT)
    Q_PROPERTY(QString DesktopEntry READ desktopEntry CONSTANT)
    Q_PROPERTY(QStringList SupportedUriSchemes READ uriSchemes CONSTANT)
    Q_PROPERTY(QStringList SupportedMimeTypes READ mimeTypes CONSTANT)

public:
    explicit MprisRootAdaptor(Mpris *parent);
    bool canQuit() const { return true; }
    bool canRaise() const { return true; }
    bool hasTrackList() const { return false; }
    QString identity() const { return QStringLiteral("LocalTube"); }
    QString desktopEntry() const { return QStringLiteral("localtube"); }
    QStringList uriSchemes() const { return {QStringLiteral("file")}; }
    QStringList mimeTypes() const { return {}; }

public slots:
    void Raise();
    void Quit();

private:
    Mpris *m_mpris;
};

class MprisPlayerAdaptor : public QDBusAbstractAdaptor
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.mpris.MediaPlayer2.Player")
    Q_PROPERTY(QString PlaybackStatus READ playbackStatus)
    Q_PROPERTY(QVariantMap Metadata READ metadata)
    Q_PROPERTY(qlonglong Position READ position)
    Q_PROPERTY(double Volume READ volume WRITE setVolume)
    Q_PROPERTY(double Rate READ rate)
    Q_PROPERTY(double MinimumRate READ rate)
    Q_PROPERTY(double MaximumRate READ rate)
    Q_PROPERTY(bool CanGoNext READ canGoNext)
    Q_PROPERTY(bool CanGoPrevious READ canGoPrevious)
    Q_PROPERTY(bool CanPlay READ canControl)
    Q_PROPERTY(bool CanPause READ canControl)
    Q_PROPERTY(bool CanSeek READ canControl)
    Q_PROPERTY(bool CanControl READ alwaysTrue)

public:
    explicit MprisPlayerAdaptor(Mpris *parent);
    QString playbackStatus() const { return m_mpris->playbackStatus(); }
    QVariantMap metadata() const { return m_mpris->metadataMap(); }
    qlonglong position() const { return m_mpris->positionUs(); }
    double volume() const { return m_mpris->volumeValue(); }
    void setVolume(double v) { emit m_mpris->volumeRequested(v); }
    double rate() const { return 1.0; }
    bool canGoNext() const { return m_mpris->canGoNext(); }
    bool canGoPrevious() const { return m_mpris->canGoPrevious(); }
    bool canControl() const { return m_mpris->active(); }
    bool alwaysTrue() const { return true; }

public slots:
    void PlayPause() { emit m_mpris->playPauseRequested(); }
    void Play() { emit m_mpris->playRequested(); }
    void Pause() { emit m_mpris->pauseRequested(); }
    void Stop() { emit m_mpris->stopRequested(); }
    void Next() { emit m_mpris->nextRequested(); }
    void Previous() { emit m_mpris->previousRequested(); }
    void Seek(qlonglong offsetUs) { emit m_mpris->seekRequested(offsetUs / 1e6); }
    void SetPosition(const QDBusObjectPath &, qlonglong positionUs) { emit m_mpris->setPositionRequested(positionUs / 1e6); }
    void OpenUri(const QString &) {}

signals:
    void Seeked(qlonglong Position);

private:
    Mpris *m_mpris;
};
