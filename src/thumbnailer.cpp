#include "thumbnailer.h"

#include "framegrabber.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QStandardPaths>
#include <QSaveFile>
#include <QUrl>

#include <algorithm>
#include <cmath>
#include <memory>

namespace {
constexpr int kThumbWidth = 320;
constexpr int kTargetSlots = 240;
}

QString Thumbnailer::cacheRoot()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation) + QStringLiteral("/localtube");
}

Thumbnailer::Thumbnailer(QObject *parent)
    : QObject(parent)
    , m_worker(new ThumbnailWorker)
{
    connect(m_worker, &ThumbnailWorker::slotReady, this, &Thumbnailer::onSlotReady, Qt::QueuedConnection);
    m_worker->start(QThread::IdlePriority);

    // Give playback start-up a head start before filling in the background.
    m_prefillDelay.setSingleShot(true);
    m_prefillDelay.setInterval(2500);
    connect(&m_prefillDelay, &QTimer::timeout, this, [this] { m_worker->allowPrefill(); });
    m_touchTimer.setInterval(30000);
    connect(&m_touchTimer, &QTimer::timeout, this, [this] {
        QFile stamp(m_cacheDir + QStringLiteral("/.used"));
        if (stamp.open(QIODevice::WriteOnly | QIODevice::Truncate))
            stamp.write(QByteArray::number(QDateTime::currentSecsSinceEpoch()));
    });
}

Thumbnailer::~Thumbnailer()
{
    m_worker->stop();
    m_worker->wait();
    delete m_worker;
}

void Thumbnailer::setSource(const QString &source)
{
    if (m_source == source)
        return;
    m_source = source;
    m_duration = 0;
    emit sourceChanged();
    emit durationChanged();
    restart();
}

void Thumbnailer::setDuration(double duration)
{
    // Some containers refine their duration during playback; only a real
    // change invalidates the slot grid.
    if (std::fabs(duration - m_duration) < 1.0 && m_slotCount > 0)
        return;
    m_duration = duration;
    emit durationChanged();
    restart();
}

void Thumbnailer::restart()
{
    ++m_generation;
    m_ready.clear();
    m_slotCount = 0;
    m_prefillDelay.stop();
    m_touchTimer.stop();
    m_cacheDir.clear();

    const QFileInfo info(m_source);
    if (m_source.isEmpty() || m_duration <= 0 || !info.isFile()) {
        m_worker->setJob(ThumbnailWorker::Job {m_generation}, {});
        ++m_revision;
        emit revisionChanged();
        return;
    }

    m_slotLength = std::clamp(m_duration / kTargetSlots, 1.0, 30.0);
    m_slotCount = std::max(1, static_cast<int>(std::ceil(m_duration / m_slotLength)));

    const QString identity = info.canonicalFilePath() + QLatin1Char('|') + QString::number(info.size()) + QLatin1Char('|')
                             + QString::number(info.lastModified().toMSecsSinceEpoch()) + QLatin1Char('|')
                             + QString::number(m_slotLength, 'f', 3) + QStringLiteral("|v1");
    const QString key = QString::fromLatin1(QCryptographicHash::hash(identity.toUtf8(), QCryptographicHash::Sha1).toHex());
    const QString dir = cacheRoot() + QStringLiteral("/thumbs/") + key;
    QDir().mkpath(dir);
    m_cacheDir = dir;
    m_touchTimer.start();

    // Marks the folder as recently used for cache cleanup.
    QFile stamp(dir + QStringLiteral("/.used"));
    if (stamp.open(QIODevice::WriteOnly | QIODevice::Truncate))
        stamp.write(QByteArray::number(QDateTime::currentSecsSinceEpoch()));

    const QStringList files = QDir(dir).entryList({QStringLiteral("*.jpg")}, QDir::Files);
    for (const QString &name : files) {
        bool ok = false;
        const int slot = QStringView(name).chopped(4).toInt(&ok);
        if (ok && slot >= 0 && slot < m_slotCount)
            m_ready.insert(slot, dir + QLatin1Char('/') + name);
    }

    ThumbnailWorker::Job job;
    job.generation = m_generation;
    job.path = m_source;
    job.dir = dir;
    job.slotLength = m_slotLength;
    job.slotCount = m_slotCount;
    job.duration = m_duration;
    job.width = kThumbWidth;
    m_worker->setJob(job, m_ready);
    m_prefillDelay.start();

    ++m_revision;
    emit revisionChanged();
}

