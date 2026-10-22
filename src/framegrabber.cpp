#include "framegrabber.h"

#include <QTransform>

#include <algorithm>
#include <array>
#include <cmath>
#include <vector>

extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/display.h>
#include <libswscale/swscale.h>
}

namespace {

// Linear light (in units of 100 nits) for a 12-bit HDR code value.
struct HdrCurves {
    std::array<float, 4096> pq {};
    std::array<float, 4096> hlg {};

    HdrCurves()
    {
        constexpr double m1 = 2610.0 / 16384.0;
        constexpr double m2 = 2523.0 / 4096.0 * 128.0;
        constexpr double c1 = 3424.0 / 4096.0;
        constexpr double c2 = 2413.0 / 4096.0 * 32.0;
        constexpr double c3 = 2392.0 / 4096.0 * 32.0;
        constexpr double unit = 100.0; // nits per 1.0 of output
        constexpr double a = 0.17883277, b = 0.28466892, c = 0.55991073;
        for (int i = 0; i < 4096; ++i) {
            const double e = i / 4095.0;
            const double p = std::pow(e, 1.0 / m2);
            const double nits = 10000.0 * std::pow(std::max(p - c1, 0.0) / (c2 - c3 * p), 1.0 / m1);
            pq[i] = static_cast<float>(nits / unit);
            const double scene = e <= 0.5 ? e * e / 3.0 : (std::exp((e - c) / a) + b) / 12.0;
            hlg[i] = static_cast<float>(scene * 1000.0 / unit);
        }
    }
};

const HdrCurves &hdrCurves()
{
    static const HdrCurves curves;
    return curves;
}

int swsColorspace(const AVFrame *f, bool hdr)
{
    switch (f->colorspace) {
    case AVCOL_SPC_BT709: return SWS_CS_ITU709;
    case AVCOL_SPC_BT2020_NCL:
    case AVCOL_SPC_BT2020_CL: return SWS_CS_BT2020;
    case AVCOL_SPC_SMPTE170M:
    case AVCOL_SPC_BT470BG: return SWS_CS_ITU601;
    case AVCOL_SPC_SMPTE240M: return SWS_CS_SMPTE240M;
    case AVCOL_SPC_FCC: return SWS_CS_FCC;
    default:
        if (hdr)
            return SWS_CS_BT2020;
        return f->height >= 720 ? SWS_CS_ITU709 : SWS_CS_ITU601;
    }
}

uint8_t toSdr8(float v)
{
    v = std::clamp(v, 0.0f, 1.0f);
    return static_cast<uint8_t>(std::lround(std::pow(v, 1.0f / 2.2f) * 255.0f));
}

} // namespace

FrameGrabber::FrameGrabber(const QString &path, std::function<bool()> cancelled)
    : m_cancelled(std::move(cancelled))
{
    m_operation.start();
    m_format = avformat_alloc_context();
    if (!m_format)
        return;
    m_format->interrupt_callback = {&FrameGrabber::interrupt, this};
    if (avformat_open_input(&m_format, path.toUtf8().constData(), nullptr, nullptr) < 0) {
        m_format = nullptr;
        return;
    }
    if (avformat_find_stream_info(m_format, nullptr) < 0)
        return;

    for (unsigned i = 0; i < m_format->nb_streams; ++i) {
        const AVStream *st = m_format->streams[i];
        if (st->codecpar->codec_type != AVMEDIA_TYPE_VIDEO)
            continue;
        if (st->disposition & AV_DISPOSITION_ATTACHED_PIC) {
            if (m_coverStream < 0)
                m_coverStream = static_cast<int>(i);
        } else if (m_stream < 0) {
            m_stream = static_cast<int>(i);
        }
    }

    if (m_format->duration != AV_NOPTS_VALUE)
        m_duration = m_format->duration / static_cast<double>(AV_TIME_BASE);
    if (m_stream < 0)
        return;

    AVStream *st = m_format->streams[m_stream];
    if (m_duration <= 0 && st->duration != AV_NOPTS_VALUE)
        m_duration = st->duration * av_q2d(st->time_base);

    if (const AVPacketSideData *sd = av_packet_side_data_get(st->codecpar->coded_side_data, st->codecpar->nb_coded_side_data, AV_PKT_DATA_DISPLAYMATRIX)) {
        if (sd->size >= 9 * sizeof(int32_t)) {
            const double r = av_display_rotation_get(reinterpret_cast<const int32_t *>(sd->data));
            if (!std::isnan(r))
                m_rotation = r;
        }
    }

    const AVCodec *codec = avcodec_find_decoder(st->codecpar->codec_id);
    if (!codec)
        return;
    AVCodecContext *ctx = avcodec_alloc_context3(codec);
    if (!ctx)
        return;
    if (avcodec_parameters_to_context(ctx, st->codecpar) < 0) {
        avcodec_free_context(&ctx);
        return;
    }
    ctx->thread_count = 1;
    ctx->skip_frame = AVDISCARD_NONKEY;
    ctx->skip_loop_filter = AVDISCARD_ALL;
    ctx->flags2 |= AV_CODEC_FLAG2_FAST;
    if (avcodec_open2(ctx, codec, nullptr) < 0) {
        avcodec_free_context(&ctx);
        return;
    }
    m_codec = ctx;
    m_packet = av_packet_alloc();
    m_frame = av_frame_alloc();
    if (!m_packet || !m_frame)
        avcodec_free_context(&m_codec);
}

