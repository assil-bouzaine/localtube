#pragma once

#include <QElapsedTimer>
#include <optional>

// Coalesce drag previews. A committed seek must cancel all queued previews.
class SeekQueue
{
public:
    std::optional<double> request(double target)
    {
        if (m_active && m_timer.isValid() && m_timer.elapsed() < 1000) {
            m_pending = target;
            return {};
        }
        m_active = true;
        m_pending.reset();
        m_timer.start();
        return target;
    }

    std::optional<double> completed()
    {
        const auto target = m_pending;
        cancel();
        return target ? request(*target) : std::nullopt;
    }

    void cancel()
    {
        m_active = false;
        m_pending.reset();
        m_timer.invalidate();
    }

private:
    bool m_active = false;
    std::optional<double> m_pending;
    QElapsedTimer m_timer;
};
