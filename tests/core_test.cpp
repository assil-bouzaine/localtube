#include "history.h"
#include "playlistmodel.h"
#include "seekqueue.h"
#include "framegrabber.h"
#include "thumbnailer.h"
#include "mpvobject.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QProcess>
#include <QProcessEnvironment>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QLockFile>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QtTest>

#include <limits>

class CoreTest : public QObject
{
    Q_OBJECT
private slots:
    void committedSeekCancelsPendingPreview()
    {
        SeekQueue queue;
        QCOMPARE(queue.request(10), std::optional<double>(10));
        QVERIFY(!queue.request(20));
        QVERIFY(!queue.request(30));
        queue.cancel(); // Progress-bar release, another seek, or a new file.
        QVERIFY(!queue.completed());
        QCOMPARE(queue.request(50), std::optional<double>(50));
    }

    void previewUsesLatestTarget()
    {
        SeekQueue queue;
        QVERIFY(queue.request(10));
        QVERIFY(!queue.request(20));
        QVERIFY(!queue.request(30));
        QCOMPARE(queue.completed(), std::optional<double>(30));
        QVERIFY(!queue.completed());
    }

    void historyMergesIndependentWriters()
    {
        QTemporaryDir dir;
        const QString path = dir.filePath("history.json");
        History first(nullptr, path), second(nullptr, path);
        first.update("a.mp4", 20, 100);
        second.update("b.mp4", 40, 100);
        QVERIFY(first.save());
        QVERIFY(second.save());
        History restored(nullptr, path);
        QCOMPARE(restored.resumePosition("a.mp4"), 20);
        QCOMPARE(restored.resumePosition("b.mp4"), 40);
    }

    void historyDoesNotResurrectRemovedEntries()
    {
        QTemporaryDir dir;
        const QString path = dir.filePath("history.json");
        History first(nullptr, path);
        first.update("a.mp4", 20, 100);
        QVERIFY(first.save());
        History second(nullptr, path);
        first.remove("a.mp4");
        QVERIFY(first.save());
        second.update("b.mp4", 40, 100);
        QVERIFY(second.save());
        History restored(nullptr, path);
        QCOMPARE(restored.resumePosition("a.mp4"), 0);
        QCOMPARE(restored.resumePosition("b.mp4"), 40);
    }

    void historyRetriesAfterLockContention()
    {
        QTemporaryDir dir;
        const QString path = dir.filePath("history.json");
        History history(nullptr, path);
        QLockFile lock(path + ".lock");
        QVERIFY(lock.tryLock());
        history.update("a.mp4", 20, 100);
        QVERIFY(!history.save());
        QVERIFY(!history.lastError().isEmpty());
        lock.unlock();
        QVERIFY(history.save());
        QVERIFY(history.lastError().isEmpty());
        History restored(nullptr, path);
        QCOMPARE(restored.resumePosition("a.mp4"), 20);
    }

    void damagedHistoryIsPreserved()
    {
        QTemporaryDir dir;
        const QString path = dir.filePath("history.json");
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write("damaged history");
        file.close();
        History history(nullptr, path);
        history.update("a.mp4", 20, 100);
        QVERIFY(!history.save());
        QVERIFY(file.open(QIODevice::ReadOnly));
        QCOMPARE(file.readAll(), QByteArray("damaged history"));
    }

    void continueWatchingExcludesFinishedVideos()
    {
        QTemporaryDir dir;
        const QString media = dir.filePath("a.mp4");
        QFile file(media);
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.close();
        History history(nullptr, dir.filePath("history.json"));
        history.update(media, 20, 100);
        QCOMPARE(history.recent(12).size(), 1);
        history.markFinished(media, 100);
        QVERIFY(history.recent(12).isEmpty());
        history.update(media, std::numeric_limits<double>::quiet_NaN(), 100);
        QCOMPARE(history.resumePosition(media), 0);
        history.clear();
        QVERIFY(history.save());
        History restored(nullptr, dir.filePath("history.json"));
        QCOMPARE(restored.progress(media), 0);
    }

    void playlistScanAndSearchPreservePlaybackOrder()
    {
        QTemporaryDir dir;
        for (const QString &name : {"Video 10.mp4", "Video 2.mp4", "Video 1.mp4"}) {
            QFile file(dir.filePath(name));
            QVERIFY(file.open(QIODevice::WriteOnly));
        }
        PlaylistModel playlist;
        QSignalSpy opened(&playlist, &PlaylistModel::opened);
        playlist.open({dir.path()});
        QVERIFY(playlist.busy());
        QTRY_COMPARE(opened.size(), 1);
        QCOMPARE(playlist.count(), 3);
        QCOMPARE(playlist.titleAt(1), QString("Video 2"));
        PlaylistFilter filter;
        filter.setPlaylist(&playlist);
        filter.setQuery("VIDEO 2");
        QCOMPARE(filter.rowCount(), 1);
        QCOMPARE(filter.data(filter.index(0, 0), PlaylistModel::SourceIndexRole).toInt(), 1);
        QCOMPARE(filter.filteredIndex(1), 0);
        QCOMPARE(filter.filteredIndex(0), -1);
        QCOMPARE(playlist.titleAt(0), QString("Video 1"));
    }

