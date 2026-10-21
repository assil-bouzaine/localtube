#pragma once

#include <QAbstractListModel>
#include <QHash>
#include <QMutex>
#include <QSet>
#include <QThread>
#include <QTimer>
#include <QWaitCondition>
#include <QtQml/qqmlregistration.h>

#include <deque>

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

public:
    enum Role {
        PathRole = Qt::UserRole + 1,
        TitleRole,
        DurationRole,
        PosterRole,
        ProgressRole,
        CurrentRole,
    };

    explicit PlaylistModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const { return static_cast<int>(m_paths.size()); }
    int currentIndex() const { return m_current; }
    void setCurrentIndex(int index);
    QString title() const { return m_title; }

    // Builds the playlist from files and/or folders. A single file pulls in its
    // whole folder. Returns the index that should start playing, or -1.
    Q_INVOKABLE int open(const QStringList &paths);
    Q_INVOKABLE QString pathAt(int index) const;
    Q_INVOKABLE QString titleAt(int index) const;
    Q_INVOKABLE int indexOf(const QString &path) const;

signals:
    void countChanged();
    void currentIndexChanged();
    void titleChanged();

private:
    void refreshPath(const QString &path, const QList<int> &roles);

    QStringList m_paths;
    int m_current = -1;
    QString m_title;
};
