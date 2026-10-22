#pragma once

#include <QHash>
#include <QSet>
#include <QObject>
#include <QTimer>
#include <QVariant>
#include <QtQml/qqmlregistration.h>

class QQmlEngine;
class QJSEngine;

// Remembers where each file was left off, like YouTube's watch progress.
class History : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)

public:
    static History *instance();
    static History *create(QQmlEngine *, QJSEngine *);
    explicit History(QObject *parent = nullptr, const QString &storageFile = {});
    QString lastError() const { return m_lastError; }

    // Position to resume from, or 0 when the file should start from the top.
    Q_INVOKABLE double resumePosition(const QString &path) const;
    // Watched fraction in [0, 1] for progress bars on thumbnails.
    Q_INVOKABLE double progress(const QString &path) const;
    Q_INVOKABLE void update(const QString &path, double position, double duration);
    Q_INVOKABLE void markFinished(const QString &path, double duration);
    // Most recently watched files that still exist, newest first.
    Q_INVOKABLE QVariantList recent(int max) const;
    Q_INVOKABLE void remove(const QString &path);
    Q_INVOKABLE void clear();
    Q_INVOKABLE bool save();

signals:
    void changed(const QString &path);
    void lastErrorChanged();

private:
    struct Entry;
    void load();
    bool readEntries(QHash<QString, Entry> &entries, QString &error) const;
    void setError(const QString &error);
    void scheduleSave();

    struct Entry {
        double position = 0;
        double duration = 0;
        bool finished = false;
        qint64 updated = 0;
    };
    QHash<QString, Entry> m_entries;
    QSet<QString> m_dirty;
    QSet<QString> m_removed;
    bool m_clearPending = false;
    QTimer m_saveTimer;
    QString m_file;
    QString m_lastError;
};
