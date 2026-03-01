namespace IIS_Site_Manager.API.Models;

public record SystemMetrics(
    double CpuUsagePercent,
    double MemoryUsagePercent,
    long MemoryUsedBytes,
    long MemoryTotalBytes,
    double BytesReceivedPerSec,
    double BytesSentPerSec,
    double BytesTotalPerSec,
    DateTime Timestamp
);