QString Thumbnailer::thumbnail(double seconds)
{
    if (m_slotCount <= 0)
        return {};
    const int slot = std::clamp(static_cast<int>(seconds / m_slotLength), 0, m_slotCount - 1);
    if (auto it = m_ready.constFind(slot); it != m_ready.cend())
        return QUrl::fromLocalFile(*it).toString();

    m_worker->request(slot);
    for (int d = 1; d < m_slotCount; ++d) {
        if (auto it = m_ready.constFind(slot - d); it != m_ready.cend())
            return QUrl::fromLocalFile(*it).toString();
        if (auto it = m_ready.constFind(slot + d); it != m_ready.cend())
            return QUrl::fromLocalFile(*it).toString();
    }
    return {};
}

void Thumbnailer::onSlotReady(quint64 generation, int slot, const QString &file)
{
    if (generation != m_generation || file.isEmpty())
        return;
    m_ready.insert(slot, file);
    ++m_revision;
    emit revisionChanged();
}

void ThumbnailWorker::setJob(const Job &job, const QHash<int, QString> &existing)
{
    QMutexLocker lock(&m_mutex);
    m_job = job;
    m_generation.store(job.generation);
    m_demand.clear();
    m_prefill = false;
    m_done.assign(static_cast<size_t>(std::max(0, job.slotCount)), 0);
    m_attempts.assign(m_done.size(), 0);
    for (auto it = existing.cbegin(); it != existing.cend(); ++it)
        m_done[static_cast<size_t>(it.key())] = 1;

    // Coarse-to-fine order: every 2^n-th slot first, so early previews are
    // spread across the whole timeline.
    m_order.clear();
    m_orderPos = 0;
    std::vector<char> added(m_done.size(), 0);
    int step = 1;
    while (step * 2 < job.slotCount)
        step *= 2;
    for (; step >= 1; step /= 2) {
        for (int i = 0; i < job.slotCount; i += step) {
            if (!added[static_cast<size_t>(i)]) {
                added[static_cast<size_t>(i)] = 1;
                m_order.push_back(i);
            }
        }
    }
    m_wake.wakeAll();
}

void ThumbnailWorker::request(int slot)
{
    QMutexLocker lock(&m_mutex);
    if (slot < 0 || slot >= m_job.slotCount || m_done[static_cast<size_t>(slot)])
        return;
    if (!m_demand.empty() && m_demand.back() == slot)
        return;
    std::erase(m_demand, slot);
    m_demand.push_back(slot);
    while (m_demand.size() > 3)
        m_demand.pop_front();
    m_wake.wakeAll();
}

void ThumbnailWorker::allowPrefill()
{
    QMutexLocker lock(&m_mutex);
    m_prefill = true;
    m_wake.wakeAll();
}

void ThumbnailWorker::stop()
{
    QMutexLocker lock(&m_mutex);
    m_quit = true;
    m_stopping.store(true);
    m_wake.wakeAll();
}

int ThumbnailWorker::takeSlot(bool *demanded)
{
    *demanded = true;
    while (!m_demand.empty()) {
        const int slot = m_demand.back();
        m_demand.pop_back();
        if (!m_done[static_cast<size_t>(slot)])
            return slot;
    }
    *demanded = false;
    if (m_prefill) {
        while (m_orderPos < m_order.size()) {
            const int slot = m_order[m_orderPos++];
            if (!m_done[static_cast<size_t>(slot)])
                return slot;
        }
    }
    return -1;
}

