#include "playlistmodel.h"

#include "framegrabber.h"
#include "history.h"
#include "thumbnailer.h"

#include <QCollator>
#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFutureWatcher>
#include <QtConcurrentRun>
#include <QCoreApplication>
#include <QFile>
#include <QFileInfo>
#include <QJSEngine>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QRegularExpression>
#include <QSaveFile>
#include <QUrl>

#include <algorithm>
#include <cmath>

namespace {

const QStringList &mediaExtensions()
{
    static const QStringList extensions {
        // video
        QStringLiteral("mkv"), QStringLiteral("mp4"), QStringLiteral("m4v"), QStringLiteral("webm"), QStringLiteral("mov"),
        QStringLiteral("avi"), QStringLiteral("wmv"), QStringLiteral("flv"), QStringLiteral("mpg"), QStringLiteral("mpeg"),
        QStringLiteral("m2ts"), QStringLiteral("mts"), QStringLiteral("ts"), QStringLiteral("ogv"), QStringLiteral("3gp"),
        QStringLiteral("vob"), QStringLiteral("divx"), QStringLiteral("rmvb"), QStringLiteral("asf"), QStringLiteral("f4v"),
        // audio
        QStringLiteral("mp3"), QStringLiteral("m4a"), QStringLiteral("opus"), QStringLiteral("ogg"), QStringLiteral("flac"),
        QStringLiteral("wav"), QStringLiteral("aac"), QStringLiteral("mka"),
    };
    return extensions;
}

QString posterDir()
{
    return Thumbnailer::cacheRoot() + QStringLiteral("/posters");
}

QString keyFor(const QFileInfo &info)
{
    const QString identity = info.absoluteFilePath() + QLatin1Char('|') + QString::number(info.size()) + QLatin1Char('|')
                             + QString::number(info.lastModified().toMSecsSinceEpoch());
    return QString::fromLatin1(QCryptographicHash::hash(identity.toUtf8(), QCryptographicHash::Sha1).toHex());
}

// Picks a frame that is neither black nor flat, which makes a decent poster.
QImage representativeFrame(FrameGrabber &grabber, int width)
{
    QImage best;
    double bestScore = -1;
    for (const double at : {0.2, 0.4, 0.6, 0.1}) {
        const QImage image = grabber.grab(grabber.duration() * at, width);
        if (image.isNull())
            continue;
        double sum = 0, sumSq = 0;
        int n = 0;
        for (int y = 0; y < image.height(); y += 4) {
            const uchar *line = image.constScanLine(y);
            for (int x = 0; x < image.width(); x += 4) {
                const double l = 0.2126 * line[x * 3] + 0.7152 * line[x * 3 + 1] + 0.0722 * line[x * 3 + 2];
                sum += l;
                sumSq += l * l;
                ++n;
            }
        }
        const double mean = n ? sum / n : 0;
        const double stddev = n ? std::sqrt(std::max(0.0, sumSq / n - mean * mean)) : 0;
        const double score = stddev + 0.35 * std::min(mean, 140.0);
        if (score > bestScore) {
            bestScore = score;
            best = image;
        }
        if (mean > 45 && stddev > 40)
            break;
    }
    return best;
}

} // namespace

// ---------------------------------------------------------------- MediaInfo

MediaInfo *MediaInfo::instance()
{
    static MediaInfo *info = new MediaInfo(QCoreApplication::instance());
    return info;
}

MediaInfo *MediaInfo::create(QQmlEngine *, QJSEngine *)
{
    QJSEngine::setObjectOwnership(instance(), QJSEngine::CppOwnership);
    return instance();
}

MediaInfo::MediaInfo(QObject *parent)
    : QObject(parent)
    , m_worker(new MediaInfoWorker)
{
    loadIndex();
    connect(m_worker, &MediaInfoWorker::ready, this, &MediaInfo::onReady, Qt::QueuedConnection);
    m_worker->start(QThread::IdlePriority);
    m_saveTimer.setSingleShot(true);
    m_saveTimer.setInterval(3000);
    connect(&m_saveTimer, &QTimer::timeout, this, &MediaInfo::saveIndex);
    connect(QCoreApplication::instance(), &QCoreApplication::aboutToQuit, this, [this] {
        m_worker->stop();
        m_worker->wait();
        saveIndex();
    });
}

MediaInfo::~MediaInfo()
{
    m_worker->stop();
    m_worker->wait();
    delete m_worker;
    saveIndex();
}

