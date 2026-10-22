#include "history.h"

#include <QDateTime>
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJSEngine>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QLockFile>
#include <QSaveFile>
#include <QStandardPaths>

#include <algorithm>
#include <cmath>

namespace {
constexpr int kMaxEntries = 1500;
}

History *History::instance()
{
    static History *history = new History(QCoreApplication::instance());
    return history;
}

History *History::create(QQmlEngine *, QJSEngine *)
{
    QJSEngine::setObjectOwnership(instance(), QJSEngine::CppOwnership);
    return instance();
}

History::History(QObject *parent, const QString &storageFile)
    : QObject(parent)
{
    m_file = storageFile.isEmpty()
                 ? QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/localtube/history.json")
                 : storageFile;
    m_saveTimer.setSingleShot(true);
    m_saveTimer.setInterval(2000);
    connect(&m_saveTimer, &QTimer::timeout, this, &History::save);
    load();
}

void History::load()
{
    QString error;
    if (!readEntries(m_entries, error))
        setError(error);
}

void History::setError(const QString &error)
{
    if (error == m_lastError)
        return;
    m_lastError = error;
    emit lastErrorChanged();
}

bool History::readEntries(QHash<QString, Entry> &entries, QString &error) const
{
    QFile file(m_file);
    if (!file.exists())
        return true;
    if (!file.open(QIODevice::ReadOnly)) {
        error = tr("Could not read watch history: %1").arg(file.errorString());
        return false;
    }
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &parseError);
    const QJsonObject root = document.object();
    if (parseError.error != QJsonParseError::NoError || !document.isObject()
        || root.value(QStringLiteral("version")).toInt() != 1 || !root.value(QStringLiteral("items")).isArray()) {
        error = tr("Watch history is damaged or uses an unsupported format. The existing file was preserved.");
        return false;
    }
    const QJsonArray items = root.value(QStringLiteral("items")).toArray();
    for (const QJsonValue &v : items) {
        const QJsonObject o = v.toObject();
        Entry e;
        e.position = o.value(QStringLiteral("position")).toDouble();
        e.duration = o.value(QStringLiteral("duration")).toDouble();
        e.finished = o.value(QStringLiteral("finished")).toBool();
        e.updated = static_cast<qint64>(o.value(QStringLiteral("updated")).toDouble());
        const QString path = o.value(QStringLiteral("path")).toString();
        if (!path.isEmpty() && std::isfinite(e.position) && std::isfinite(e.duration)
            && e.position >= 0 && e.duration >= 0)
            entries.insert(path, e);
    }
    return true;
}

bool History::save()
{
    m_saveTimer.stop();
    if (m_dirty.isEmpty() && m_removed.isEmpty() && !m_clearPending)
        return m_lastError.isEmpty();
    const auto fail = [this](const QString &error) {
        setError(error);
        m_saveTimer.start();
        return false;
    };
    if (!QDir().mkpath(QFileInfo(m_file).absolutePath()))
        return fail(tr("Could not create the watch history folder."));
    QLockFile lock(m_file + QStringLiteral(".lock"));
    if (!lock.tryLock(0))
        return fail(tr("Watch history is busy or cannot be locked. Saving will be retried."));
    QHash<QString, Entry> merged;
    QString error;
    if (!readEntries(merged, error))
        return fail(error);
    if (m_clearPending)
        merged.clear();
    for (const QString &path : m_removed)
        merged.remove(path);
    for (const QString &path : m_dirty)
        merged.insert(path, m_entries.value(path));
    QList<QPair<QString, Entry>> items;
    items.reserve(merged.size());
    for (auto it = merged.cbegin(); it != merged.cend(); ++it)
        items.append({it.key(), it.value()});
    std::sort(items.begin(), items.end(), [](const auto &a, const auto &b) { return a.second.updated > b.second.updated; });
    if (items.size() > kMaxEntries)
        items.resize(kMaxEntries);

    QJsonArray array;
    merged.clear();
    for (const auto &[path, e] : items) {
        merged.insert(path, e);
        array.append(QJsonObject {
            {QStringLiteral("path"), path},
            {QStringLiteral("position"), e.position},
            {QStringLiteral("duration"), e.duration},
            {QStringLiteral("finished"), e.finished},
            {QStringLiteral("updated"), static_cast<double>(e.updated)},
        });
    }
    QSaveFile file(m_file);
    if (!file.open(QIODevice::WriteOnly))
        return fail(tr("Could not save watch history: %1").arg(file.errorString()));
    const QByteArray data = QJsonDocument(QJsonObject {{QStringLiteral("version"), 1}, {QStringLiteral("items"), array}}).toJson(QJsonDocument::Compact);
    if (file.write(data) != data.size() || !file.commit())
        return fail(tr("Could not save watch history: %1").arg(file.errorString()));
    m_entries = merged;
    m_dirty.clear();
    m_removed.clear();
    m_clearPending = false;
    setError({});
    emit changed({});
    return true;
}

