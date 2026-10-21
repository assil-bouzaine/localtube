#include "mpris.h"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QUrl>

namespace {
const QString kObjectPath = QStringLiteral("/org/mpris/MediaPlayer2");
const QString kPlayerInterface = QStringLiteral("org.mpris.MediaPlayer2.Player");
}

Mpris::Mpris(QObject *parent)
    : QObject(parent)
{
    new MprisRootAdaptor(this);
    auto *player = new MprisPlayerAdaptor(this);
    connect(this, &Mpris::seeked, player, &MprisPlayerAdaptor::Seeked);

    QDBusConnection bus = QDBusConnection::sessionBus();
    if (bus.registerObject(kObjectPath, this)) {
        const QString service = QStringLiteral("org.mpris.MediaPlayer2.localtube.instance%1").arg(QCoreApplication::applicationPid());
        m_registered = bus.registerService(service);
    }
}

Mpris::~Mpris()
{
    if (m_registered)
        QDBusConnection::sessionBus().unregisterService(QStringLiteral("org.mpris.MediaPlayer2.localtube.instance%1").arg(QCoreApplication::applicationPid()));
}

QString Mpris::playbackStatus() const
{
    if (!m_active)
        return QStringLiteral("Stopped");
    return m_playing ? QStringLiteral("Playing") : QStringLiteral("Paused");
}

QVariantMap Mpris::metadataMap() const
{
    if (!m_active)
        return {{QStringLiteral("mpris:trackid"), QVariant::fromValue(QDBusObjectPath(QStringLiteral("/org/mpris/MediaPlayer2/TrackList/NoTrack")))}};
    const QByteArray id = QCryptographicHash::hash(m_path.toUtf8(), QCryptographicHash::Md5).toHex();
    QVariantMap map {
        {QStringLiteral("mpris:trackid"), QVariant::fromValue(QDBusObjectPath(QStringLiteral("/org/localtube/track/") + QString::fromLatin1(id)))},
        {QStringLiteral("mpris:length"), static_cast<qlonglong>(m_duration * 1e6)},
        {QStringLiteral("xesam:title"), m_title},
        {QStringLiteral("xesam:url"), QUrl::fromLocalFile(m_path).toString()},
    };
    if (!m_artist.isEmpty())
        map.insert(QStringLiteral("xesam:artist"), QStringList {m_artist});
    if (!m_artUrl.isEmpty())
        map.insert(QStringLiteral("mpris:artUrl"), m_artUrl);
    return map;
}

void Mpris::propertiesChanged(const QVariantMap &changed)
{
    if (!m_registered)
        return;
    QDBusMessage signal = QDBusMessage::createSignal(kObjectPath, QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("PropertiesChanged"));
    signal << kPlayerInterface << changed << QStringList();
    QDBusConnection::sessionBus().send(signal);
}

void Mpris::setPlaying(bool v)
{
    if (m_playing == v)
        return;
    m_playing = v;
    emit stateChanged();
    propertiesChanged({{QStringLiteral("PlaybackStatus"), playbackStatus()}});
}

void Mpris::setActive(bool v)
{
    if (m_active == v)
        return;
    m_active = v;
    emit stateChanged();
    propertiesChanged({{QStringLiteral("PlaybackStatus"), playbackStatus()},
                       {QStringLiteral("Metadata"), metadataMap()},
                       {QStringLiteral("CanPlay"), v},
                       {QStringLiteral("CanPause"), v},
                       {QStringLiteral("CanSeek"), v}});
}

#define MPRIS_METADATA_SETTER(name, member, type) \
    void Mpris::name(type v) \
    { \
        if (member == v) \
            return; \
        member = v; \
        emit metadataChanged(); \
        propertiesChanged({{QStringLiteral("Metadata"), metadataMap()}}); \
    }

MPRIS_METADATA_SETTER(setTitle, m_title, const QString &)
MPRIS_METADATA_SETTER(setArtist, m_artist, const QString &)
MPRIS_METADATA_SETTER(setArtUrl, m_artUrl, const QString &)
MPRIS_METADATA_SETTER(setPath, m_path, const QString &)
MPRIS_METADATA_SETTER(setDuration, m_duration, double)

void Mpris::setVolume(double v)
{
    if (qFuzzyCompare(m_volume, v))
        return;
    m_volume = v;
    emit stateChanged();
    propertiesChanged({{QStringLiteral("Volume"), v}});
}

void Mpris::setCanGoNext(bool v)
{
    if (m_canGoNext == v)
        return;
    m_canGoNext = v;
    emit stateChanged();
    propertiesChanged({{QStringLiteral("CanGoNext"), v}});
}

void Mpris::setCanGoPrevious(bool v)
{
    if (m_canGoPrevious == v)
        return;
    m_canGoPrevious = v;
    emit stateChanged();
    propertiesChanged({{QStringLiteral("CanGoPrevious"), v}});
}

void Mpris::updatePosition(double seconds, bool seeked)
{
    m_position = seconds;
    emit positionUpdated();
    if (seeked)
        emit this->seeked(positionUs());
}

MprisRootAdaptor::MprisRootAdaptor(Mpris *parent)
    : QDBusAbstractAdaptor(parent)
    , m_mpris(parent)
{
}

void MprisRootAdaptor::Raise()
{
    emit m_mpris->raiseRequested();
}

void MprisRootAdaptor::Quit()
{
    emit m_mpris->quitRequested();
}

MprisPlayerAdaptor::MprisPlayerAdaptor(Mpris *parent)
    : QDBusAbstractAdaptor(parent)
    , m_mpris(parent)
{
    setAutoRelaySignals(true);
}
