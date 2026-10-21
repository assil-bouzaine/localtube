#include "history.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJSEngine>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QStandardPaths>

#include <algorithm>

namespace {
constexpr int kMaxEntries = 1500;
}

History *History::instance()
{
    static History *history = new History;
    return history;
}

History *History::create(QQmlEngine *, QJSEngine *)
{
    QJSEngine::setObjectOwnership(instance(), QJSEngine::CppOwnership);
    return instance();
}

History::History(QObject *parent)
    : QObject(parent)
{
    m_file = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/localtube/history.json");
    m_saveTimer.setSingleShot(true);
    m_saveTimer.setInterval(2000);
    connect(&m_saveTimer, &QTimer::timeout, this, &History::save);
    load();
}

void History::load()
{
    QFile file(m_file);
    if (!file.open(QIODevice::ReadOnly))
        return;
    const QJsonArray items = QJsonDocument::fromJson(file.readAll()).object().value(QStringLiteral("items")).toArray();
    for (const QJsonValue &v : items) {
        const QJsonObject o = v.toObject();
        Entry e;
        e.position = o.value(QStringLiteral("position")).toDouble();
        e.duration = o.value(QStringLiteral("duration")).toDouble();
        e.finished = o.value(QStringLiteral("finished")).toBool();
        e.updated = static_cast<qint64>(o.value(QStringLiteral("updated")).toDouble());
        m_entries.insert(o.value(QStringLiteral("path")).toString(), e);
    }
}

void History::save()
{
    m_saveTimer.stop();
    QList<QPair<QString, Entry>> items;
    items.reserve(m_entries.size());
    for (auto it = m_entries.cbegin(); it != m_entries.cend(); ++it)
        items.append({it.key(), it.value()});
    std::sort(items.begin(), items.end(), [](const auto &a, const auto &b) { return a.second.updated > b.second.updated; });
    if (items.size() > kMaxEntries)
        items.resize(kMaxEntries);

    QJsonArray array;
    for (const auto &[path, e] : items) {
        array.append(QJsonObject {
            {QStringLiteral("path"), path},
            {QStringLiteral("position"), e.position},
            {QStringLiteral("duration"), e.duration},
            {QStringLiteral("finished"), e.finished},
            {QStringLiteral("updated"), static_cast<double>(e.updated)},
        });
    }
    QDir().mkpath(QFileInfo(m_file).absolutePath());
    QSaveFile file(m_file);
    if (!file.open(QIODevice::WriteOnly))
        return;
    file.write(QJsonDocument(QJsonObject {{QStringLiteral("version"), 1}, {QStringLiteral("items"), array}}).toJson(QJsonDocument::Compact));
    file.commit();
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
    if (path.isEmpty() || duration <= 0)
        return;
    Entry &e = m_entries[path];
    e.position = position;
    e.duration = duration;
    e.finished = position >= duration - 1;
    e.updated = QDateTime::currentSecsSinceEpoch();
    emit changed(path);
    scheduleSave();
}

void History::markFinished(const QString &path, double duration)
{
    if (path.isEmpty())
        return;
    Entry &e = m_entries[path];
    e.position = 0;
    e.duration = duration > 0 ? duration : e.duration;
    e.finished = true;
    e.updated = QDateTime::currentSecsSinceEpoch();
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
        if (!QFileInfo::exists(path))
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
    if (m_entries.remove(path)) {
        emit changed(path);
        scheduleSave();
    }
}