void History::scheduleSave()
{
    if (!m_saveTimer.isActive())
        m_saveTimer.start();
}

double History::resumePosition(const QString &path) const
{
    const auto it = m_entries.constFind(path);
    if (it == m_entries.cend() || it->finished)
        return 0;
    // Like YouTube: skip the resume if barely started or nearly finished.
    if (it->position < 5 || (it->duration > 0 && it->position > it->duration - 10))
        return 0;
    return it->position;
}

double History::progress(const QString &path) const
{
    const auto it = m_entries.constFind(path);
    if (it == m_entries.cend())
        return 0;
    if (it->finished)
        return 1;
    return it->duration > 0 ? std::clamp(it->position / it->duration, 0.0, 1.0) : 0;
}

void History::update(const QString &path, double position, double duration)
{
    if (path.isEmpty() || !std::isfinite(position) || !std::isfinite(duration) || duration <= 0)
        return;
    Entry &e = m_entries[path];
    e.position = std::clamp(position, 0.0, duration);
    e.duration = duration;
    e.finished = e.position >= duration - 1;
    e.updated = QDateTime::currentSecsSinceEpoch();
    m_dirty.insert(path);
    m_removed.remove(path);
    emit changed(path);
    scheduleSave();
}

void History::markFinished(const QString &path, double duration)
{
    if (path.isEmpty() || !std::isfinite(duration))
        return;
    Entry &e = m_entries[path];
    e.position = 0;
    e.duration = duration > 0 ? duration : e.duration;
    e.finished = true;
    e.updated = QDateTime::currentSecsSinceEpoch();
    m_dirty.insert(path);
    m_removed.remove(path);
    emit changed(path);
    scheduleSave();
}

QVariantList History::recent(int max) const
{
    QList<QPair<QString, Entry>> items;
    for (auto it = m_entries.cbegin(); it != m_entries.cend(); ++it)
        items.append({it.key(), it.value()});
    std::sort(items.begin(), items.end(), [](const auto &a, const auto &b) { return a.second.updated > b.second.updated; });

    QVariantList result;
    for (const auto &[path, e] : items) {
        if (result.size() >= max)
            break;
        if (e.finished || e.position < 5 || (e.duration > 0 && e.position > e.duration - 10)
            || !QFileInfo::exists(path))
            continue;
        result.append(QVariantMap {
            {QStringLiteral("path"), path},
            {QStringLiteral("position"), e.position},
            {QStringLiteral("duration"), e.duration},
            {QStringLiteral("progress"), e.finished ? 1.0 : (e.duration > 0 ? e.position / e.duration : 0.0)},
            {QStringLiteral("updated"), static_cast<double>(e.updated)},
        });
    }
    return result;
}

void History::remove(const QString &path)
{
    if (!path.isEmpty()) {
        m_entries.remove(path);
        m_dirty.remove(path);
        m_removed.insert(path);
        emit changed(path);
        scheduleSave();
    }
}

void History::clear()
{
    m_entries.clear();
    m_dirty.clear();
    m_removed.clear();
    m_clearPending = true;
    emit changed({});
    scheduleSave();
}
