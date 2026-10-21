#pragma once

#include <QImage>
#include <QString>

struct AVFormatContext;
struct AVCodecContext;
struct AVPacket;
struct AVFrame;
struct SwsContext;

// Decodes single key frames from a media file with libavformat/libavcodec.
// Used for hover previews and playlist posters. Not thread-safe: use one
// instance per thread.
class FrameGrabber
{
public:
    explicit FrameGrabber(const QString &path);
    ~FrameGrabber();
    FrameGrabber(const FrameGrabber &) = delete;
    FrameGrabber &operator=(const FrameGrabber &) = delete;

    bool isOpen() const { return m_codec != nullptr; }
    double duration() const { return m_duration; }

    // Position (seconds) of the first key frame at or before `seconds`, read
    // from the container without decoding. Returns a negative value if unknown.
    double keyframeBefore(double seconds);
    // Decodes the key frame at or before `seconds`, scaled to `width` pixels.
    // HDR (PQ/HLG) sources are tone-mapped to SDR.
    QImage grab(double seconds, int width, double *frameTime = nullptr);
    // Embedded cover art (e.g. from yt-dlp --embed-thumbnail), if any.
    QImage coverArt() const;

private:
    QImage convert(const AVFrame *frame, int width);
    bool seek(double seconds);

    AVFormatContext *m_format = nullptr;
    AVCodecContext *m_codec = nullptr;
    AVPacket *m_packet = nullptr;
    AVFrame *m_frame = nullptr;
    SwsContext *m_sws = nullptr;
    int m_stream = -1;
    int m_coverStream = -1;
    double m_duration = 0;
    double m_rotation = 0;
};
