#pragma once

#include <QHash>
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

public:
    static History *instance();
    static History *create(QQmlEngine *, QJSEngine *);

    // Position to resume from, or 0 when the file should start from the top.
    Q_INVOKABLE double resumePosition(const QString &path) const;
    // Watched fraction in [0, 1] for progress bars on thumbnails.
    Q_INVOKABLE double progress(const QString &path) const;
    Q_INVOKABLE void update(const QString &path, double position, double duration);
    Q_INVOKABLE void markFinished(const QString &path, double duration);
    // Most recently watched files that still exist, newest first.
    Q_INVOKABLE QVariantList recent(int max) const;
    Q_INVOKABLE void remove(const QString &path);
    Q_INVOKABLE void save();

signals:
    void changed(const QString &path);

private:
    explicit History(QObject *parent = nullptr);
    void load();
    void scheduleSave();

    struct Entry {
        double position = 0;
        double duration = 0;
        bool finished = false;
        qint64 updated = 0;
    };
    QHash<QString, Entry> m_entries;
    QTimer m_saveTimer;
    QString m_file;
};