bool FrameGrabber::interrupted() const
{
    return (m_cancelled && m_cancelled()) || m_operation.elapsed() >= 5000;
}

int FrameGrabber::interrupt(void *opaque)
{
    return static_cast<FrameGrabber *>(opaque)->interrupted() ? 1 : 0;
}

FrameGrabber::~FrameGrabber()
{
    sws_freeContext(m_sws);
    av_frame_free(&m_frame);
    av_packet_free(&m_packet);
    avcodec_free_context(&m_codec);
    avformat_close_input(&m_format);
}

bool FrameGrabber::seek(double seconds)
{
    m_operation.restart();
    if (interrupted()) return false;
    AVStream *st = m_format->streams[m_stream];
    int64_t ts = av_rescale_q(std::llround(seconds * AV_TIME_BASE), AV_TIME_BASE_Q, st->time_base);
    if (st->start_time != AV_NOPTS_VALUE)
        ts += st->start_time;
    if (av_seek_frame(m_format, m_stream, ts, AVSEEK_FLAG_BACKWARD) < 0) {
        int64_t t = std::llround(seconds * AV_TIME_BASE);
        if (m_format->start_time != AV_NOPTS_VALUE)
            t += m_format->start_time;
        if (avformat_seek_file(m_format, -1, INT64_MIN, t, t, 0) < 0)
            return false;
    }
    avcodec_flush_buffers(m_codec);
    return true;
}

double FrameGrabber::keyframeBefore(double seconds)
{
    if (!isOpen() || !seek(seconds))
        return -1;
    const AVStream *st = m_format->streams[m_stream];
    for (int guard = 0; guard < 4000 && !interrupted(); ++guard) {
        if (av_read_frame(m_format, m_packet) < 0)
            break;
        const bool match = m_packet->stream_index == m_stream && (m_packet->flags & AV_PKT_FLAG_KEY);
        int64_t ts = m_packet->pts != AV_NOPTS_VALUE ? m_packet->pts : m_packet->dts;
        av_packet_unref(m_packet);
        if (match && ts != AV_NOPTS_VALUE) {
            if (st->start_time != AV_NOPTS_VALUE)
                ts -= st->start_time;
            return ts * av_q2d(st->time_base);
        }
    }
    return -1;
}

QImage FrameGrabber::grab(double seconds, int width, double *frameTime)
{
    if (!isOpen() || !seek(seconds))
        return {};

    const AVStream *st = m_format->streams[m_stream];
    bool started = false;
    bool got = false;
    int sent = 0;
    for (int guard = 0; guard < 4000 && !got && !interrupted(); ++guard) {
        if (av_read_frame(m_format, m_packet) < 0) {
            avcodec_send_packet(m_codec, nullptr);
            got = avcodec_receive_frame(m_codec, m_frame) == 0;
            break;
        }
        if (m_packet->stream_index != m_stream || (!started && !(m_packet->flags & AV_PKT_FLAG_KEY))) {
            av_packet_unref(m_packet);
            continue;
        }
        started = true;
        const int err = avcodec_send_packet(m_codec, m_packet);
        av_packet_unref(m_packet);
        if (err < 0 && err != AVERROR(EAGAIN))
            continue;
        got = avcodec_receive_frame(m_codec, m_frame) == 0;
        // Decoders with reordering delay may hold the key frame back; drain them.
        if (!got && ++sent >= 32) {
            avcodec_send_packet(m_codec, nullptr);
            got = avcodec_receive_frame(m_codec, m_frame) == 0;
            break;
        }
    }
    if (!got)
        return {};

    if (frameTime) {
        int64_t ts = m_frame->best_effort_timestamp;
        if (ts != AV_NOPTS_VALUE && st->start_time != AV_NOPTS_VALUE)
            ts -= st->start_time;
        *frameTime = ts != AV_NOPTS_VALUE ? ts * av_q2d(st->time_base) : seconds;
    }
    QImage image = convert(m_frame, width);
    av_frame_unref(m_frame);
    return image;
}