QStringList MediaInfo::mediaFilters()
{
    QStringList filters;
    for (const QString &ext : mediaExtensions())
        filters << QStringLiteral("*.") + ext;
    return filters;
}

bool MediaInfo::isMediaFile(const QString &path)
{
    return mediaExtensions().contains(QFileInfo(path).suffix().toLower());
}

QString MediaInfo::displayTitle(const QString &path)
{
    // yt-dlp's default template is "Title [videoid].ext"; drop the id.
    static const QRegularExpression youtubeId(QStringLiteral("\\s*\\[[A-Za-z0-9_-]{11}\\]$"));
    QString name = QFileInfo(path).completeBaseName();
    name.remove(youtubeId);
    return name.isEmpty() ? QFileInfo(path).fileName() : name;
}

const MediaInfo::Info *MediaInfo::lookup(const QString &path)
{
    if (path.isEmpty())
        return nullptr;
    auto keyIt = m_keyForPath.constFind(path);
    if (keyIt == m_keyForPath.cend()) {
        const QFileInfo info(path);
        if (!info.isFile())
            return nullptr;
        keyIt = m_keyForPath.insert(path, keyFor(info));
    }
    const QString &key = *keyIt;
    auto it = m_byKey.find(key);
    if (it != m_byKey.end() && it->done && (it->poster.isEmpty() || QFile::exists(it->poster))) {
        it->used = QDateTime::currentSecsSinceEpoch();
        return &*it;
    }
    if (!m_queued.contains(key)) {
        m_queued.insert(key);
        m_worker->enqueue(path, key);
    }
    return it != m_byKey.end() ? &*it : nullptr;
}

QString MediaInfo::poster(const QString &path)
{
    const Info *info = lookup(path);
    return info && !info->poster.isEmpty() ? QUrl::fromLocalFile(info->poster).toString() : QString();
}

double MediaInfo::duration(const QString &path)
{
    const Info *info = lookup(path);
    return info ? info->duration : 0;
}

void MediaInfo::onReady(const QString &path, const QString &key, double duration, const QString &poster)
{
    m_queued.remove(key);
    m_byKey.insert(key, Info {duration, poster, true, QDateTime::currentSecsSinceEpoch()});
    ++m_revision;
    emit revisionChanged();
    emit infoReady(path);
    if (!m_saveTimer.isActive())
        m_saveTimer.start();
}

void MediaInfo::loadIndex()
{
    QFile file(posterDir() + QStringLiteral("/index.json"));
    if (!file.open(QIODevice::ReadOnly))
        return;
    const QJsonObject root = QJsonDocument::fromJson(file.readAll()).object();
    for (auto it = root.constBegin(); it != root.constEnd(); ++it) {
        const QJsonObject o = it.value().toObject();
        const QString poster = o.value(QStringLiteral("poster")).toString();
        if (!poster.isEmpty() && !QFile::exists(poster)) continue;
        m_byKey.insert(it.key(), Info {o.value(QStringLiteral("duration")).toDouble(), poster, true,
                                      o.value(QStringLiteral("used")).toInteger(QDateTime::currentSecsSinceEpoch())});
    }
}

void MediaInfo::saveIndex()
{
    const qint64 cutoff = QDateTime::currentSecsSinceEpoch() - 45LL * 86400;
    QList<QString> keys;
    for (auto it = m_byKey.begin(); it != m_byKey.end();) {
        if (it->used < cutoff || (!it->poster.isEmpty() && !QFile::exists(it->poster)))
            it = m_byKey.erase(it);
        else {
            keys << it.key();
            ++it;
        }
    }
    std::sort(keys.begin(), keys.end(), [this](const QString &a, const QString &b) { return m_byKey.value(a).used > m_byKey.value(b).used; });
    for (qsizetype i = 4000; i < keys.size(); ++i)
        m_byKey.remove(keys.at(i));
    QJsonObject root;
    for (auto it = m_byKey.cbegin(); it != m_byKey.cend(); ++it) {
        if (it->done)
            root.insert(it.key(), QJsonObject {{QStringLiteral("duration"), it->duration}, {QStringLiteral("poster"), it->poster},
                                              {QStringLiteral("used"), it->used}});
    }
    QDir().mkpath(posterDir());
    QSaveFile file(posterDir() + QStringLiteral("/index.json"));
    if (file.open(QIODevice::WriteOnly)) {
        file.write(QJsonDocument(root).toJson(QJsonDocument::Compact));
        file.commit();
    }
}

