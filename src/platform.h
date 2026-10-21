#pragma once

#include <QJsonObject>
#include <QObject>
#include <QQuickWindow>
#include <QRect>
#include <QStringList>
#include <QtQml/qqmlregistration.h>

class QQmlEngine;
class QJSEngine;

// Desktop integration for QML: dialogs, clipboard, idle inhibition, Hyprland
// window management, plus a small input-automation API for self-tests.
class Platform : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QStringList initialFiles READ initialFiles CONSTANT)
    Q_PROPERTY(bool startFullscreen READ startFullscreen CONSTANT)
    Q_PROPERTY(QString settingsFile READ settingsFile CONSTANT)
    Q_PROPERTY(QString selfTestDir READ selfTestDir CONSTANT)
    Q_PROPERTY(bool hyprland READ hyprland CONSTANT)
    Q_PROPERTY(QString version READ version CONSTANT)

public:
    static Platform *instance();
    static Platform *create(QQmlEngine *, QJSEngine *);

    void configure(const QStringList &files, bool fullscreen, const QString &selfTestDir);

    QStringList initialFiles() const { return m_initialFiles; }
    bool startFullscreen() const { return m_startFullscreen; }
    QString settingsFile() const;
    QString selfTestDir() const { return m_selfTestDir; }
    bool hyprland() const;
    QString version() const;

    Q_INVOKABLE QStringList openFiles(const QString &startDir);
    Q_INVOKABLE QString openFolder(const QString &startDir);
    Q_INVOKABLE QString openSubtitle(const QString &startDir);
    Q_INVOKABLE void copyText(const QString &text);
    Q_INVOKABLE void showInFolder(const QString &path);
    Q_INVOKABLE void inhibitIdle(bool inhibit);
    // Floats, pins and shrinks the window into a corner (Hyprland), or restores it.
    Q_INVOKABLE bool setMiniplayer(QWindow *window, bool enabled);

    Q_INVOKABLE static QString fileUrl(const QString &path);
    Q_INVOKABLE static QString localPath(const QUrl &url);
    Q_INVOKABLE static QString fileName(const QString &path);
    Q_INVOKABLE static QString dirName(const QString &path);
    Q_INVOKABLE static QString formatSize(qint64 bytes);
    Q_INVOKABLE static qint64 fileSize(const QString &path);

    Q_INVOKABLE bool grab(QQuickWindow *window, const QString &file);
    Q_INVOKABLE void mouseMove(QQuickWindow *window, qreal x, qreal y);
    Q_INVOKABLE void mouseClick(QQuickWindow *window, qreal x, qreal y, int button = 1);
    Q_INVOKABLE void mousePress(QQuickWindow *window, qreal x, qreal y);
    Q_INVOKABLE void mouseRelease(QQuickWindow *window, qreal x, qreal y);
    Q_INVOKABLE void key(QQuickWindow *window, int key, int modifiers = 0, const QString &text = {});
    Q_INVOKABLE void log(const QString &message);
    Q_INVOKABLE void quit(int code);

private:
    explicit Platform(QObject *parent = nullptr);
    QJsonObject hyprClient() const;
    bool hyprlandLua() const;

    QStringList m_initialFiles;
    bool m_startFullscreen = false;
    QString m_selfTestDir;
    uint m_inhibitCookie = 0;
    bool m_inhibitWanted = false;
    bool m_inhibitPending = false;
    QJsonObject m_restoreState;
};