QImage FrameGrabber::convert(const AVFrame *f, int width)
{
    const int srcW = f->width;
    const int srcH = f->height;
    if (srcW <= 0 || srcH <= 0 || width <= 0 || interrupted())
        return {};

    AVRational sar = f->sample_aspect_ratio;
    if (sar.num <= 0 || sar.den <= 0)
        sar = AVRational {1, 1};
    const double aspect = srcW * av_q2d(sar) / srcH;
    const bool sideways = std::lround(std::fabs(m_rotation)) % 180 == 90;
    // Bound allocations even when a damaged file advertises an extreme aspect ratio.
    const int outW = static_cast<int>(std::clamp(sideways ? width * aspect : double(width), 2.0, 2048.0));
    const int outH = static_cast<int>(std::clamp(sideways ? double(width) : width / aspect, 2.0, 2048.0));

    const bool pq = f->color_trc == AVCOL_TRC_SMPTE2084;
    const bool hlg = f->color_trc == AVCOL_TRC_ARIB_STD_B67;
    const bool hdr = pq || hlg;

    m_sws = sws_getCachedContext(m_sws, srcW, srcH, static_cast<AVPixelFormat>(f->format), outW, outH,
                                 hdr ? AV_PIX_FMT_RGB48 : AV_PIX_FMT_RGB24, SWS_AREA, nullptr, nullptr, nullptr);
    if (!m_sws)
        return {};
    const int *coefficients = sws_getCoefficients(swsColorspace(f, hdr));
    sws_setColorspaceDetails(m_sws, coefficients, f->color_range == AVCOL_RANGE_JPEG ? 1 : 0,
                             sws_getCoefficients(SWS_CS_DEFAULT), 1, 0, 1 << 16, 1 << 16);

    QImage image(outW, outH, QImage::Format_RGB888);
    if (image.isNull()) return {};
    if (!hdr) {
        uint8_t *dst[4] = {image.bits(), nullptr, nullptr, nullptr};
        int dstStride[4] = {static_cast<int>(image.bytesPerLine()), 0, 0, 0};
        sws_scale(m_sws, f->data, f->linesize, 0, srcH, dst, dstStride);
    } else {
        std::vector<uint16_t> rgb(static_cast<size_t>(outW) * outH * 3);
        uint8_t *dst[4] = {reinterpret_cast<uint8_t *>(rgb.data()), nullptr, nullptr, nullptr};
        int dstStride[4] = {outW * 6, 0, 0, 0};
        sws_scale(m_sws, f->data, f->linesize, 0, srcH, dst, dstStride);

        // BT.2020 -> BT.709 primaries, then an extended Reinhard curve that maps
        // a ~1000 nit peak to SDR white while preserving hue.
        const auto &lut = pq ? hdrCurves().pq : hdrCurves().hlg;
        constexpr float peak = 1000.0f / 100.0f;
        for (int y = 0; y < outH; ++y) {
            const uint16_t *src = rgb.data() + static_cast<size_t>(y) * outW * 3;
            uchar *line = image.scanLine(y);
            for (int x = 0; x < outW; ++x) {
                float r = lut[src[x * 3] >> 4];
                float g = lut[src[x * 3 + 1] >> 4];
                float b = lut[src[x * 3 + 2] >> 4];
                if (hlg) {
                    // HLG system gamma (OOTF) for a 1000 nit display.
                    const float ys = 0.2627f * r + 0.6780f * g + 0.0593f * b;
                    const float k = std::pow(std::max(ys * 100.0f / 1000.0f, 1e-6f), 0.2f);
                    r *= k;
                    g *= k;
                    b *= k;
                }
                const float r7 = std::max(0.0f, 1.6605f * r - 0.5876f * g - 0.0728f * b);
                const float g7 = std::max(0.0f, -0.1246f * r + 1.1329f * g - 0.0083f * b);
                const float b7 = std::max(0.0f, -0.0182f * r - 0.1006f * g + 1.1187f * b);
                const float m = std::max({r7, g7, b7});
                const float scale = m > 0 ? (1.0f + m / (peak * peak)) / (1.0f + m) : 0.0f;
                line[x * 3] = toSdr8(r7 * scale);
                line[x * 3 + 1] = toSdr8(g7 * scale);
                line[x * 3 + 2] = toSdr8(b7 * scale);
            }
        }
    }

    if (m_rotation != 0)
        image = image.transformed(QTransform().rotate(-m_rotation));
    return image;
}

QImage FrameGrabber::coverArt() const
{
    if (!m_format || m_coverStream < 0)
        return {};
    const AVPacket &pic = m_format->streams[m_coverStream]->attached_pic;
    if (!pic.data || pic.size <= 0)
        return {};
    return QImage::fromData(QByteArrayView(pic.data, pic.size));
}