void MediaInfoWorker::enqueue(const QString &path, const QString &key)
{
    QMutexLocker lock(&m_mutex);
    m_queue.emplace_back(path, key);
    m_wake.wakeAll();
}

void MediaInfoWorker::stop()
{
    requestInterruption();
    QMutexLocker lock(&m_mutex);
    m_quit = true;
    m_wake.wakeAll();
}

void MediaInfoWorker::run()
{
    QDir().mkpath(posterDir());
    while (true) {
        QPair<QString, QString> job;
        {
            QMutexLocker lock(&m_mutex);
            while (!m_quit && m_queue.empty())
                m_wake.wait(&m_mutex);
            if (m_quit)
                return;
            job = m_queue.front();
            m_queue.pop_front();
        }
        const auto &[path, key] = job;
        constexpr int width = 480;

        FrameGrabber grabber(path, [this] { return isInterruptionRequested(); });
        QImage image;
        // 1. Thumbnail written next to the video by yt-dlp --write-thumbnail.
        const QFileInfo info(path);
        const QString base = info.absolutePath() + QLatin1Char('/') + info.completeBaseName();
        for (const char *ext : {".webp", ".jpg", ".jpeg", ".png"}) {
            if (QFile::exists(base + QLatin1String(ext)) && image.load(base + QLatin1String(ext)))
                break;
        }
        // 2. Cover art embedded by yt-dlp --embed-thumbnail.
        if (image.isNull())
            image = grabber.coverArt();
        if (!image.isNull() && image.width() > width)
            image = image.scaledToWidth(width, Qt::SmoothTransformation);
        // 3. A representative frame.
        if (image.isNull() && grabber.isOpen())
            image = representativeFrame(grabber, width);

        QString poster;
        if (!image.isNull()) {
            poster = posterDir() + QLatin1Char('/') + key + QStringLiteral(".jpg");
            QSaveFile output(poster);
            if (!output.open(QIODevice::WriteOnly) || !image.convertToFormat(QImage::Format_RGB888).save(&output, "JPG", 85) || !output.commit())
                poster.clear();
        }
        emit ready(path, key, grabber.duration(), poster);
    }
}

// ------------------------------------------------------------ PlaylistModel

PlaylistModel::PlaylistModel(QObject *parent)
    : QAbstractListModel(parent)
{
    connect(MediaInfo::instance(), &MediaInfo::infoReady, this, [this](const QString &path) {
        refreshPath(path, {DurationRole, PosterRole});
    });
    connect(History::instance(), &History::changed, this, [this](const QString &path) {
        refreshPath(path, {ProgressRole});
    });
}

int PlaylistModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : count();
}

QVariant PlaylistModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= count())
        return {};
    const QString &path = m_paths.at(index.row());
    switch (role) {
    case PathRole: return path;
    case TitleRole: return MediaInfo::displayTitle(path);
    case DurationRole: return MediaInfo::instance()->duration(path);
    case PosterRole: return MediaInfo::instance()->poster(path);
    case ProgressRole: return History::instance()->progress(path);
    case CurrentRole: return index.row() == m_current;
    case SourceIndexRole: return index.row();
    default: return {};
    }
}

QHash<int, QByteArray> PlaylistModel::roleNames() const
{
    return {
        {PathRole, "path"},
        {TitleRole, "title"},
        {DurationRole, "duration"},
        {PosterRole, "poster"},
        {ProgressRole, "progress"},
        {CurrentRole, "current"},
        {SourceIndexRole, "sourceIndex"},
    };
}

void PlaylistModel::setCurrentIndex(int index)
{
    if (index < -1 || index >= count() || index == m_current)
        return;
    const int old = m_current;
    m_current = index;
    if (old >= 0)
        emit dataChanged(this->index(old), this->index(old), {CurrentRole});
    if (index >= 0)
        emit dataChanged(this->index(index), this->index(index), {CurrentRole});
    emit currentIndexChanged();
}

PlaylistModel::~PlaylistModel()
{
    ++*m_scanGeneration;
}