void ThumbnailWorker::run()
{
    std::unique_ptr<FrameGrabber> grabber;
    quint64 openGeneration = 0;
    QHash<qint64, QString> byKeyframe;

    while (true) {
        Job job;
        int slot = -1;
        bool demanded = false;
        {
            QMutexLocker lock(&m_mutex);
            while (!m_quit && (slot = takeSlot(&demanded)) < 0)
                m_wake.wait(&m_mutex);
            if (m_quit)
                break;
            job = m_job;
            m_done[static_cast<size_t>(slot)] = 1;
            ++m_attempts[static_cast<size_t>(slot)];
        }
        // Someone is hovering over this spot: compete normally for the CPU.
        // Background filling stays at idle priority.
        setPriority(demanded ? QThread::NormalPriority : QThread::IdlePriority);

        if (!grabber || openGeneration != job.generation) {
            grabber = std::make_unique<FrameGrabber>(job.path, [this, generation = job.generation] {
                return m_stopping.load() || m_generation.load() != generation;
            });
            openGeneration = job.generation;
            byKeyframe.clear();
        }

        QString file;
        if (grabber->isOpen()) {
            const double t = std::min((slot + 0.5) * job.slotLength, std::max(0.0, job.duration - 0.5));
            const QString target = job.dir + QStringLiteral("/%1.jpg").arg(slot);
            // Neighbouring slots often share a key frame; link instead of decoding again.
            const double key = grabber->keyframeBefore(t);
            const qint64 keyMs = key >= 0 ? qRound64(key * 1000) : -1;
            if (const auto it = byKeyframe.constFind(keyMs); keyMs >= 0 && it != byKeyframe.cend()) {
                QFile::remove(target);
                if (QFile::link(QFileInfo(*it).fileName(), target))
                    file = target;
            }
            if (file.isEmpty()) {
                const QImage image = grabber->grab(t, job.width);
                QSaveFile output(target);
                if (!image.isNull() && output.open(QIODevice::WriteOnly) && image.save(&output, "JPG", 82) && output.commit()) {
                    file = target;
                    if (keyMs >= 0)
                        byKeyframe.insert(keyMs, target);
                }
            }
        }
        if (file.isEmpty()) {
            QMutexLocker lock(&m_mutex);
            if (m_job.generation == job.generation && m_attempts[static_cast<size_t>(slot)] < 3)
                m_done[static_cast<size_t>(slot)] = 0;
            // A failed open must be retried on the next demand, too.
            if (!grabber->isOpen())
                grabber.reset();
        }
        emit slotReady(job.generation, slot, file);
    }
}

void Thumbnailer::cleanupCache(int maxAgeDays, qint64 maxBytes)
{
    const QDir root(cacheRoot() + QStringLiteral("/thumbs"));
    const qint64 now = QDateTime::currentSecsSinceEpoch();
    const QStringList dirs = root.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &name : dirs) {
        QFile stamp(root.filePath(name) + QStringLiteral("/.used"));
        qint64 used = 0;
        if (stamp.open(QIODevice::ReadOnly))
            used = stamp.readAll().trimmed().toLongLong();
        if (now - used > qint64(maxAgeDays) * 86400)
            QDir(root.filePath(name)).removeRecursively();
    }
    // Posters used to grow forever. Evict old files as well as old preview folders.
    const QDir posters(cacheRoot() + QStringLiteral("/posters"));
    for (const QFileInfo &file : posters.entryInfoList({QStringLiteral("*.jpg")}, QDir::Files)) {
        if (now - file.lastModified().toSecsSinceEpoch() > qint64(maxAgeDays) * 86400)
            QFile::remove(file.absoluteFilePath());
    }
    struct CacheItem { QString path; qint64 bytes; qint64 used; bool directory; };
    QList<CacheItem> items;
    qint64 total = 0;
    for (const QFileInfo &dir : root.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot)) {
        qint64 bytes = 0;
        QDirIterator it(dir.absoluteFilePath(), QDir::Files | QDir::Hidden, QDirIterator::Subdirectories);
        while (it.hasNext()) { it.next(); bytes += it.fileInfo().size(); }
        QFile stamp(dir.absoluteFilePath() + QStringLiteral("/.used"));
        qint64 used = dir.lastModified().toSecsSinceEpoch();
        if (stamp.open(QIODevice::ReadOnly)) used = stamp.readAll().trimmed().toLongLong();
        items.append({dir.absoluteFilePath(), bytes, used, true});
        total += bytes;
    }
    for (const QFileInfo &file : posters.entryInfoList({QStringLiteral("*.jpg")}, QDir::Files)) {
        items.append({file.absoluteFilePath(), file.size(), file.lastModified().toSecsSinceEpoch(), false});
        total += file.size();
    }
    std::sort(items.begin(), items.end(), [](const auto &a, const auto &b) { return a.used < b.used; });
    for (const auto &item : items) {
        if (total <= maxBytes) break;
        // Avoid deleting files another running player has just opened or written.
        if (now - item.used < 60) continue;
        const bool removed = item.directory ? QDir(item.path).removeRecursively() : QFile::remove(item.path);
        if (removed) total -= item.bytes;
    }
}
