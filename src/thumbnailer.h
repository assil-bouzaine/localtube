#pragma once

#include <QHash>
#include <QMutex>
#include <QObject>
#include <QThread>
#include <QTimer>
#include <QWaitCondition>
#include <QtQml/qqmlregistration.h>

#include <deque>
#include <atomic>
#include <vector>

class ThumbnailWorker;

// Generates progress-bar hover previews ("storyboards") for the current file.
// The timeline is split into slots; slots under the mouse are generated first,
// the rest are filled in coarse-to-fine order in the background. Images are
// cached on disk, so reopening a file shows previews instantly.
class Thumbnailer : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString source READ source WRITE setSource NOTIFY sourceChanged)
    Q_PROPERTY(double duration READ duration WRITE setDuration NOTIFY durationChanged)
    Q_PROPERTY(int revision READ revision NOTIFY revisionChanged)

public:
    explicit Thumbnailer(QObject *parent = nullptr);
    ~Thumbnailer() override;

    QString source() const { return m_source; }
    void setSource(const QString &source);
    double duration() const { return m_duration; }
    void setDuration(double duration);
    int revision() const { return m_revision; }

    // URL of the best preview for `seconds`: the exact slot if ready, otherwise
    // the nearest finished one. Requests the exact slot if it is missing.
    Q_INVOKABLE QString thumbnail(double seconds);

    static QString cacheRoot();
    // Removes preview folders that have not been used for `maxAgeDays`.
    static void cleanupCache(int maxAgeDays, qint64 maxBytes = 512LL * 1024 * 1024);

signals:
    void sourceChanged();
    void durationChanged();
    void revisionChanged();

private:
    void restart();
    void onSlotReady(quint64 generation, int slot, const QString &file);

    QString m_source;
    double m_duration = 0;
    int m_revision = 0;
    quint64 m_generation = 0;
    double m_slotLength = 1;
    int m_slotCount = 0;
    QHash<int, QString> m_ready;
    QTimer m_prefillDelay;
    QTimer m_touchTimer;
    QString m_cacheDir;
    ThumbnailWorker *m_worker = nullptr;
};

class ThumbnailWorker : public QThread
{
    Q_OBJECT
public:
    struct Job {
        quint64 generation = 0;
        QString path;
        QString dir;
        double slotLength = 1;
        int slotCount = 0;
        double duration = 0;
        int width = 320;
    };

    void setJob(const Job &job, const QHash<int, QString> &existing);
    void request(int slot);
    void allowPrefill();
    void stop();

signals:
    void slotReady(quint64 generation, int slot, const QString &file);

protected:
    void run() override;

private:
    int takeSlot(bool *demanded);

    QMutex m_mutex;
    QWaitCondition m_wake;
    Job m_job;
    bool m_quit = false;
    bool m_prefill = false;
    std::deque<int> m_demand;
    std::vector<int> m_order;
    size_t m_orderPos = 0;
    std::vector<char> m_done;
    std::vector<char> m_attempts;
    std::atomic<quint64> m_generation {0};
    std::atomic<bool> m_stopping {false};
};