void PlaylistModel::open(const QStringList &paths)
{
    const auto generation = m_scanGeneration;
    const quint64 request = ++*generation;
    if (!m_busy) {
        m_busy = true;
        emit busyChanged();
    }
    struct ScanResult {
        QStringList files;
        QString start;
        QString folder;
    };
    auto *watcher = new QFutureWatcher<ScanResult>(this);
    connect(watcher, &QFutureWatcher<ScanResult>::finished, this, [this, watcher, generation, request] {
        const auto result = watcher->result();
        watcher->deleteLater();
        if (generation->load() != request)
            return;
        m_busy = false;
        emit busyChanged();
        if (result.files.isEmpty()) {
            emit openFailed(tr("No readable media files were found."));
            return;
        }
        beginResetModel();
        m_paths = result.files;
        m_current = -1;
        endResetModel();
        emit countChanged();
        emit currentIndexChanged();
        m_title = QFileInfo(result.folder).fileName();
        emit titleChanged();
        const int index = result.start.isEmpty() ? 0 : static_cast<int>(m_paths.indexOf(result.start));
        setCurrentIndex(index);
        emit opened(index);
    });
    watcher->setFuture(QtConcurrent::run([paths, generation, request] {
    QStringList files;
    QString start;
    QString folder;

    const auto scan = [generation, request](const QString &dir) {
        QStringList entries;
        QDirIterator iterator(dir, MediaInfo::mediaFilters(), QDir::Files | QDir::Readable);
        while (iterator.hasNext()) {
            if (generation->load() != request)
                return QStringList {};
            iterator.next();
            entries << iterator.fileName();
        }
        QCollator collator;
        // The C locale does not implement numeric collation.
        if (collator.locale().language() == QLocale::C)
            collator.setLocale(QLocale(QLocale::English, QLocale::UnitedStates));
        collator.setNumericMode(true);
        collator.setCaseSensitivity(Qt::CaseInsensitive);
        std::sort(entries.begin(), entries.end(), collator);
        QStringList result;
        for (const QString &e : entries)
            result << QDir(dir).absoluteFilePath(e);
        return result;
    };

    if (paths.size() == 1) {
        const QFileInfo info(paths.first());
        if (info.isDir()) {
            folder = info.absoluteFilePath();
            files = scan(folder);
        } else {
            folder = info.absolutePath();
            start = info.absoluteFilePath();
            files = scan(folder);
            if (info.isFile() && info.isReadable() && !files.contains(start))
                files.prepend(start);
            if (!info.isFile() || !info.isReadable())
                files.clear();
        }
    } else {
        for (const QString &p : paths) {
            if (generation->load() != request)
                return ScanResult {};
            const QFileInfo info(p);
            if (info.isDir())
                files << scan(info.absoluteFilePath());
            else if (info.isFile() && info.isReadable())
                files << info.absoluteFilePath();
        }
        if (!files.isEmpty())
            folder = QFileInfo(files.first()).absolutePath();
    }

    files.removeDuplicates();
    return ScanResult {files, start, folder};
    }));
}

QString PlaylistModel::pathAt(int index) const
{
    return index >= 0 && index < count() ? m_paths.at(index) : QString();
}

QString PlaylistModel::titleAt(int index) const
{
    return index >= 0 && index < count() ? MediaInfo::displayTitle(m_paths.at(index)) : QString();
}

int PlaylistModel::indexOf(const QString &path) const
{
    return static_cast<int>(m_paths.indexOf(path));
}

void PlaylistModel::refreshPath(const QString &path, const QList<int> &roles)
{
    if (path.isEmpty() && !m_paths.isEmpty()) {
        emit dataChanged(index(0), index(count() - 1), roles);
        return;
    }
    const int row = static_cast<int>(m_paths.indexOf(path));
    if (row >= 0)
        emit dataChanged(index(row), index(row), roles);
}

PlaylistFilter::PlaylistFilter(QObject *parent)
    : QSortFilterProxyModel(parent)
{
    setFilterRole(PlaylistModel::TitleRole);
    setFilterCaseSensitivity(Qt::CaseInsensitive);
}

void PlaylistFilter::setPlaylist(PlaylistModel *playlist)
{
    if (sourceModel() == playlist) return;
    setSourceModel(playlist);
    emit playlistChanged();
}

void PlaylistFilter::setQuery(const QString &query)
{
    if (m_query == query) return;
    m_query = query;
    setFilterFixedString(query);
    emit queryChanged();
}

int PlaylistFilter::filteredIndex(int sourceRow) const
{
    return sourceModel() ? mapFromSource(sourceModel()->index(sourceRow, 0)).row() : -1;
}