    void newerOpenRequestWins()
    {
        QTemporaryDir dir;
        const QString path = dir.filePath("a.mp4");
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.close();
        PlaylistModel playlist;
        QSignalSpy opened(&playlist, &PlaylistModel::opened);
        QSignalSpy failed(&playlist, &PlaylistModel::openFailed);
        playlist.open({dir.path()});
        playlist.open({dir.filePath("missing.mp4")});
        QTRY_COMPARE(failed.size(), 1);
        QCOMPARE(opened.size(), 0);
        QVERIFY(!playlist.busy());
    }

    void frameGrabberHonorsCancellation()
    {
        FrameGrabber grabber("/does/not/exist.mp4", [] { return true; });
        QVERIFY(!grabber.isOpen());
        QVERIFY(grabber.grab(0, 320).isNull());
    }

    void playbackCommitsSeekAndReportsCommandFailures()
    {
        QTemporaryDir dir;
        const QString media = dir.filePath("sample.mp4");
        QCOMPARE(QProcess::execute("ffmpeg", {"-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i",
                                              "color=size=160x90:rate=24", "-t", "40", "-c:v", "mpeg4", media}), 0);
        MpvObject::setDefaultOptions({{"vo", "null"}, {"ao", "null"}, {"config", "no"},
                                     {"load-scripts", "no"}, {"keep-open", "yes"}, {"idle", "yes"}, {"hwdec", "no"}});
        MpvObject player;
        QSignalSpy failed(&player, &MpvObject::commandFailed);
        QSignalSpy succeeded(&player, &MpvObject::commandSucceeded);
        player.loadFile(media, 0, true);
        QTRY_VERIFY_WITH_TIMEOUT(player.fileLoaded(), 5000);
        player.scrub(5);
        player.scrub(10);
        player.scrub(15);
        player.seekTo(20, true);
        QTRY_VERIFY_WITH_TIMEOUT(std::abs(player.position() - 20) < 0.25, 5000);
        // Flush later playback-restart events, which used to submit a stale preview.
        QTest::qWait(150);
        QVERIFY(std::abs(player.position() - 20) < 0.25);
        QVERIFY(!succeeded.isEmpty());
        // Force a filesystem error regardless of the output's screenshot support.
        player.setOption("screenshot-directory", "/dev/null/localtube");
        player.screenshot();
        QTRY_VERIFY(!failed.isEmpty());
        QCOMPARE(failed.last().first().toString(), QString("screenshot"));
        QVERIFY(!failed.last().at(1).toString().isEmpty());
    }

    void cacheBudgetIncludesPosters()
    {
        const QString posters = Thumbnailer::cacheRoot() + "/posters";
        QVERIFY(QDir().mkpath(posters));
        QFile file(posters + "/budget-test.jpg");
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write(QByteArray(128, 'x'));
        QVERIFY(file.flush());
        QVERIFY(file.setFileTime(QDateTime::currentDateTime().addDays(-1), QFileDevice::FileModificationTime));
        file.close();
        Thumbnailer::cleanupCache(45, 0);
        QVERIFY(!file.exists());
    }

    void homeKeyboardRemovalWorksInTheApplication()
    {
        QTemporaryDir dir;
        const QString media = dir.filePath("sample.mp4");
        QFile file(media);
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.close();
        QVERIFY(QDir().mkpath(dir.filePath("data/localtube")));
        QVERIFY(QDir().mkpath(dir.filePath("home-controls")));
        const QString historyPath = dir.filePath("data/localtube/history.json");
        History history(nullptr, historyPath);
        history.update(media, 20, 100);
        QVERIFY(history.save());

        QProcess process;
        auto environment = QProcessEnvironment::systemEnvironment();
        environment.insert("QT_QPA_PLATFORM", "offscreen");
        environment.insert("QT_QUICK_BACKEND", "software");
        environment.insert("LOCALTUBE_DEBUG", "1");
        environment.insert("XDG_DATA_HOME", dir.filePath("data"));
        environment.insert("XDG_CACHE_HOME", dir.filePath("cache"));
        environment.insert("XDG_CONFIG_HOME", dir.filePath("config"));
        process.setProcessEnvironment(environment);
        process.start(QStringLiteral(LOCALTUBE_EXECUTABLE), {"--self-test", dir.filePath("home-controls")});
        QVERIFY(process.waitForFinished(10000));
        const QByteArray diagnostics = process.readAllStandardError();
        QVERIFY2(process.exitStatus() == QProcess::NormalExit && process.exitCode() == 0, diagnostics.constData());
        QVERIFY2(!diagnostics.contains("[qml]"), diagnostics.constData());
        QVERIFY(QFile::exists(dir.filePath("home-controls/home_after_remove.png")));
        QFile saved(historyPath);
        QVERIFY(saved.open(QIODevice::ReadOnly));
        QVERIFY(QJsonDocument::fromJson(saved.readAll()).object().value("items").toArray().isEmpty());
    }
};

int main(int argc, char **argv)
{
    // Never read or write the developer's actual history, settings or cache.
    QTemporaryDir storage;
    if (!storage.isValid()) return 1;
    qputenv("XDG_DATA_HOME", storage.path().toUtf8());
    qputenv("XDG_CACHE_HOME", storage.path().toUtf8());
    qputenv("XDG_CONFIG_HOME", storage.path().toUtf8());
    QGuiApplication app(argc, argv);
    CoreTest test;
    return QTest::qExec(&test, argc, argv);
}

#include "core_test.moc"
