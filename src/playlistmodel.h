#pragma once

#include <QAbstractListModel>
#include <QHash>
#include <QMutex>
#include <QSet>
#include <QSortFilterProxyModel>
#include <QThread>
#include <QTimer>
#include <QWaitCondition>
#include <QtQml/qqmlregistration.h>

#include <deque>
#include <atomic>
#include <memory>

class QQmlEngine;
class QJSEngine;

class MediaInfoWorker;

// Durations and poster images for files in the playlist and on the home
// screen. Posters prefer the YouTube thumbnail saved by yt-dlp (side-car image
// or embedded cover art) and fall back to a representative video frame.
class MediaInfo : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(int revision READ revision NOTIFY revisionChanged)

public:
    static MediaInfo *instance();
    static MediaInfo *create(QQmlEngine *, QJSEngine *);
    ~MediaInfo() override;

    int revision() const { return m_revision; }
    // Both return immediately and queue background work when not cached yet.
    Q_INVOKABLE QString poster(const QString &path);
    Q_INVOKABLE double duration(const QString &path);
    Q_INVOKABLE static QString displayTitle(const QString &path);
    Q_INVOKABLE static bool isMediaFile(const QString &path);
    static QStringList mediaFilters();

signals:
    void revisionChanged();
    void infoReady(const QString &path);

private:
    explicit MediaInfo(QObject *parent = nullptr);
    struct Info {
        double duration = 0;
        QString poster;
        bool done = false;
        qint64 used = 0;
    };
    const Info *lookup(const QString &path);
    void onReady(const QString &path, const QString &key, double duration, const QString &poster);
    void loadIndex();
    void saveIndex();

    QHash<QString, Info> m_byKey;
    QHash<QString, QString> m_keyForPath;
    QSet<QString> m_queued;
    int m_revision = 0;
    QTimer m_saveTimer;
    MediaInfoWorker *m_worker = nullptr;
};

class MediaInfoWorker : public QThread
{
    Q_OBJECT
public:
    void enqueue(const QString &path, const QString &key);
    void stop();

signals:
    void ready(const QString &path, const QString &key, double duration, const QString &poster);

protected:
    void run() override;

private:
    QMutex m_mutex;
    QWaitCondition m_wake;
    std::deque<QPair<QString, QString>> m_queue;
    bool m_quit = false;
};

// The "Up next" list: every video in the opened file's folder, naturally sorted.
class PlaylistModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(int currentIndex READ currentIndex WRITE setCurrentIndex NOTIFY currentIndexChanged)
    Q_PROPERTY(QString title READ title NOTIFY titleChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)

public:
    enum Role {
        PathRole = Qt::UserRole + 1,
        TitleRole,
        DurationRole,
        PosterRole,
        ProgressRole,
        CurrentRole,
        SourceIndexRole,
    };

    explicit PlaylistModel(QObject *parent = nullptr);
    ~PlaylistModel() override;

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const { return static_cast<int>(m_paths.size()); }
    int currentIndex() const { return m_current; }
    void setCurrentIndex(int index);
    QString title() const { return m_title; }
    bool busy() const { return m_busy; }

    // Builds the playlist from files and/or folders. A single file pulls in its
    // whole folder. Scans in the background; opened() selects the starting row.
    Q_INVOKABLE void open(const QStringList &paths);
    Q_INVOKABLE QString pathAt(int index) const;
    Q_INVOKABLE QString titleAt(int index) const;
    Q_INVOKABLE int indexOf(const QString &path) const;

signals:
    void countChanged();
    void currentIndexChanged();
    void titleChanged();
    void busyChanged();
    void opened(int index);
    void openFailed(const QString &error);

private:
    void refreshPath(const QString &path, const QList<int> &roles);

    QStringList m_paths;
    int m_current = -1;
    QString m_title;
    bool m_busy = false;
    std::shared_ptr<std::atomic<quint64>> m_scanGeneration = std::make_shared<std::atomic<quint64>>(0);
};

// Search changes the displayed rows without changing playback order.
class PlaylistFilter : public QSortFilterProxyModel
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(PlaylistModel *playlist READ playlist WRITE setPlaylist NOTIFY playlistChanged)
    Q_PROPERTY(QString query READ query WRITE setQuery NOTIFY queryChanged)
public:
    explicit PlaylistFilter(QObject *parent = nullptr);
    PlaylistModel *playlist() const { return qobject_cast<PlaylistModel *>(sourceModel()); }
    void setPlaylist(PlaylistModel *playlist);
    QString query() const { return m_query; }
    void setQuery(const QString &query);
    Q_INVOKABLE int filteredIndex(int sourceRow) const;
signals:
    void playlistChanged();
    void queryChanged();
private:
    QString m_query;
};
